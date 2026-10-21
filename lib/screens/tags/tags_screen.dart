import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';

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
                    trailing: IconButton(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () async {
                        final action = await showActionSheet<String>(
                          context,
                          title: tag.label,
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
                        if (!context.mounted) return;
                        if (action == 'edit') {
                          await _edit(context, ref, tag);
                        } else if (action == 'delete') {
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
                            await ref
                                .read(repositoryProvider)
                                .deleteTag(tag.id);
                            ref.invalidate(tagsProvider);
                            ref.invalidate(transactionsProvider);
                          }
                        }
                      },
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
