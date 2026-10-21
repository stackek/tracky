import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/prefs.dart';
import '../core/storage_access.dart';
import 'backup_service.dart';

enum AutoBackupUnit { hours, days, weeks, months }

extension AutoBackupUnitInfo on AutoBackupUnit {
  String get label {
    switch (this) {
      case AutoBackupUnit.hours:
        return 'hours';
      case AutoBackupUnit.days:
        return 'days';
      case AutoBackupUnit.weeks:
        return 'weeks';
      case AutoBackupUnit.months:
        return 'months';
    }
  }

  String labelFor(int interval) =>
      interval == 1 ? label.substring(0, label.length - 1) : label;

  Duration duration(int interval) {
    switch (this) {
      case AutoBackupUnit.hours:
        return Duration(hours: interval);
      case AutoBackupUnit.days:
        return Duration(days: interval);
      case AutoBackupUnit.weeks:
        return Duration(days: 7 * interval);
      case AutoBackupUnit.months:
        return Duration(days: 30 * interval);
    }
  }

  static AutoBackupUnit parse(String? value) {
    switch (value) {
      case 'hours':
        return AutoBackupUnit.hours;
      case 'days':
        return AutoBackupUnit.days;
      case 'months':
        return AutoBackupUnit.months;
      default:
        return AutoBackupUnit.weeks;
    }
  }
}

class AutoBackupService {
  AutoBackupService({required this.preferences, required this.backupService});

  final AppPreferences preferences;
  final BackupService backupService;

  String? get _folderUri => preferences.autoBackupFolderUri;

  bool get hasFolder {
    if (StorageAccess.isSupported) {
      final uri = _folderUri;
      return uri != null && uri.isNotEmpty;
    }
    final folder = preferences.autoBackupFolder;
    return folder != null && folder.isNotEmpty;
  }

  Future<String?> runIfDue() async {
    if (!preferences.autoBackupEnabled) return null;
    if (!hasFolder) return null;
    final unit = AutoBackupUnitInfo.parse(preferences.autoBackupUnit);
    final interval = preferences.autoBackupInterval.clamp(1, 9999);
    final last = preferences.lastAutoBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < unit.duration(interval)) {
      return null;
    }
    return runNow();
  }

  Future<String> runNow() async {
    final folder = preferences.autoBackupFolder;
    final folderUri = _folderUri;
    final useStorageAccess = StorageAccess.isSupported;
    if (useStorageAccess) {
      if (folderUri == null || folderUri.isEmpty) {
        throw BackupException(
          'Choose a backup folder first. Android requires you to pick the '
          'folder again after this update.',
        );
      }
    } else if (folder == null || folder.isEmpty) {
      throw BackupException('Choose a backup folder first.');
    }
    String? password;
    if (preferences.autoBackupEncrypted) {
      password = preferences.autoBackupPassword;
      if (password == null || password.isEmpty) {
        throw BackupException(
          'Set a password for encrypted automatic backups.',
        );
      }
    }
    final file = await backupService.export(password: password);
    final name = p.basename(file.path);
    try {
      if (useStorageAccess) {
        try {
          await StorageAccess.writeFile(
            uri: folderUri!,
            fileName: name,
            mimeType: name.endsWith('.enc')
                ? 'application/octet-stream'
                : 'application/zip',
            bytes: await file.readAsBytes(),
          );
        } on PlatformException catch (error) {
          throw BackupException(
            error.message ??
                'Could not write the backup to the selected folder.',
          );
        }
      } else {
        final directory = Directory(folder!);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final target = File(p.join(directory.path, name));
        await file.copy(target.path);
      }
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
    await preferences.recordAutoBackup(name);
    return name;
  }
}
