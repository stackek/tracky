import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tags.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.sell_outlined,
                title: 'No tags',
                message: 'Tags let you group transactions across categories.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final tag = items[index];
                  return ListTile(
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(tag.label),
                    onTap: () => _edit(context, ref, tag),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _edit(context, ref, tag);
                        } else if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Delete ${tag.label}?'),
                              content: const Text(
                                'The tag will be removed from all transactions.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await ref.read(repositoryProvider).deleteTag(tag.id);
                            ref.invalidate(tagsProvider);
                            ref.invalidate(transactionsProvider);
                          }
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
            Center(child: Text('Could not load tags:\n$error')),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, [Tag? tag]) async {
    final controller = TextEditingController(text: tag?.label ?? '');
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tag == null ? 'New tag' : 'Edit tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final label = controller.text.trim();
    disposeAfterDialog([controller]);
    if (label.isEmpty) return;
    if (tag == null) {
      await ref.read(repositoryProvider).insertTag(label);
    } else {
      await ref.read(repositoryProvider).updateTag(tag.id, label: label);
    }
    ref.invalidate(tagsProvider);
  }
}

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: methods.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.payment_outlined,
                title: 'No payment methods',
                message: 'Add how you usually pay: cash, card, transfer…',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final method = items[index];
                  return ListTile(
                    leading: Icon(iconForPaymentMethod(method.icon)),
                    title: Text(method.displayName),
                    onTap: () => _edit(context, ref, method),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _edit(context, ref, method);
                        } else if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Delete ${method.displayName}?'),
                              content: const Text(
                                'Transactions using this method will keep their '
                                'data but lose the method link.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await ref
                                .read(repositoryProvider)
                                .deletePaymentMethod(method.id);
                            ref.invalidate(paymentMethodsProvider);
                            ref.invalidate(transactionsProvider);
                          }
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
            Center(child: Text('Could not load payment methods:\n$error')),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PaymentMethod? method,
  ]) async {
    final controller = TextEditingController(text: method?.label ?? '');
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(method == null ? 'New payment method' : 'Edit payment method'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final label = controller.text.trim();
    controller.dispose();
    if (label.isEmpty) return;
    if (method == null) {
      await ref.read(repositoryProvider).insertPaymentMethod(label);
    } else {
      await ref
          .read(repositoryProvider)
          .updatePaymentMethod(method.id, label: label, icon: method.icon);
    }
    ref.invalidate(paymentMethodsProvider);
  }
}
