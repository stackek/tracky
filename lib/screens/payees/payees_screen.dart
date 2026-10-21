import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';

class PayeesScreen extends ConsumerStatefulWidget {
  const PayeesScreen({super.key});

  @override
  ConsumerState<PayeesScreen> createState() => _PayeesScreenState();
}

class _PayeesScreenState extends ConsumerState<PayeesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final payees = ref.watch(payeesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payees')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: payees.when(
        data: (items) {
          final filtered = items
              .where(
                (payee) =>
                    payee.name.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search payees',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.person_outline,
                        title: _query.isEmpty ? 'No payees' : 'No matches',
                        message: _query.isEmpty
                            ? 'Add people and shops you transact with.'
                            : 'Try a different search term.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final payee = filtered[index];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                payee.name.isEmpty
                                    ? '?'
                                    : payee.name[0].toUpperCase(),
                              ),
                            ),
                            title: Text(payee.name),
                            subtitle: payee.iban == null || payee.iban!.isEmpty
                                ? null
                                : Text(payee.iban!),
                            onTap: () => _edit(payee),
                            trailing: IconButton(
                              tooltip: 'More',
                              icon: const Icon(Icons.more_vert),
                              onPressed: () async {
                                final action = await showActionSheet<String>(
                                  context,
                                  title: payee.name,
                                  actions: const [
                                    SheetAction(
                                      value: 'edit',
                                      label: 'Edit',
                                      icon: Icons.edit_outlined,
                                    ),
                                    SheetAction(
                                      value: 'delete',
                                      label: 'Delete',
                                      icon: Icons.delete_outline,
                                      destructive: true,
                                    ),
                                  ],
                                );
                                if (action == 'edit') {
                                  await _edit(payee);
                                } else if (action == 'delete') {
                                  await _delete(payee);
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load payees:\n$error')),
      ),
    );
  }

  Future<void> _edit([Payee? payee]) async {
    final name = TextEditingController(text: payee?.name ?? '');
    final shortName = TextEditingController(text: payee?.shortName ?? '');
    final iban = TextEditingController(text: payee?.iban ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(payee == null ? 'New payee' : 'Edit payee'),
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
                controller: shortName,
                decoration: const InputDecoration(labelText: 'Short name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: iban,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'IBAN'),
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
    );
    final savedName = name.text.trim();
    final savedShort = shortName.text.trim();
    final savedIban = iban.text.trim();
    disposeAfterDialog([name, shortName, iban]);
    if (result != true || savedName.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    if (payee == null) {
      await repo.insertPayee(
        savedName,
        shortName: savedShort.isEmpty ? null : savedShort,
        iban: savedIban.isEmpty ? null : savedIban,
      );
    } else {
      await repo.updatePayee(
        payee.id,
        name: savedName,
        shortName: savedShort.isEmpty ? null : savedShort,
        iban: savedIban.isEmpty ? null : savedIban,
      );
    }
    ref.invalidate(payeesProvider);
  }

  Future<void> _delete(Payee payee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${payee.name}?'),
        content: const Text(
          'Transactions that reference this payee will keep their data but '
          'lose the payee link.',
        ),
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
    await ref.read(repositoryProvider).deletePayee(payee.id);
    ref.invalidate(payeesProvider);
    ref.invalidate(transactionsProvider);
  }
}
