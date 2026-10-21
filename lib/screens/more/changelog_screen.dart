import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/links.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Changelog')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            "What's new",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _ChangelogContent(entry: latestChangelog),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openReleasesPage(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('More'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogContent extends StatelessWidget {
  const _ChangelogContent({required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('Version ${entry.version}'),
            ),
            Text(
              entry.date,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final change in entry.changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(change)),
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> showChangelogDialog(
  BuildContext context, {
  ChangelogEntry? entry,
}) async {
  final data = entry ?? latestChangelog;
  final pageContext = context;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("What's new in Tracky ${data.version}"),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: _ChangelogContent(entry: data),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            openReleasesPage(pageContext);
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('More'),
        ),
      ],
    ),
  );
}
