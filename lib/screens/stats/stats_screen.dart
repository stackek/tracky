import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(statsMonthProvider);
    final range = ref.watch(statsRangeProvider);
    final accountId = ref.watch(statsAccountProvider);
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final stats = ref.watch(statsProvider);
    final earliest = ref.watch(earliestTransactionDateProvider).value;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final earliestMonth = earliest == null
        ? currentMonth
        : DateTime(earliest.year, earliest.month, 1);
    final canGoPrevious = range == null && month.isAfter(earliestMonth);
    final canGoNext = range == null && month.isBefore(currentMonth);
    final selectedAccount = accounts
        .where((account) => account.id == accountId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (range != null) return;
          if (velocity > 250 && canGoPrevious) {
            ref.read(statsMonthProvider.notifier).previous();
          } else if (velocity < -250 && canGoNext) {
            ref.read(statsMonthProvider.notifier).next();
          }
        },
        child: stats.when(
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(statsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                _Header(
                  month: month,
                  range: range,
                  canGoPrevious: canGoPrevious,
                  canGoNext: canGoNext,
                  onPrevious: canGoPrevious
                      ? () => ref.read(statsMonthProvider.notifier).previous()
                      : null,
                  onNext: canGoNext
                      ? () => ref.read(statsMonthProvider.notifier).next()
                      : null,
                  onPickRange: () => _pickRange(context, ref, earliest, now),
                  onClearRange: () =>
                      ref.read(statsRangeProvider.notifier).set(null),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: selectedAccount == null
                        ? const Icon(Icons.public, size: 18)
                        : Icon(
                            iconForAccountType(selectedAccount.type),
                            size: 18,
                          ),
                    label: Text(selectedAccount?.label ?? 'All accounts'),
                    onPressed: () => _showAccountMenu(context, ref, accounts),
                  ),
                ),
                const SizedBox(height: 12),
                Consumer(
                  builder: (context, ref, _) {
                    final statsType = ref.watch(statsTypeProvider);
                    final categories = data.byCategoryFor(statsType);
                    return Column(
                      children: [
                        _SummaryCards(
                          data: data,
                          theme: theme,
                          type: statsType,
                          onTypeChanged: (value) => ref
                              .read(statsTypeProvider.notifier)
                              .set(value),
                        ),
                        const SizedBox(height: 22),
                        if (categories.isEmpty)
                          EmptyState(
                            icon: Icons.pie_chart_outline,
                            title: statsType == StatsType.income
                                ? 'No income in this period'
                                : 'No expenses in this period',
                            message: statsType == StatsType.income
                                ? 'Add income to see the breakdown by category.'
                                : 'Add an expense to see the breakdown by category.',
                          )
                        else
                          _CategoryBreakdown(
                            data: data,
                            type: statsType,
                            onOpenCategory: (category) => _openCategory(
                              context,
                              ref,
                              category,
                              month,
                              range,
                              accountId,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    range == null
                        ? 'Swipe left or right to change month'
                        : 'Showing a custom date range',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load statistics:\n$error'),
            ),
          ),
        ),
      ),
    );
  }

  void _openCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryTotal category,
    DateTime month,
    DateTimeRange? range,
    int? accountId,
  ) {
    final notifier = ref.read(transactionFilterProvider.notifier);
    notifier.clear();
    if (accountId != null) notifier.setAccount(accountId);
    if (category.categoryId > 1) {
      notifier.setCategory(category.categoryId);
    }
    final from = range?.start ?? DateTime(month.year, month.month, 1);
    final to = range == null
        ? DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        : DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    notifier.setDates(from, to);
    context.go('/transactions');
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    DateTime? earliest,
    DateTime now,
  ) async {
    final current = ref.read(statsRangeProvider);
    final month = ref.read(statsMonthProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: earliest ?? DateTime(2000),
      lastDate: now,
      initialDateRange:
          current ??
          DateTimeRange(
            start: DateTime(month.year, month.month + 1, 0),
            end: DateTime(month.year, month.month + 1, 0),
          ),
      helpText: 'Statistics period',
    );
    if (range != null) {
      ref.read(statsRangeProvider.notifier).set(range);
    }
  }

  Future<void> _showAccountMenu(
    BuildContext context,
    WidgetRef ref,
    List<Account> accounts,
  ) async {
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Account',
      hint: 'Search accounts',
      selected: ref.read(statsAccountProvider) ?? -1,
      allowNone: true,
      noneLabel: 'All accounts',
      noneValue: -1,
      entries: [
        for (final account in accounts)
          PickerEntry(
            value: account.id,
            label: account.label,
            subtitle: account.currency,
            icon: iconForAccountType(account.type),
          ),
      ],
    );
    if (value == null) return;
    ref.read(statsAccountProvider.notifier).set(value == -1 ? null : value);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.range,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
    required this.onClearRange,
  });

  final DateTime month;
  final DateTimeRange? range;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  @override
  Widget build(BuildContext context) {
    if (range != null) {
      return Row(
        children: [
          IconButton(
            onPressed: onPickRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'Change range',
          ),
          Expanded(
            child: Text(
              '${formatShortDate(range!.start)} – ${formatShortDate(range!.end)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onClearRange,
            icon: const Icon(Icons.close),
            tooltip: 'Back to monthly view',
          ),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Text(
            formatMonth(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
        IconButton(
          onPressed: onPickRange,
          icon: const Icon(Icons.date_range),
          tooltip: 'Choose date range',
        ),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.data,
    required this.theme,
    required this.type,
    required this.onTypeChanged,
  });

  final StatsData data;
  final ThemeData theme;
  final StatsType type;
  final ValueChanged<StatsType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final income = data.income;
    final expense = -data.expense;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BigCard(
                label: 'Income',
                amount: income,
                currency: data.currency,
                icon: Icons.south_west,
                color: theme.colorScheme.primary,
                background: theme.colorScheme.primaryContainer,
                selected: type == StatsType.income,
                onTap: () => onTypeChanged(StatsType.income),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BigCard(
                label: 'Expenses',
                amount: expense,
                currency: data.currency,
                icon: Icons.north_east,
                color: theme.colorScheme.error,
                background: theme.colorScheme.errorContainer,
                selected: type == StatsType.expense,
                onTap: () => onTypeChanged(StatsType.expense),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                data.net >= 0 ? Icons.trending_up : Icons.trending_down,
                color: data.net >= 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Text('Net', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                formatMoney(data.net, data.currency, signed: true),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: data.net >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.icon,
    required this.color,
    required this.background,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int amount;
  final String currency;
  final IconData icon;
  final Color color;
  final Color background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 16, color: color),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoney(amount, currency),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatefulWidget {
  const _CategoryBreakdown({
    required this.data,
    required this.type,
    required this.onOpenCategory,
  });

  final StatsData data;
  final StatsType type;
  final ValueChanged<CategoryTotal> onOpenCategory;

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  int _selectedIndex = -1;
  bool _percent = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = widget.data.byCategoryFor(widget.type);
    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.amount,
    );
    final selected = _selectedIndex >= 0 && _selectedIndex < categories.length
        ? categories[_selectedIndex]
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => _selectedIndex = -1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.type == StatsType.income
                      ? 'Income by category'
                      : 'Spending by category',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Amount')),
                  ButtonSegment(value: true, label: Text('Percent')),
                ],
                selected: {_percent},
                onSelectionChanged: (value) =>
                    setState(() => _percent = value.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 56,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent) {
                          final touched =
                              response?.touchedSection?.touchedSectionIndex ??
                              -1;
                          setState(() {
                            _selectedIndex = touched == _selectedIndex
                                ? -1
                                : touched;
                          });
                        }
                      },
                    ),
                    sections: [
                      for (var i = 0; i < categories.length; i++)
                        PieChartSectionData(
                          value: categories[i].amount.toDouble(),
                          color: colorFromDb(categories[i].color),
                          radius: _selectedIndex == i ? 64 : 50,
                          showTitle: _selectedIndex == i,
                          title: _selectedIndex == i
                              ? (_percent
                                    ? '${_percentage(categories[i].amount, total)}%'
                                    : formatMoney(
                                        categories[i].amount,
                                        widget.data.currency,
                                      ))
                              : '',
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _percent
                            ? '100%'
                            : formatMoney(total, widget.data.currency),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconForCategory(selected.icon),
                        color: colorFromDb(selected.color),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _percent
                            ? '${_percentage(selected.amount, total)}%'
                            : formatMoney(
                                selected.amount,
                                widget.data.currency,
                              ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < categories.length; i++)
            _CategoryRow(
              category: categories[i],
              currency: widget.data.currency,
              percent: _percent,
              total: total,
              selected: _selectedIndex == i,
              onTap: () =>
                  setState(() => _selectedIndex = _selectedIndex == i ? -1 : i),
              onDoubleTap: () =>
                  widget.onOpenCategory(categories[i]),
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.currency,
    required this.percent,
    required this.total,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final CategoryTotal category;
  final String currency;
  final bool percent;
  final int total;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFromDb(category.color);
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(
                  iconForCategory(category.icon),
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                percent
                    ? '${_percentage(category.amount, total)}%'
                    : formatMoney(category.amount, currency),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _percentage(int amount, int total) =>
    total == 0 ? '0' : (amount * 100 / total).round().toString();
