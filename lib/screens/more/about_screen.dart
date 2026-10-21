import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repository = ref.watch(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.account_balance_wallet,
                size: 36,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'My Expenses Open',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version 1.0.0',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'A free, open source and privacy-first expense tracker. It contains '
            'no advertising, analytics or payment features. Your data stays on '
            'your device unless you explicitly export it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FutureBuilder(
            future: repository.counts(),
            builder: (context, snapshot) {
              final counts = snapshot.data;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Your data'),
                subtitle: Text(
                  counts == null
                      ? 'Loading…'
                      : '${counts['transactions']} transactions • '
                            '${counts['accounts']} accounts • '
                            '${counts['categories']} categories',
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open source licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'My Expenses Open',
              applicationVersion: '1.0.0',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: const Text('Licence'),
            subtitle: const Text('GNU General Public License v3.0'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Made with Flutter',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
