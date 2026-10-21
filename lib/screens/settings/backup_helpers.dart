import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../data/backup_service.dart';
import '../../providers.dart';

Future<File?> pickBackupFile() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Select a backup',
    type: FileType.custom,
    allowedExtensions: ['zip', 'enc'],
  );
  final path = files.isEmpty ? null : files.first.path;
  return path == null ? null : File(path);
}

Future<String?> askBackupPassword(
  BuildContext context, {
  bool confirm = false,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(confirm ? 'Protect backup' : 'Encrypted backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            confirm
                ? 'Choose a password. You will need it to restore this backup.'
                : 'This backup is encrypted. Enter the password used to create it.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(confirm ? 'Encrypt' : 'Unlock'),
        ),
      ],
    ),
  );
  disposeAfterDialog([controller]);
  return result;
}

Future<BackupImportResult?> importBackupInteractive(
  BuildContext context,
  WidgetRef ref,
) async {
  final file = await pickBackupFile();
  if (file == null) return null;
  String? password;
  final service = ref.read(backupServiceProvider);
  final bytes = await file.openRead(0, 9).expand((chunk) => chunk).toList();
  final encrypted = bytes.length >= 9 &&
      String.fromCharCodes(bytes) == 'ME_ENC_01';
  if (encrypted) {
    if (!context.mounted) return null;
    password = await askBackupPassword(context);
    if (password == null || password.isEmpty) return null;
  }
  if (!context.mounted) return null;
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Restoring backup…')),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await service.importFromFile(file, password: password);
    if (navigator.canPop()) navigator.pop();
    return result;
  } catch (error) {
    if (navigator.canPop()) navigator.pop();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore failed'),
          content: Text(error is BackupException ? error.message : '$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return null;
  }
}

Future<T?> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await action();
    if (navigator.canPop()) navigator.pop();
    return result;
  } catch (error) {
    if (navigator.canPop()) navigator.pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is BackupException ? error.message : '$error')),
      );
    }
    return null;
  }
}
