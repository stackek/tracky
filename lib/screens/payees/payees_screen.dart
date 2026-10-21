import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';

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
    final counts =
        ref.watch(payeeTransactionCountsProvider).value ?? const <int, int>{};
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
                          final count = counts[payee.id] ?? 0;
                          final subtitle = [
                            if (payee.description != null &&
                                payee.description!.isNotEmpty)
                              payee.description!,
                            count == 1
                                ? '1 transaction'
                                : '$count transactions',
                          ].join(' • ');
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                payee.name.isEmpty
                                    ? '?'
                                    : payee.name[0].toUpperCase(),
                              ),
                            ),
                            title: Text(payee.name),
                            subtitle: Text(subtitle),
                            onTap: () => _edit(payee),
                            trailing: IconButton(
                              tooltip: 'Delete payee',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(payee),
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
    final description = TextEditingController(text: payee?.description ?? '');
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
                controller: description,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
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
    final savedDescription = description.text.trim();
    disposeAfterDialog([name, description]);
    if (result != true || savedName.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    if (payee == null) {
      await repo.insertPayee(
        savedName,
        description: savedDescription.isEmpty ? null : savedDescription,
      );
    } else {
      await repo.updatePayee(
        payee.id,
        name: savedName,
        description: savedDescription.isEmpty ? null : savedDescription,
      );
    }
    ref.invalidate(payeesProvider);
    ref.invalidate(payeeTransactionCountsProvider);
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
    ref.invalidate(payeeTransactionCountsProvider);
    ref.invalidate(transactionsProvider);
  }
}
