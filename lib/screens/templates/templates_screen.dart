import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/template/edit'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/template/edit'),
        child: const Icon(Icons.add),
      ),
      body: templates.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.repeat_outlined,
                title: 'No templates',
                message:
                    'Templates are reusable transactions, perfect for regular '
                    'expenses like rent or subscriptions.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final template = items[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorFromDb(template.categoryColor)
                          .withValues(alpha: 0.18),
                      child: Icon(
                        iconForCategory(template.categoryIcon),
                        color: colorFromDb(template.categoryColor),
                      ),
                    ),
                    title: Text(template.title),
                    subtitle: Text(
                      [
                        if (template.categoryPath != null)
                          template.categoryPath!,
                        if (template.accountLabel != null)
                          template.accountLabel!,
                        if (template.payeeName != null) template.payeeName!,
                      ].join(' • '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMoney(template.amount, template.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          tooltip: 'Delete template',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Delete ${template.title}?'),
                                content: const Text(
                                  'The template will be deleted. Transactions '
                                  'already created from it are kept.',
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
                                  .deleteTemplate(template.id);
                              ref.invalidate(templatesProvider);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      context.push('/template/edit?id=${template.id}');
                    },
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load templates:\n$error')),
      ),
    );
  }
}
