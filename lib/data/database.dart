import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const int myExpensesSchemaVersion = 183;

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Directory? _supportDir;
  Directory? _picturesDir;
  bool _initialized = false;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Database has not been initialised');
    }
    return database;
  }

  Directory get supportDir {
    final directory = _supportDir;
    if (directory == null) throw StateError('Database has not been initialised');
    return directory;
  }

  Directory get picturesDir {
    final directory = _picturesDir;
    if (directory == null) throw StateError('Database has not been initialised');
    return directory;
  }

  File get databaseFile => File(p.join(supportDir.path, 'myexpenses.sqlite'));

  Future<void> init() async {
    if (_initialized) return;
    _supportDir = await getApplicationSupportDirectory();
    _picturesDir = Directory(p.join(_supportDir!.path, 'Pictures'));
    await _picturesDir!.create(recursive: true);
    await _open();
    _initialized = true;
  }

  Future<void> _open() async {
    final path = databaseFile.path;
    var exists = await databaseFile.exists();
    if (exists) {
      // A previous interrupted first start may have left a partially created
      // database behind (for example because of a crash during onCreate).
      // It has user_version 0; discard it and start over.
      try {
        final probe = await openDatabase(
          path,
          readOnly: true,
          singleInstance: false,
        );
        final rows = await probe.rawQuery('PRAGMA user_version');
        final version = rows.isEmpty ? 0 : (rows.first.values.first as int? ?? 0);
        await probe.close();
        if (version == 0) {
          await _deleteDatabaseFiles();
          exists = false;
        }
      } catch (_) {
        await _deleteDatabaseFiles();
        exists = false;
      }
    }
    Future<void> configure(Database database) async {
      await database.execute('PRAGMA foreign_keys = ON');
      await database.execute('PRAGMA recursive_triggers = ON');
    }

    try {
      if (exists) {
        _db = await openDatabase(
          path,
          onConfigure: configure,
          onOpen: configure,
        );
      } else {
        _db = await openDatabase(
          path,
          version: myExpensesSchemaVersion,
          onConfigure: configure,
          onCreate: (database, version) async {
            await _createSchema(database);
          },
          onOpen: configure,
        );
      }
    } catch (error) {
      await _deleteDatabaseFiles();
      rethrow;
    }
    if (!exists) {
      await _seedDefaults(_db!);
      await _db!.execute('PRAGMA user_version = $myExpensesSchemaVersion');
    }
  }

  Future<void> _deleteDatabaseFiles() async {
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${databaseFile.path}$suffix');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _createSchema(Database database) async {
    final schemaJson =
        await rootBundle.loadString('assets/db/schema.json');
    final statements = (jsonDecode(schemaJson) as List).cast<String>();
    for (final statement in statements) {
      if (statement.contains('android_metadata')) {
        // sqflite creates this table itself.
        continue;
      }
      try {
        await database.execute(statement);
      } catch (error) {
        // Indexes on tables that do not exist in an old/newer schema can be
        // skipped, all core tables are created without them.
        if (!statement.toUpperCase().startsWith('CREATE INDEX')) {
          rethrow;
        }
      }
    }
    final seedJson = await rootBundle.loadString('assets/db/seed.json');
    final seed = (jsonDecode(seedJson) as List).cast<String>();
    for (final statement in seed) {
      await database.execute(statement);
    }
    final defaultsJson =
        await rootBundle.loadString('assets/db/default_categories.json');
    final defaults = (jsonDecode(defaultsJson) as List).cast<String>();
    for (final statement in defaults) {
      await database.execute(statement);
    }
  }

  Future<void> _seedDefaults(Database database) async {
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT count(*) FROM accounts'),
    );
    // A freshly created database has no accounts. Nothing else is required.
    assert((count ?? 0) == 0);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> reopen() async {
    await close();
    await _open();
  }

  Future<void> replaceDatabase(File replacement) async {
    await close();
    final target = databaseFile;
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${target.path}$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
    await replacement.copy(target.path);
    await _open();
  }

  Future<File> createConsistentCopy(Directory targetDirectory) async {
    final target = File(p.join(
      targetDirectory.path,
      'BACKUP-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    ));
    final escaped = target.path.replaceAll("'", "''");
    try {
      await db.execute("VACUUM INTO '$escaped'");
    } catch (_) {
      // VACUUM INTO is only available on SQLite >= 3.27 (Android 10). On
      // Android 8 and 9 fall back to a checkpointed file copy.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await databaseFile.copy(target.path);
    }
    return target;
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      db.transaction(action);
}
