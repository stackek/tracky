import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_info.dart';
import 'core/theme.dart';
import 'providers.dart';
import 'screens/accounts/account_editor_screen.dart';
import 'screens/accounts/account_types_screen.dart';
import 'screens/accounts/accounts_screen.dart';
import 'screens/budgets/budget_detail_screen.dart';
import 'screens/budgets/budgets_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/categories/category_editor_screen.dart';
import 'screens/debts/debts_screen.dart';
import 'screens/home_shell.dart';
import 'screens/more/about_screen.dart';
import 'screens/more/changelog_screen.dart';
import 'screens/more/more_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/payees/payees_screen.dart';
import 'screens/settings/backup_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/tags/tags_screen.dart';
import 'screens/templates/template_editor_screen.dart';
import 'screens/templates/templates_screen.dart';
import 'screens/transactions/transaction_editor_screen.dart';
import 'screens/transactions/transactions_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(preferencesProvider);
  return GoRouter(
    initialLocation: prefs.onboardingDone ? '/transactions' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (context, state) => const TransactionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/budgets',
                builder: (context, state) => const BudgetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/changelog',
        builder: (context, state) => const ChangelogScreen(),
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) => TransactionEditorScreen(
          transactionId: int.tryParse(state.uri.queryParameters['tx'] ?? ''),
          initialType: state.uri.queryParameters['type'],
          initialAccountId: int.tryParse(
            state.uri.queryParameters['account'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/account-types',
        builder: (context, state) => const AccountTypesScreen(),
      ),
      GoRoute(
        path: '/account/edit',
        builder: (context, state) => AccountEditorScreen(
          accountId: int.tryParse(state.uri.queryParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/category/edit',
        builder: (context, state) => CategoryEditorScreen(
          categoryId: int.tryParse(state.uri.queryParameters['id'] ?? ''),
          initialType:
              int.tryParse(state.uri.queryParameters['type'] ?? '') ?? 1,
        ),
      ),
      GoRoute(
        path: '/payees',
        builder: (context, state) => const PayeesScreen(),
      ),
      GoRoute(path: '/tags', builder: (context, state) => const TagsScreen()),
      GoRoute(
        path: '/debts',
        builder: (context, state) => const DebtsScreen(),
      ),
      GoRoute(
        path: '/accounts',
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/budget',
        builder: (context, state) => BudgetDetailScreen(
          budgetId: int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TemplatesScreen(),
      ),
      GoRoute(
        path: '/template/edit',
        builder: (context, state) => TemplateEditorScreen(
          templateId: int.tryParse(state.uri.queryParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => BackupScreen(
          importOnly: state.uri.queryParameters['import'] == '1',
        ),
      ),
    ],
  );
});

class TrackyApp extends ConsumerStatefulWidget {
  const TrackyApp({super.key});

  @override
  ConsumerState<TrackyApp> createState() => _TrackyAppState();
}

class _TrackyAppState extends ConsumerState<TrackyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAutoBackup();
      _maybeShowChangelog();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _runAutoBackup();
  }

  Future<void> _runAutoBackup() async {
    try {
      await ref.read(autoBackupServiceProvider).runIfDue();
    } catch (_) {
      // Automatic backups should never prevent the app from starting.
    }
  }

  Future<void> _maybeShowChangelog() async {
    final prefs = ref.read(preferencesProvider);
    if (!prefs.onboardingDone ||
        prefs.lastSeenChangelogVersion == appVersion ||
        !mounted) {
      return;
    }
    prefs.lastSeenChangelogVersion = appVersion;
    await showChangelogDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildLightTheme(null),
      darkTheme: buildDarkTheme(null),
      routerConfig: router,
    );
  }
}
