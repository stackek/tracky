import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/prefs.dart';
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

  Future<File?> runIfDue() async {
    if (!preferences.autoBackupEnabled) return null;
    final folder = preferences.autoBackupFolder;
    if (folder == null || folder.isEmpty) return null;
    final unit = AutoBackupUnitInfo.parse(preferences.autoBackupUnit);
    final interval = preferences.autoBackupInterval.clamp(1, 9999);
    final last = preferences.lastAutoBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < unit.duration(interval)) {
      return null;
    }
    return runNow();
  }

  Future<File> runNow() async {
    final folder = preferences.autoBackupFolder;
    if (folder == null || folder.isEmpty) {
      throw BackupException('Choose a backup folder first.');
    }
    final directory = Directory(folder);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    String? password;
    if (preferences.autoBackupEncrypted) {
      password = preferences.autoBackupPassword;
      if (password == null || password.isEmpty) {
        throw BackupException('Set a password for encrypted automatic backups.');
      }
    }
    final file = await backupService.export(password: password);
    final target = File(p.join(directory.path, p.basename(file.path)));
    await file.copy(target.path);
    await preferences.recordAutoBackup(p.basename(target.path));
    try {
      await file.delete();
    } catch (_) {}
    return target;
  }
}
