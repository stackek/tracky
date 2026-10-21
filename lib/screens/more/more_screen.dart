import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _Group(
            title: 'Organise',
            children: [
              _Tile(
                icon: Icons.category_outlined,
                title: 'Categories',
                subtitle: 'Expense and income categories',
                onTap: () => context.push('/categories'),
              ),
              _Tile(
                icon: Icons.person_outline,
                title: 'Payees',
                subtitle: 'People and shops you transact with',
                onTap: () => context.push('/payees'),
              ),
              _Tile(
                icon: Icons.account_balance_outlined,
                title: 'Account types',
                subtitle: 'Cash, bank, credit card and custom types',
                onTap: () => context.push('/account-types'),
              ),
              _Tile(
                icon: Icons.sell_outlined,
                title: 'Tags',
                onTap: () => context.push('/tags'),
              ),
              _Tile(
                icon: Icons.handshake_outlined,
                title: 'Debts',
                subtitle: 'What payees owe you or you owe them',
                onTap: () => context.push('/debts'),
              ),
            ],
          ),
          _Group(
            title: 'Plan',
            children: [
              _Tile(
                icon: Icons.savings_outlined,
                title: 'Budgets',
                subtitle: 'Set monthly limits per category',
                onTap: () => context.push('/budgets'),
              ),
              _Tile(
                icon: Icons.repeat_outlined,
                title: 'Templates',
                subtitle: 'Reuse frequent transactions',
                onTap: () => context.push('/templates'),
              ),
            ],
          ),
          _Group(
            title: 'Data',
            children: [
              _Tile(
                icon: Icons.backup_outlined,
                title: 'Backup and restore',
                subtitle: 'Compatible with My Expenses backups',
                onTap: () => context.push('/backup'),
              ),
              _Tile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
          _Group(
            title: 'About',
            children: [
              FutureBuilder(
                future: counts.counts(),
                builder: (context, snapshot) {
                  final counts = snapshot.data;
                  return _Tile(
                    icon: Icons.storage_outlined,
                    title: 'Your data',
                    subtitle: counts == null
                        ? 'Loading…'
                        : '${counts['transactions']} transactions • '
                            '${counts['accounts']} accounts • '
                            '${counts['categories']} categories',
                  );
                },
              ),
              _Tile(
                icon: Icons.code,
                title: 'Licence',
                subtitle: 'GNU General Public License v3.0',
                onTap: () => launchUrl(
                  Uri.parse('https://www.gnu.org/licenses/gpl-3.0.html'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _Tile(
                icon: Icons.favorite_outline,
                title: 'Free forever',
                subtitle: 'No ads, subscriptions or payments',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'My Expenses Open 1.0.0\nMade with Flutter',
              textAlign: TextAlign.center,
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

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
