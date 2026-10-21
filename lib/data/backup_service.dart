import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';

import '../core/prefs.dart';
import '../models/models.dart';
import 'database.dart';
import 'repository.dart';
import 'transaction_repository.dart';

const _magic = 'ME_ENC_01';
const _backupDb = 'BACKUP';
const _backupPref = 'BACKUP_PREF';
const _dataStoreFile = 'ui_settings.preferences_pb';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupImportResult {
  const BackupImportResult({
    required this.schemaVersion,
    required this.accounts,
    required this.transactions,
    required this.categories,
    required this.pictures,
    this.warnings = const [],
  });

  final int schemaVersion;
  final int accounts;
  final int transactions;
  final int categories;
  final int pictures;
  final List<String> warnings;
}

class BackupService {
  BackupService({
    required this.database,
    required this.repository,
    required this.preferences,
  });

  final AppDatabase database;
  final Repository repository;
  final AppPreferences preferences;

  Future<BackupImportResult> importFromFile(
    File file, {
    String? password,
  }) async {
    var bytes = await file.readAsBytes();
    if (_isEncrypted(bytes)) {
      if (password == null || password.isEmpty) {
        throw BackupException(
          'This backup is encrypted. Enter the password used in My Expenses.',
        );
      }
      bytes = await _decrypt(bytes, password);
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    final workingDir = Directory(p.join(
      database.supportDir.path,
      'restore-${DateTime.now().microsecondsSinceEpoch}',
    ));
    await workingDir.create(recursive: true);
    final pictures = <String, Uint8List>{};
    Uint8List? prefBytes;
    Uint8List? dataStoreBytes;
    try {
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = p.normalize(entry.name.replaceAll('\\', '/'));
        if (name.startsWith('..') || p.isAbsolute(name)) {
          throw BackupException('The backup contains an unsafe file path.');
        }
        final data = entry.content;
        if (name == _backupDb) {
          await File(p.join(workingDir.path, 'BACKUP')).writeAsBytes(data);
        } else if (name == _backupPref) {
          prefBytes = data;
        } else if (p.basename(name) == _dataStoreFile) {
          dataStoreBytes = data;
        } else if (name.isEmpty) {
          continue;
        } else if (name.toLowerCase().startsWith('pictures/')) {
          pictures[p.basename(name)] = data;
        }
      }
      final backupFile = File(p.join(workingDir.path, 'BACKUP'));
      if (!await backupFile.exists()) {
        throw BackupException(
          'This zip does not contain a My Expenses database (BACKUP).',
        );
      }
      final length = await backupFile.length();
      if (length < 16) {
        throw BackupException('The BACKUP file is not a valid SQLite database.');
      }
      final header =
          await backupFile.openRead(0, 16).expand((chunk) => chunk).toList();
      if (ascii.decode(header, allowInvalid: true) != 'SQLite format 3\u0000') {
        throw BackupException('The BACKUP file is not a valid SQLite database.');
      }

      final probe = await openDatabase(
        backupFile.path,
        readOnly: true,
        singleInstance: false,
      );
      int version;
      try {
        final versionRows = await probe.rawQuery('PRAGMA user_version');
        version = versionRows.isEmpty
            ? 0
            : asIntOr(versionRows.first.values.first, 0);
      } finally {
        await probe.close();
      }
      if (version < 140) {
        throw BackupException(
          'This backup uses a very old schema (version $version). Please '
          'restore it once with My Expenses 4.x so it can be upgraded.',
        );
      }

      await database.replaceDatabase(backupFile);

      final warnings = <String>[];
      final pictureCount = await _restorePictures(pictures, warnings);
      final counts = await repository.counts();

      if (prefBytes != null) {
        final xml = utf8.decode(prefBytes, allowMalformed: true);
        preferences.legacyPrefsXml = xml;
        await _applyImportedPreferences(xml);
      } else {
        preferences.homeCurrency = await repository.suggestedHomeCurrency();
        warnings.add('The backup did not contain preferences.');
      }

      if (dataStoreBytes != null) {
        await File(p.join(database.supportDir.path, 'legacy_$_dataStoreFile'))
            .writeAsBytes(dataStoreBytes);
      }

      preferences.onboardingDone = true;

      return BackupImportResult(
        schemaVersion: version,
        accounts: counts['accounts'] ?? 0,
        transactions: counts['transactions'] ?? 0,
        categories: counts['categories'] ?? 0,
        pictures: pictureCount,
        warnings: warnings,
      );
    } finally {
      try {
        await workingDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<int> _restorePictures(
    Map<String, Uint8List> pictures,
    List<String> warnings,
  ) async {
    if (pictures.isEmpty) return 0;
    await database.picturesDir.create(recursive: true);
    await for (final entity in database.picturesDir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    final attachments = await repository.allAttachments();
    var restored = 0;
    for (final row in attachments) {
      final id = asIntOr(row['_id'], 0);
      final oldUri = asStringOr(row['uri']);
      String? fileName;
      for (final name in pictures.keys) {
        if (name.startsWith('${id}_')) {
          fileName = name;
          break;
        }
      }
      fileName ??= p.basename(Uri.tryParse(oldUri)?.path ?? oldUri);
      final data = pictures[fileName];
      if (data == null) {
        warnings.add('Picture for transaction attachment $id was not found.');
        continue;
      }
      var localName = fileName;
      if (localName.startsWith('${id}_')) {
        localName = localName.substring('${id}_'.length);
      }
      localName = p.basename(localName);
      var target = File(p.join(database.picturesDir.path, localName));
      var counter = 1;
      while (await target.exists()) {
        final extension = p.extension(localName);
        final base = p.basenameWithoutExtension(localName);
        target = File(p.join(database.picturesDir.path, '${base}_${counter++}$extension'));
      }
      await target.writeAsBytes(data);
      await repository.updateAttachmentUri(id, target.path);
      restored++;
    }
    return restored;
  }

  Future<void> _applyImportedPreferences(String xml) async {
    try {
      final doc = XmlDocument.parse(xml);
      final values = <String, String>{};
      for (final element in doc.rootElement.childElements) {
        final name = element.getAttribute('name');
        if (name != null) values[name] = element.innerText;
      }
      final home = values['home_currency'];
      if (home != null && home.isNotEmpty) {
        preferences.homeCurrency = home;
      } else {
        preferences.homeCurrency = await repository.suggestedHomeCurrency();
      }
      final theme = values['pref_ui_theme'];
      if (theme == 'dark') preferences.themeMode = ThemeMode.dark;
      if (theme == 'light') preferences.themeMode = ThemeMode.light;
    } catch (_) {
      preferences.homeCurrency = await repository.suggestedHomeCurrency();
    }
  }

  Future<File> export({
    String? password,
    bool includePictures = true,
  }) async {
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(now);
    final encrypted = password != null && password.isNotEmpty;
    final name = 'myexpenses-backup-$stamp.${encrypted ? 'enc' : 'zip'}';
    final backupDir = Directory(p.join(database.supportDir.path, 'backups'));
    await backupDir.create(recursive: true);
    final target = File(p.join(backupDir.path, name));
    final workingDir = Directory(p.join(
      database.supportDir.path,
      'export-${now.microsecondsSinceEpoch}',
    ));
    await workingDir.create(recursive: true);
    try {
      final dbCopy = await database.createConsistentCopy(workingDir);
      final archive = Archive();
      final dbBytes = await dbCopy.readAsBytes();
      archive.addFile(ArchiveFile(_backupDb, dbBytes.length, dbBytes));
      final prefBytes = utf8.encode(_buildPrefsXml());
      archive.addFile(ArchiveFile(_backupPref, prefBytes.length, prefBytes));
      final dataStore = File(
        p.join(database.supportDir.path, 'legacy_$_dataStoreFile'),
      );
      if (await dataStore.exists()) {
        final bytes = await dataStore.readAsBytes();
        archive.addFile(ArchiveFile(_dataStoreFile, bytes.length, bytes));
      }
      if (includePictures) {
        final attachments = await repository.allAttachments();
        for (final row in attachments) {
          final id = asIntOr(row['_id'], 0);
          final uri = asStringOr(row['uri']);
          var source = File(uri);
          if (!await source.exists()) {
            final candidates = await database.picturesDir
                .list()
                .where((entity) => entity is File)
                .cast<File>()
                .toList();
            File? match;
            for (final candidate in candidates) {
              if (p.basename(candidate.path).startsWith('${id}_')) {
                match = candidate;
                break;
              }
            }
            if (match != null) source = match;
          }
          if (!await source.exists()) continue;
          final fileName = '${id}_${p.basename(source.path)}';
          final bytes = await source.readAsBytes();
          archive.addFile(
            ArchiveFile('Pictures/$fileName', bytes.length, bytes),
          );
        }
      }
      final encoded = ZipEncoder().encode(archive);
      var output = Uint8List.fromList(encoded);
      if (encrypted) {
        output = await _encrypt(output, password);
      }
      await target.writeAsBytes(output, flush: true);
      await preferences.recordBackup(name);
      return target;
    } finally {
      try {
        await workingDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  String _buildPrefsXml() {
    XmlDocument doc;
    final raw = preferences.legacyPrefsXml;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        doc = XmlDocument.parse(raw);
      } catch (_) {
        doc = XmlDocument.parse('<?xml version="1.0" encoding="utf-8"?><map></map>');
      }
    } else {
      doc = XmlDocument.parse('<?xml version="1.0" encoding="utf-8"?><map></map>');
    }
    final root = doc.rootElement;
    void setString(String key, String value) {
      root.children
          .whereType<XmlElement>()
          .where((element) => element.getAttribute('name') == key)
          .toList()
          .forEach((element) => element.remove());
      root.children.add(
        XmlElement(
          XmlName.qualified('string'),
          [XmlAttribute(XmlName.qualified('name'), key)],
          [XmlText(value)],
        ),
      );
    }

    void setBool(String key, bool value) {
      root.children
          .whereType<XmlElement>()
          .where((element) => element.getAttribute('name') == key)
          .toList()
          .forEach((element) => element.remove());
      root.children.add(
        XmlElement(
          XmlName.qualified('boolean'),
          [
            XmlAttribute(XmlName.qualified('name'), key),
            XmlAttribute(XmlName.qualified('value'), value ? 'true' : 'false'),
          ],
        ),
      );
    }

    void setInt(String key, int value) {
      root.children
          .whereType<XmlElement>()
          .where((element) => element.getAttribute('name') == key)
          .toList()
          .forEach((element) => element.remove());
      root.children.add(
        XmlElement(
          XmlName.qualified('int'),
          [
            XmlAttribute(XmlName.qualified('name'), key),
            XmlAttribute(XmlName.qualified('value'), value.toString()),
          ],
        ),
      );
    }

    setString('home_currency', preferences.homeCurrency);
    setString('pref_ui_theme', preferences.themeMode.name == 'system'
        ? 'default'
        : preferences.themeMode.name);
    setString('backup_file_prefix', 'myexpenses-backup');
    setString('export_date_format', 'dd/MM/y');
    setBool('purge_backup', false);
    setBool('auto_backup', false);
    setBool('optimize_picture', true);
    setInt('export_decimal_separator', 46);
    setInt('export_delimiter', 44);
    final xml = doc.toXmlString();
    return xml.startsWith('<?xml')
        ? xml
        : '<?xml version="1.0" encoding="utf-8"?>\n$xml';
  }

  bool _isEncrypted(Uint8List bytes) {
    if (bytes.length < _magic.length) return false;
    return ascii.decode(bytes.sublist(0, _magic.length), allowInvalid: true) ==
        _magic;
  }

  Future<Uint8List> _encrypt(Uint8List plain, String password) async {
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(crypto.sha256.convert(utf8.encode(password)).bytes);
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
    );
    final builder = BytesBuilder(copy: false);
    builder.add(utf8.encode(_magic));
    builder.add(nonce);
    builder.add(box.cipherText);
    builder.add(box.mac.bytes);
    return builder.toBytes();
  }

  Future<Uint8List> _decrypt(Uint8List encrypted, String password) async {
    final nonceLength = 12;
    final start = _magic.length;
    if (encrypted.length < start + nonceLength + 16) {
      throw BackupException('The encrypted backup is truncated.');
    }
    final nonce = encrypted.sublist(start, start + nonceLength);
    final tagStart = encrypted.length - 16;
    final cipherText = encrypted.sublist(start + nonceLength, tagStart);
    final mac = encrypted.sublist(tagStart);
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(crypto.sha256.convert(utf8.encode(password)).bytes);
    try {
      final clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      throw BackupException(
        'The password is not correct or the backup is damaged.',
      );
    }
  }
}
