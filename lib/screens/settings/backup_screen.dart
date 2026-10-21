import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/ui_utils.dart';
import '../../data/auto_backup_service.dart';
import '../../data/csv_service.dart';
import '../../providers.dart';
import '../../widgets/search_picker.dart';
import 'backup_helpers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key, this.importOnly = false});

  final bool importOnly;

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    final theme = Theme.of(context);
    final lastBackup = prefs.lastBackupAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(
            'Backup',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (lastBackup != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Last backup: ${formatDateTime(lastBackup)}'
                '${prefs.lastBackupName == null ? '' : ' • ${prefs.lastBackupName}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Create backup'),
            subtitle: const Text('Unencrypted .zip file'),
            onTap: () => _createBackup(encrypted: false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Create encrypted backup'),
            subtitle: const Text('Password protected, compatible with .enc'),
            onTap: () => _createBackup(encrypted: true),
          ),
          const Divider(height: 28),
          Text(
            'Automatic backup',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.schedule),
            title: const Text('Back up automatically'),
            subtitle: const Text(
              'Saves a backup to the selected folder in the background when '
              'the app starts.',
            ),
            value: prefs.autoBackupEnabled,
            onChanged: (value) async {
              if (value &&
                  (prefs.autoBackupFolder == null ||
                      prefs.autoBackupFolder!.isEmpty)) {
                await _pickAutoBackupFolder();
                if (!mounted) return;
                if (prefs.autoBackupFolder == null ||
                    prefs.autoBackupFolder!.isEmpty) {
                  return;
                }
              }
              prefs.autoBackupEnabled = value;
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Encrypt automatic backups'),
            subtitle: Text(
              prefs.autoBackupEncrypted
                  ? 'Password protected .enc files'
                  : 'Unencrypted .zip files',
            ),
            value: prefs.autoBackupEncrypted,
            onChanged: (value) async {
              if (value) {
                final password = await askBackupPassword(
                  context,
                  confirm: true,
                );
                if (password == null || password.isEmpty || !mounted) return;
                prefs.autoBackupPassword = password;
                prefs.autoBackupEncrypted = true;
              } else {
                prefs.autoBackupEncrypted = false;
              }
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Backup folder'),
            subtitle: Text(
              prefs.autoBackupFolder == null || prefs.autoBackupFolder!.isEmpty
                  ? 'Not selected'
                  : prefs.autoBackupFolder!,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickAutoBackupFolder,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat),
            title: const Text('Repeat every'),
            subtitle: Text(
              '${prefs.autoBackupInterval} '
              '${AutoBackupUnitInfo.parse(prefs.autoBackupUnit).labelFor(prefs.autoBackupInterval)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickAutoBackupPeriod,
          ),
          if (prefs.lastAutoBackupAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Last automatic backup: '
                '${formatDateTime(prefs.lastAutoBackupAt!)}'
                '${prefs.lastAutoBackupName == null ? '' : ' • ${prefs.lastAutoBackupName}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Run automatic backup now'),
            onTap: _runAutoBackupNow,
          ),
          const Divider(height: 28),
          Text(
            'Restore',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restore),
            title: const Text('Restore from a backup'),
            subtitle: const Text('Replaces the data currently on this device'),
            onTap: _restore,
          ),
          const Divider(height: 28),
          Text(
            'Spreadsheet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Export CSV'),
            subtitle: const Text('Transactions as a spreadsheet'),
            onTap: _exportCsv,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import CSV'),
            subtitle: const Text('Date and Amount columns are required'),
            onTap: _importCsv,
          ),
          const SizedBox(height: 24),
          Text(
            'Backups contain your complete financial history. Keep them in a '
            'safe place. Encrypted backups use AES-256-GCM with a key derived '
            'from your password.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAutoBackupFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose backup folder',
      initialDirectory: ref.read(preferencesProvider).autoBackupFolder,
    );
    if (path == null || !mounted) return;
    ref.read(preferencesProvider).autoBackupFolder = path;
    setState(() {});
  }

  Future<void> _pickAutoBackupPeriod() async {
    final prefs = ref.read(preferencesProvider);
    final controller = TextEditingController(
      text: prefs.autoBackupInterval.toString(),
    );
    var unit = AutoBackupUnitInfo.parse(prefs.autoBackupUnit);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Automatic backup period'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Repeat every',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Unit'),
                subtitle: Text(unit.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selected = await showSearchPicker<AutoBackupUnit>(
                    context: context,
                    title: 'Backup period unit',
                    selected: unit,
                    entries: [
                      for (final value in AutoBackupUnit.values)
                        PickerEntry(
                          value: value,
                          label: value.label,
                          icon: Icons.schedule,
                        ),
                    ],
                  );
                  if (selected != null) {
                    setDialogState(() => unit = selected);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final interval = int.tryParse(controller.text.trim()) ?? 1;
    disposeAfterDialog([controller]);
    if (result != true || !mounted) return;
    prefs.autoBackupInterval = interval.clamp(1, 9999);
    prefs.autoBackupUnit = unit.name;
    setState(() {});
  }

  Future<void> _runAutoBackupNow() async {
    final result = await runWithProgress<File>(
      context,
      'Creating automatic backup…',
      () => ref.read(autoBackupServiceProvider).runNow(),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Backup saved to ${result.path}')));
  }

  Future<void> _createBackup({required bool encrypted}) async {
    String? password;
    if (encrypted) {
      password = await askBackupPassword(context, confirm: true);
      if (password == null || password.isEmpty || !mounted) return;
    }
    final service = ref.read(backupServiceProvider);
    final file = await runWithProgress<File>(
      context,
      encrypted ? 'Encrypting backup…' : 'Creating backup…',
      () => service.export(password: password),
    );
    if (file == null || !mounted) return;
    setState(() {});
    await _offerBackupFile(file);
  }

  Future<void> _offerBackupFile(File file) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to device'),
              subtitle: const Text('Choose where to store the backup'),
              onTap: () => Navigator.of(context).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              subtitle: const Text('Send to cloud storage or another app'),
              onTap: () => Navigator.of(context).pop('share'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      final bytes = await file.readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: file.uri.pathSegments.last,
        bytes: bytes,
        mimeType: file.path.endsWith('.enc')
            ? 'application/octet-stream'
            : 'application/zip',
        dialogTitle: 'Save backup',
      );
      if (uri != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup saved.')));
      }
    } else if (action == 'share') {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Tracky backup'),
      );
    }
  }

  Future<void> _restore() async {
    final result = await importBackupInteractive(context, ref);
    if (result == null || !mounted) return;
    ref.invalidate(settingsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(activeAccountsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(categoryTreeProvider);
    ref.invalidate(payeesProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(periodTotalsProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(templatesProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore complete'),
        content: Text(
          'Schema version ${result.schemaVersion}\n'
          '${result.accounts} accounts\n'
          '${result.transactions} transactions\n'
          '${result.categories} categories\n'
          '${result.pictures} pictures\n'
          '${result.warnings.isEmpty ? '' : '\nWarnings:\n${result.warnings.join('\n')}'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final service = CsvService(ref.read(repositoryProvider));
    final temp = Directory.systemTemp.createTempSync('tracky-csv');
    final file = File('${temp.path}/transactions.csv');
    final exported = await runWithProgress<File>(
      context,
      'Exporting CSV…',
      () => service.export(file),
    );
    if (exported == null || !mounted) return;
    final bytes = await exported.readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: 'transactions.csv',
      bytes: bytes,
      mimeType: 'text/csv',
      dialogTitle: 'Save CSV',
    );
    if (uri != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV exported.')));
    }
  }

  Future<void> _importCsv() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Select a CSV file',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    final accounts = await ref.read(repositoryProvider).activeAccounts();
    if (accounts.isEmpty || !mounted) return;
    final csv = CsvService(ref.read(repositoryProvider));
    final imported = await runWithProgress<CsvImportResult>(
      context,
      'Importing CSV…',
      () => csv.import(File(path), defaultAccountId: accounts.first.id),
    );
    if (imported == null || !mounted) return;
    ref.invalidate(transactionsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(statsProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CSV import complete'),
        content: Text(
          '${imported.imported} transactions imported.\n'
          '${imported.skipped} rows skipped.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
