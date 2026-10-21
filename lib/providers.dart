import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/currency.dart';
import 'core/prefs.dart';
import 'data/auto_backup_service.dart';
import 'data/backup_service.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'data/transaction_repository.dart';
import 'models/models.dart';

export 'data/transaction_repository.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final preferencesProvider = Provider<AppPreferences>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);

final repositoryProvider = Provider<Repository>(
  (ref) => Repository(ref.watch(databaseProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    repository: ref.watch(repositoryProvider),
    preferences: ref.watch(preferencesProvider),
  ),
);

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(
    preferences: ref.watch(preferencesProvider),
    backupService: ref.watch(backupServiceProvider),
  ),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(preferencesProvider);
    MoneyFormatConfig.customFractionDigits = prefs.currencyDecimals;
    MoneyFormatConfig.decimalSeparator = prefs.decimalSeparator;
    MoneyFormatConfig.groupSeparator = prefs.groupSeparator;
    return AppSettings(
      homeCurrency: prefs.homeCurrency,
      themeMode: prefs.themeMode,
      dynamicColor: prefs.dynamicColor,
      currencyDecimals: prefs.currencyDecimals,
      decimalSeparator: prefs.decimalSeparator,
      groupSeparator: prefs.groupSeparator,
    );
  }

  Future<void> setHomeCurrency(String currency) async {
    ref.read(preferencesProvider).homeCurrency = currency;
    state = state.copyWith(homeCurrency: currency);
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(statsProvider);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    ref.read(preferencesProvider).themeMode = mode;
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setDynamicColor(bool value) async {
    ref.read(preferencesProvider).dynamicColor = value;
    state = state.copyWith(dynamicColor: value);
  }

  Future<void> setCurrencyFormat({
    required int? decimals,
    required String decimalSeparator,
    required String groupSeparator,
  }) async {
    final prefs = ref.read(preferencesProvider);
    await prefs.setCurrencyDecimals(decimals);
    await prefs.setDecimalSeparator(decimalSeparator);
    await prefs.setGroupSeparator(groupSeparator);
    MoneyFormatConfig.customFractionDigits = decimals;
    MoneyFormatConfig.decimalSeparator = decimalSeparator;
    MoneyFormatConfig.groupSeparator = groupSeparator;
    state = state.copyWith(
      currencyDecimals: decimals,
      clearCurrencyDecimals: decimals == null,
      decimalSeparator: decimalSeparator,
      groupSeparator: groupSeparator,
    );
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(budgetsProvider);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void setAccount(int? accountId) {
    state = accountId == null
        ? state.copyWith(clearAccount: true)
        : state.copyWith(accountId: accountId);
  }

  void setSearch(String search) => state = state.copyWith(search: search);

  void setCategory(int? categoryId) {
    state = categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId);
  }

  void setPayee(int? payeeId) {
    state = payeeId == null
        ? state.copyWith(clearPayee: true)
        : state.copyWith(payeeId: payeeId);
  }

  void setDates(DateTime? from, DateTime? to) {
    final end = to == null
        ? null
        : DateTime(to.year, to.month, to.day, 23, 59, 59);
    state = from == null && end == null
        ? state.copyWith(clearDates: true)
        : state.copyWith(from: from, to: end, period: TransactionPeriod.custom);
  }

  void setPeriod(TransactionPeriod period) {
    state = period == TransactionPeriod.custom
        ? state.copyWith(period: period)
        : state.copyWith(period: period, clearDates: true);
  }

  void setTag(int? tagId) {
    state = tagId == null
        ? state.copyWith(clearTag: true)
        : state.copyWith(tagId: tagId);
  }

  void setAmountRange(int? minAmount, int? maxAmount) {
    state = state.copyWith(
      minAmount: minAmount,
      maxAmount: maxAmount,
      clearMinAmount: minAmount == null,
      clearMaxAmount: maxAmount == null,
    );
  }

  void setFlow(TransactionFlowFilter flow) =>
      state = state.copyWith(flow: flow);

  void setVoidFilter(TransactionVoidFilter value) =>
      state = state.copyWith(voidFilter: value);

  void clear() => state = const TransactionFilter();
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
      TransactionFilterNotifier.new,
    );

class TransactionStatsPeriodNotifier extends Notifier<TransactionPeriod> {
  @override
  TransactionPeriod build() => TransactionPeriod.thisMonth;

  void set(TransactionPeriod value) => state = value;
}

final transactionStatsPeriodProvider =
    NotifierProvider<TransactionStatsPeriodNotifier, TransactionPeriod>(
      TransactionStatsPeriodNotifier.new,
    );

class TransactionStatsRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  void set(DateTimeRange? value) => state = value;
}

final transactionStatsRangeProvider =
    NotifierProvider<TransactionStatsRangeNotifier, DateTimeRange?>(
      TransactionStatsRangeNotifier.new,
    );

class StatsMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime(DateTime.now().year, DateTime.now().month, 1);

  void previous() => state = DateTime(state.year, state.month - 1, 1);
  void next() => state = DateTime(state.year, state.month + 1, 1);
  void set(DateTime value) => state = DateTime(value.year, value.month, 1);
}

final statsMonthProvider = NotifierProvider<StatsMonthNotifier, DateTime>(
  StatsMonthNotifier.new,
);

class StatsTypeNotifier extends Notifier<StatsType> {
  @override
  StatsType build() => StatsType.expense;

  void set(StatsType value) => state = value;
}

final statsTypeProvider = NotifierProvider<StatsTypeNotifier, StatsType>(
  StatsTypeNotifier.new,
);

class StatsAccountNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? value) => state = value;
}

final statsAccountProvider = NotifierProvider<StatsAccountNotifier, int?>(
  StatsAccountNotifier.new,
);

class StatsRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  void set(DateTimeRange? value) => state = value;
}

final statsRangeProvider = NotifierProvider<StatsRangeNotifier, DateTimeRange?>(
  StatsRangeNotifier.new,
);

final accountsProvider = FutureProvider<List<Account>>(
  (ref) => ref.watch(repositoryProvider).accounts(),
);

final activeAccountsProvider = FutureProvider<List<Account>>(
  (ref) => ref.watch(repositoryProvider).activeAccounts(),
);

final accountLastTransactionProvider = FutureProvider<Map<int, DateTime>>(
  (ref) => ref.watch(repositoryProvider).lastTransactionDates(),
);

final accountTypesProvider = FutureProvider<List<AccountType>>(
  (ref) => ref.watch(repositoryProvider).accountTypes(),
);

final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(repositoryProvider).categories(),
);

final categoryTreeProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(repositoryProvider).categoryTree(),
);

final payeesProvider = FutureProvider<List<Payee>>(
  (ref) => ref.watch(repositoryProvider).payees(),
);

final tagsProvider = FutureProvider<List<Tag>>(
  (ref) => ref.watch(repositoryProvider).tags(),
);

final currenciesProvider = FutureProvider<List<CurrencyInfo>>(
  (ref) => ref.watch(repositoryProvider).currencies(),
);

final exchangeRatesProvider = FutureProvider<Map<String, double>>((ref) {
  final settings = ref.watch(settingsProvider);
  return ref
      .watch(repositoryProvider)
      .exchangeRatesTo(settings.homeCurrency);
});

final transactionsProvider = FutureProvider<List<Transaction>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(repositoryProvider).transactions(filter);
});

final periodTotalsProvider = FutureProvider<PeriodTotals>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final period = ref.watch(transactionStatsPeriodProvider);
  final range = ref.watch(transactionStatsRangeProvider);
  final settings = ref.watch(settingsProvider);
  final statsFilter = TransactionFilter(
    accountId: filter.accountId,
    period: period,
    from: range?.start,
    to: range == null
        ? null
        : DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
  );
  return ref
      .watch(repositoryProvider)
      .periodTotals(
        accountId: statsFilter.accountId,
        from: statsFilter.effectiveFrom,
        to: statsFilter.effectiveTo,
        homeCurrency: settings.homeCurrency,
      );
});

final transactionProvider = FutureProvider.family<Transaction?, int>(
  (ref, id) => ref.watch(repositoryProvider).transaction(id),
);

final splitChildrenProvider = FutureProvider.family<List<Transaction>, int>(
  (ref, parentId) => ref.watch(repositoryProvider).children(parentId),
);

final transactionAttachmentsProvider =
    FutureProvider.family<List<Attachment>, int>(
      (ref, transactionId) => ref
          .watch(repositoryProvider)
          .attachmentsForTransaction(transactionId),
    );

final earliestTransactionDateProvider = FutureProvider<DateTime?>(
  (ref) => ref.watch(repositoryProvider).earliestTransactionDate(),
);

final statsProvider = FutureProvider<StatsData>((ref) {
  final month = ref.watch(statsMonthProvider);
  final accountId = ref.watch(statsAccountProvider);
  final range = ref.watch(statsRangeProvider);
  final settings = ref.watch(settingsProvider);
  return ref
      .watch(repositoryProvider)
      .stats(
        accountId: accountId,
        month: month,
        rangeFrom: range?.start,
        rangeTo: range?.end,
        homeCurrency: settings.homeCurrency,
      );
});

final debtsProvider = FutureProvider<List<Debt>>(
  (ref) => ref.watch(repositoryProvider).debts(),
);

final budgetsProvider = FutureProvider<List<Budget>>(
  (ref) => ref.watch(repositoryProvider).budgets(),
);

class BudgetPeriod {
  const BudgetPeriod(this.budgetId, this.year, this.month);

  final int budgetId;
  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is BudgetPeriod &&
      other.budgetId == budgetId &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(budgetId, year, month);
}

final budgetAllocationsProvider =
    FutureProvider.family<List<BudgetAllocation>, BudgetPeriod>(
      (ref, period) => ref
          .watch(repositoryProvider)
          .budgetAllocations(
            budgetId: period.budgetId,
            year: period.year,
            month: period.month,
          ),
    );

final templatesProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(repositoryProvider).templates(),
);

void invalidateTransactionData(WidgetRef ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(activeAccountsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(periodTotalsProvider);
  ref.invalidate(statsProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(debtsProvider);
}

void invalidateLookupData(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  ref.invalidate(categoryTreeProvider);
  ref.invalidate(payeesProvider);
  ref.invalidate(tagsProvider);
}
