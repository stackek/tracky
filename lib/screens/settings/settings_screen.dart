import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/prefs.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/currency_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final currencies =
        ref.watch(currenciesProvider).value ?? const <CurrencyInfo>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _Header('Appearance'),
          ListTile(
            leading: const Icon(Icons.contrast),
            title: const Text('Theme'),
            subtitle: Text(switch (settings.themeMode) {
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
              ThemeMode.system => 'Follow system',
            }),
            onTap: () => _pickTheme(context, ref, settings.themeMode),
          ),
          const Divider(),
          _Header('Money'),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Home currency'),
            subtitle: Text(settings.homeCurrency),
            onTap: () async {
              var available = currencies;
              if (available.isEmpty) {
                available =
                    await ref.read(repositoryProvider).currencies();
              }
              if (!context.mounted) return;
              final selected = await showCurrencyPicker(
                context,
                available,
                selected: settings.homeCurrency,
              );
              if (selected != null) {
                await ref
                    .read(settingsProvider.notifier)
                    .setHomeCurrency(selected);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Currency formatting'),
            subtitle: Text(
              '${fractionDigitsFor(settings.homeCurrency)} decimal places, '
              'decimal "${settings.decimalSeparator}", '
              'grouping "${settings.groupSeparator}"\n'
              'Example: ${formatMoney(123456, settings.homeCurrency)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCurrencyFormat(context, ref, settings),
          ),
          const Divider(),
          _Header('Data'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup and restore'),
            subtitle: const Text('Create or restore a My Expenses backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/backup'),
          ),
          const Divider(),
          _Header('About'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open source licences'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'My Expenses Open',
              applicationVersion: '1.0.0',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'My Expenses Open is free software, licensed under the GNU '
              'General Public License v3. It contains no advertising, analytics '
              'or payment features. Your data stays on your device unless you '
              'explicitly export it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrencyFormat(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    var decimals = settings.currencyDecimals;
    var decimalSeparator = settings.decimalSeparator;
    var groupSeparator = settings.groupSeparator;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final defaultDigits =
              currencyFractionDigits[settings.homeCurrency] ?? 2;
          final digits = decimals ?? defaultDigits;
          final sample =
              '1${groupSeparator}234$decimalSeparator${'5' * digits}';
          final valid = decimalSeparator != groupSeparator;
          return AlertDialog(
            title: const Text('Currency formatting'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int?>(
                    initialValue: decimals,
                    decoration: const InputDecoration(
                      labelText: 'Decimal places',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Automatic (per currency)'),
                      ),
                      DropdownMenuItem(value: 0, child: Text('0')),
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                      DropdownMenuItem(value: 4, child: Text('4')),
                    ],
                    onChanged: (value) =>
                        setState(() => decimals = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: decimalSeparator,
                    decoration:
                        const InputDecoration(labelText: 'Decimal separator'),
                    items: const [
                      DropdownMenuItem(value: '.', child: Text('Dot (.)')),
                      DropdownMenuItem(value: ',', child: Text('Comma (,)')),
                    ],
                    onChanged: (value) => setState(
                      () => decimalSeparator = value ?? decimalSeparator,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: groupSeparator,
                    decoration:
                        const InputDecoration(labelText: 'Thousands separator'),
                    items: const [
                      DropdownMenuItem(value: ',', child: Text('Comma (,)')),
                      DropdownMenuItem(value: '.', child: Text('Dot (.)')),
                      DropdownMenuItem(value: ' ', child: Text('Space')),
                      DropdownMenuItem(value: '', child: Text('None')),
                    ],
                    onChanged: (value) =>
                        setState(() => groupSeparator = value ?? ''),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    valid ? 'Example: $sample' : 'Separators must be different',
                    style: TextStyle(
                      color: valid
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result == true) {
      await ref.read(settingsProvider.notifier).setCurrencyFormat(
            decimals: decimals,
            decimalSeparator: decimalSeparator,
            groupSeparator: groupSeparator,
          );
    }
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final result = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(switch (mode) {
                  ThemeMode.light => Icons.light_mode,
                  ThemeMode.dark => Icons.dark_mode,
                  ThemeMode.system => Icons.brightness_auto,
                }),
                title: Text(switch (mode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'Follow system',
                }),
                trailing: current == mode ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref.read(settingsProvider.notifier).setThemeMode(result);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
