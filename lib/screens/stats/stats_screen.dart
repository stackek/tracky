import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final statsData = stats.value;
    final totalColor = statsData == null
        ? null
        : statsData.net < 0
        ? theme.colorScheme.error
        : theme.brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          statsData == null
              ? 'Statistics'
              : formatMoney(statsData.net, statsData.currency, signed: true),
          style: TextStyle(fontWeight: FontWeight.w700, color: totalColor),
        ),
      ),
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
                  onPickRange: () => _pickRange(context, ref),
                  onClearRange: () =>
                      ref.read(statsRangeProvider.notifier).set(null),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => _showAccountMenu(context, ref, accounts),
                    child: Row(
                      children: [
                        Icon(
                          selectedAccount == null
                              ? Icons.public
                              : iconForAccountType(selectedAccount.type),
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(selectedAccount?.label ?? 'All accounts'),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
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
                          onTypeChanged: (value) =>
                              ref.read(statsTypeProvider.notifier).set(value),
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
                          _CategoryBreakdown(data: data, type: statsType),
                      ],
                    );
                  },
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

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final current = ref.read(statsRangeProvider);
    final month = ref.read(statsMonthProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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
    final theme = Theme.of(context);
    if (range != null) {
      return Row(
        children: [
          IconButton(
            onPressed: onPickRange,
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Change range',
          ),
          Expanded(
            child: Text(
              '${formatShortDate(range!.start)} – ${formatShortDate(range!.end)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
        IconButton(
          onPressed: onPickRange,
          icon: const Icon(Icons.calendar_month),
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
    return Row(
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

class _CategoryBreakdown extends ConsumerStatefulWidget {
  const _CategoryBreakdown({required this.data, required this.type});

  final StatsData data;
  final StatsType type;

  @override
  ConsumerState<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends ConsumerState<_CategoryBreakdown> {
  int? _selectedCategoryId;
  bool _percent = true;
  final Set<int> _expanded = {};

  @override
  void didUpdateWidget(covariant _CategoryBreakdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _expanded.clear();
      _selectedCategoryId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final childrenByParent = <int, List<Category>>{};
    for (final category in categories) {
      final parent = category.parentId;
      if (parent != null && parent != 0 && parent != category.id) {
        childrenByParent.putIfAbsent(parent, () => []).add(category);
      }
    }
    for (final list in childrenByParent.values) {
      list.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    }

    final direct = widget.data.directAmountsFor(widget.type);
    final memo = <int, int>{};
    int totalFor(int id) {
      final cached = memo[id];
      if (cached != null) return cached;
      var sum = direct[id] ?? 0;
      for (final child in childrenByParent[id] ?? const <Category>[]) {
        sum += totalFor(child.id);
      }
      memo[id] = sum;
      return sum;
    }

    final roots = widget.data.byCategoryFor(widget.type);

    List<Category> childrenOf(int id) =>
        (childrenByParent[id] ?? const <Category>[])
            .where((child) => totalFor(child.id) > 0)
            .toList();

    CategoryTotal withTotal(CategoryTotal node) => CategoryTotal(
      categoryId: node.categoryId,
      label: node.label,
      icon: node.icon,
      color: node.color,
      amount: totalFor(node.categoryId),
    );

    CategoryTotal childTotal(Category child) => CategoryTotal(
      categoryId: child.id,
      label: child.label,
      icon: child.icon,
      color: child.color,
      amount: totalFor(child.id),
    );

    CategoryTotal otherTotal(CategoryTotal node, int amount) => CategoryTotal(
      categoryId: -1000000 - node.categoryId,
      label: 'Other',
      icon: node.icon,
      color: node.color,
      amount: amount,
    );

    bool canExpand(CategoryTotal item) =>
        item.categoryId >= 0 && childrenOf(item.categoryId).isNotEmpty;

    final listEntries = <_CategoryEntry>[];
    void addListEntry(CategoryTotal node, int depth) {
      final children = childrenOf(node.categoryId);
      final expanded =
          children.isNotEmpty && _expanded.contains(node.categoryId);
      listEntries.add(
        _CategoryEntry(
          category: withTotal(node),
          depth: depth,
          expanded: expanded,
          expandable: children.isNotEmpty,
        ),
      );
      if (!expanded) return;
      for (final child in children) {
        addListEntry(childTotal(child), depth + 1);
      }
      final own = direct[node.categoryId] ?? 0;
      if (own > 0) {
        listEntries.add(
          _CategoryEntry(
            category: otherTotal(node, own),
            depth: depth + 1,
            expanded: false,
            expandable: false,
          ),
        );
      }
    }

    final pieSlices = <CategoryTotal>[];
    final pieDepths = <int>[];
    void addPieSlice(CategoryTotal node, int depth) {
      final children = childrenOf(node.categoryId);
      if (children.isNotEmpty && _expanded.contains(node.categoryId)) {
        for (final child in children) {
          addPieSlice(childTotal(child), depth + 1);
        }
        final own = direct[node.categoryId] ?? 0;
        if (own > 0) {
          pieSlices.add(otherTotal(node, own));
          pieDepths.add(depth + 1);
        }
      } else {
        pieSlices.add(withTotal(node));
        pieDepths.add(depth);
      }
    }

    for (final root in roots) {
      addListEntry(root, 0);
      addPieSlice(root, 0);
    }

    final displayColors = <int, Color>{};
    final usedColors = <Color>[];
    for (var i = 0; i < pieSlices.length; i++) {
      final base = HSVColor.fromColor(colorFromDb(pieSlices[i].color));
      final depth = pieDepths[i];
      var hue = base.hue;
      if (depth > 0) hue = (hue + 14 + depth * 8) % 360;
      var saturation = base.saturation < 0.15 ? 0.55 : base.saturation;
      var value = depth > 0
          ? (base.value * (1 - 0.04 * depth)).clamp(0.35, 1.0)
          : base.value;
      var adjusted = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
      var guard = 0;
      while (guard++ < 80 &&
          usedColors.any(
            (color) =>
                _hueDistance(
                  HSVColor.fromColor(color).hue,
                  HSVColor.fromColor(adjusted).hue,
                ) <
                12,
          )) {
        hue = (hue + 17) % 360;
        adjusted = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
      }
      displayColors[pieSlices[i].categoryId] = adjusted;
      usedColors.add(adjusted);
    }

    final total = pieSlices.fold<int>(
      0,
      (sum, category) => sum + category.amount,
    );
    final selected = pieSlices
        .where((item) => item.categoryId == _selectedCategoryId)
        .firstOrNull;
    final selectedIndex = pieSlices.indexWhere(
      (item) => item.categoryId == _selectedCategoryId,
    );

    void handleTap(CategoryTotal item) {
      setState(() {
        if (canExpand(item)) {
          if (!_expanded.remove(item.categoryId)) {
            _expanded.add(item.categoryId);
          }
          _selectedCategoryId = null;
        } else {
          _selectedCategoryId = _selectedCategoryId == item.categoryId
              ? null
              : item.categoryId;
        }
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => _selectedCategoryId = null),
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
                          if (touched >= 0 && touched < pieSlices.length) {
                            handleTap(pieSlices[touched]);
                          }
                        }
                      },
                    ),
                    sections: [
                      for (var i = 0; i < pieSlices.length; i++)
                        PieChartSectionData(
                          value: pieSlices[i].amount.toDouble(),
                          color:
                              displayColors[pieSlices[i].categoryId] ??
                              colorFromDb(pieSlices[i].color),
                          radius: selectedIndex == i ? 64 : 50,
                          showTitle: selectedIndex == i,
                          title: selectedIndex == i
                              ? (_percent
                                    ? '${_percentage(pieSlices[i].amount, total)}%'
                                    : formatMoney(
                                        pieSlices[i].amount,
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
                        color:
                            displayColors[selected.categoryId] ??
                            colorFromDb(selected.color),
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
          for (final entry in listEntries)
            _CategoryRow(
              category: entry.category,
              color: displayColors[entry.category.categoryId],
              currency: widget.data.currency,
              percent: _percent,
              total: total,
              selected:
                  entry.expanded ||
                  _selectedCategoryId == entry.category.categoryId,
              expandable: entry.expandable,
              expanded: entry.expanded,
              indent: entry.depth * 18,
              onTap: () => handleTap(entry.category),
            ),
        ],
      ),
    );
  }
}

class _CategoryEntry {
  const _CategoryEntry({
    required this.category,
    required this.depth,
    required this.expanded,
    required this.expandable,
  });

  final CategoryTotal category;
  final int depth;
  final bool expanded;
  final bool expandable;
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    this.color,
    required this.currency,
    required this.percent,
    required this.total,
    required this.selected,
    required this.expandable,
    required this.expanded,
    required this.indent,
    required this.onTap,
  });

  final CategoryTotal category;
  final Color? color;
  final String currency;
  final bool percent;
  final int total;
  final bool selected;
  final bool expandable;
  final bool expanded;
  final double indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowColor = color ?? colorFromDb(category.color);
    return Material(
      color: selected ? rowColor.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8 + indent, 8, 8, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: rowColor.withValues(alpha: 0.18),
                child: Icon(
                  iconForCategory(category.icon),
                  size: 18,
                  color: rowColor,
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
              if (expandable)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
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

String _percentage(int amount, int total) =>
    total == 0 ? '0' : (amount * 100 / total).round().toString();

double _hueDistance(double a, double b) {
  final difference = (a - b).abs() % 360;
  return difference > 180 ? 360 - difference : difference;
}
