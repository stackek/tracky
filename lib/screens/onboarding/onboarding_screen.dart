import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../settings/backup_helpers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await importBackupInteractive(context, ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      _afterRestore(result.accounts, result.transactions);
    }
  }

  Future<void> _startFresh() async {
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    final accounts = await repo.accounts();
    if (accounts.isEmpty) {
      await repo.insertAccount(
        label: 'Cash',
        currency: ref.read(settingsProvider).homeCurrency,
        type: 1,
      );
    }
    ref.read(preferencesProvider).onboardingDone = true;
    ref.invalidate(settingsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(activeAccountsProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    context.go('/transactions');
  }

  void _afterRestore(int accounts, int transactions) {
    ref.invalidate(settingsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(activeAccountsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(categoryTreeProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(periodTotalsProvider);
    ref.invalidate(topCategoryProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(payeesProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Welcome back'),
        content: Text(
          'Your backup was restored successfully.\n\n'
          '$accounts accounts and $transactions transactions are ready.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/transactions');
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.savings_outlined,
                  size: 42,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'My Expenses Open',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A free, open source expense tracker for Android. '
                'Private by design: your data never leaves your device.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              _Feature(
                icon: Icons.lock_outline,
                title: 'No account, no tracking',
                text: 'Everything is stored locally and can be exported.',
              ),
              _Feature(
                icon: Icons.swap_horiz,
                title: 'Bring your history',
                text: 'Restores backups created by My Expenses (.zip or .enc).',
              ),
              _Feature(
                icon: Icons.volunteer_activism_outlined,
                title: 'Free forever',
                text: 'No ads, no subscriptions, no locked features.',
              ),
              const Spacer(),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _restore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore a My Expenses backup'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _startFresh,
                    child: const Text('Start fresh'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'No payment. No registration. GPL-3.0 licensed.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
