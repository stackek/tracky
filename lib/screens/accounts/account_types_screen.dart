import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';

class AccountTypesScreen extends ConsumerWidget {
  const AccountTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(accountTypesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account types')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editType(context, ref),
        child: const Icon(Icons.add),
      ),
      body: types.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.account_balance_outlined,
                title: 'No account types',
                message: 'Add an account type to use when creating accounts.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final type = items[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Icon(
                        type.isAsset
                            ? Icons.trending_up
                            : Icons.trending_down,
                      ),
                    ),
                    title: Text(type.displayName),
                    subtitle: Text(
                      [
                        type.isAsset ? 'Asset' : 'Liability',
                        if (type.supportsReconciliation) 'Reconciliation',
                      ].join(' • '),
                    ),
                    onTap: () => _editType(context, ref, type),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _editType(context, ref, type);
                        } else if (value == 'delete') {
                          await _deleteType(context, ref, type);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load account types:\n$error')),
      ),
    );
  }

  Future<void> _editType(
    BuildContext context,
    WidgetRef ref, [
    AccountType? type,
  ]) async {
    final name = TextEditingController(
      text: type?.displayName ?? '',
    );
    final sortKey = TextEditingController(
      text: (type?.sortKey ?? 0).toString(),
    );
    var isAsset = type?.isAsset ?? true;
    var supportsReconciliation = type?.supportsReconciliation ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(type == null ? 'New account type' : 'Edit account type'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sortKey,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    helperText: 'Lower numbers appear first',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Asset account'),
                  subtitle: const Text(
                    'Assets add to your net worth, liabilities subtract',
                  ),
                  value: isAsset,
                  onChanged: (value) => setState(() => isAsset = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Supports reconciliation'),
                  value: supportsReconciliation,
                  onChanged: (value) =>
                      setState(() => supportsReconciliation = value),
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
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final label = name.text.trim();
    final order = int.tryParse(sortKey.text) ?? 0;
    disposeAfterDialog([name, sortKey]);
    if (result != true || label.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    try {
      if (type == null) {
        await repo.insertAccountType(
          label: label,
          isAsset: isAsset,
          supportsReconciliation: supportsReconciliation,
          sortKey: order,
        );
      } else {
        await repo.updateAccountType(
          type.id,
          label: label,
          isAsset: isAsset,
          supportsReconciliation: supportsReconciliation,
          sortKey: order,
        );
      }
      ref.invalidate(accountTypesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $error')),
        );
      }
    }
  }

  Future<void> _deleteType(
    BuildContext context,
    WidgetRef ref,
    AccountType type,
  ) async {
    final usage = await ref.read(repositoryProvider).accountTypeUsage(type.id);
    if (!context.mounted) return;
    if (usage > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Account type is in use'),
          content: Text(
            '${type.displayName} is used by $usage account(s). '
            'Change those accounts to another type before deleting it.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${type.displayName}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteAccountType(type.id);
      ref.invalidate(accountTypesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $error')),
        );
      }
    }
  }
}
