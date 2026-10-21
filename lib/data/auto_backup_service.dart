import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/prefs.dart';
import 'backup_service.dart';

enum AutoBackupPeriod { daily, weekly, monthly }

extension AutoBackupPeriodInfo on AutoBackupPeriod {
  String get label {
    switch (this) {
      case AutoBackupPeriod.daily:
        return 'Daily';
      case AutoBackupPeriod.weekly:
        return 'Weekly';
      case AutoBackupPeriod.monthly:
        return 'Monthly';
    }
  }

  Duration get duration {
    switch (this) {
      case AutoBackupPeriod.daily:
        return const Duration(days: 1);
      case AutoBackupPeriod.weekly:
        return const Duration(days: 7);
      case AutoBackupPeriod.monthly:
        return const Duration(days: 30);
    }
  }

  static AutoBackupPeriod parse(String? value) {
    switch (value) {
      case 'daily':
        return AutoBackupPeriod.daily;
      case 'monthly':
        return AutoBackupPeriod.monthly;
      default:
        return AutoBackupPeriod.weekly;
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
    final period = AutoBackupPeriodInfo.parse(preferences.autoBackupPeriod);
    final last = preferences.lastAutoBackupAt;
    if (last != null && DateTime.now().difference(last) < period.duration) {
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
    final file = await backupService.export();
    final target = File(p.join(directory.path, p.basename(file.path)));
    await file.copy(target.path);
    await preferences.recordAutoBackup(p.basename(target.path));
    try {
      await file.delete();
    } catch (_) {}
    return target;
  }
}
