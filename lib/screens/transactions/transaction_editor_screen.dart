import 'dart:io';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/search_picker.dart';

class TransactionEditorScreen extends ConsumerStatefulWidget {
  const TransactionEditorScreen({
    super.key,
    this.transactionId,
    this.initialType,
    this.initialAccountId,
  });

  final int? transactionId;
  final String? initialType;
  final int? initialAccountId;

  @override
  ConsumerState<TransactionEditorScreen> createState() =>
      _TransactionEditorScreenState();
}

class _TransactionEditorScreenState
    extends ConsumerState<TransactionEditorScreen> {
  final _amountController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _commentController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _splitMode = false;
  int? _splitOriginalTotal;
  int? _editId;
  DraftType _type = DraftType.expense;
  int? _accountId;
  int? _targetAccountId;
  int? _categoryId;
  int? _payeeId;
  int? _debtId;
  DateTime _date = DateTime.now();
  DateTime _valueDate = DateTime.now();
  String _crStatus = 'RECONCILED';
  String _number = '';
  bool _dirty = false;
  final List<SplitDraft> _parts = [];
  final Set<int> _tagIds = {};
  final List<Attachment> _attachments = [];
  final List<File> _newAttachments = [];
  final List<int> _removedAttachmentIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _targetAmountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final accounts = await repo.activeAccounts();
    if (widget.transactionId != null) {
      final existing = await repo.transaction(widget.transactionId!);
      if (existing != null) {
        _editId = existing.id;
        _type = existing.isTransfer
            ? DraftType.transfer
            : existing.amount >= 0
            ? DraftType.income
            : DraftType.expense;
        _splitMode = existing.isSplit;
        var displayAmount = existing.amount.abs();
        _commentController.text = existing.comment;
        _number = existing.number ?? '';
        _accountId = existing.accountId;
        _categoryId = existing.catId;
        _payeeId = existing.payeeId;
        _date = existing.date;
        _valueDate = existing.valueDate;
        _crStatus = existing.isVoid ? 'VOID' : 'RECONCILED';
        _tagIds.addAll(existing.tagIds);
        _attachments.addAll(await repo.attachmentsForTransaction(existing.id));
        _debtId = existing.isSplit ? null : existing.debtId;
        if (existing.isTransfer) {
          final peerId = existing.transferPeer;
          final peer = peerId == null ? null : await repo.transaction(peerId);
          final sourceAccount = existing.amount <= 0
              ? existing.accountId
              : (existing.transferAccount ?? existing.accountId);
          final targetAccount = existing.amount <= 0
              ? existing.transferAccount
              : existing.accountId;
          _accountId = sourceAccount;
          _targetAccountId = targetAccount;
          if (existing.amount > 0 && peer != null) {
            displayAmount = peer.amount.abs();
          }
          final sourceCurrency =
              accounts
                  .where((account) => account.id == sourceAccount)
                  .firstOrNull
                  ?.currency ??
              existing.currency;
          final targetCurrency =
              accounts
                  .where((account) => account.id == targetAccount)
                  .firstOrNull
                  ?.currency ??
              existing.transferAccountCurrency ??
              existing.currency;
          final targetAmount = existing.amount > 0
              ? existing.amount.abs()
              : (peer?.amount.abs() ?? existing.amount.abs());
          _targetAmountController.text = formatMoneyPlain(
            targetAmount,
            targetCurrency,
          );
          _amountController.text = formatMoneyPlain(
            displayAmount,
            sourceCurrency,
          );
        } else {
          _amountController.text = formatMoneyPlain(
            displayAmount,
            existing.currency,
          );
        }
        if (existing.isSplit) {
          _splitOriginalTotal = existing.amount.abs();
          final children = await repo.children(existing.id);
          for (final child in children) {
            _parts.add(
              SplitDraft(
                id: child.id,
                categoryId: child.catId,
                amount: child.amount,
                comment: child.comment,
                debtId: child.debtId,
              ),
            );
          }
          _updateSplitTotal();
        }
      }
    } else {
      _accountId = widget.initialAccountId ?? accounts.firstOrNull?.id;
      _type = switch (widget.initialType) {
        'income' => DraftType.income,
        'transfer' => DraftType.transfer,
        _ => DraftType.expense,
      };
      if (_type == DraftType.transfer) {
        _targetAccountId = accounts
            .where((account) => account.id != _accountId)
            .firstOrNull
            ?.id;
      }
      _amountController.text = '';
    }
    _dirty = false;
    if (mounted) {
      setState(() => _loading = false);
      if (widget.transactionId == null && _type != DraftType.transfer) {
        final payees = await repo.payees();
        if (payees.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pickPayee();
          });
        }
      }
    }
  }

  void _updateSplitTotal() {
    final total = _parts.isEmpty
        ? (_splitOriginalTotal ?? 0)
        : _parts.fold<int>(0, (sum, part) => sum + part.amount);
    final currency = _accountCurrency;
    _amountController.text = formatMoneyPlain(total.abs(), currency);
  }

  void _enableSplit() {
    if (_type == DraftType.transfer) return;
    setState(() {
      _dirty = true;
      _splitMode = true;
      _splitOriginalTotal =
          parseAmountToMinor(_amountController.text, _currency) ??
          _splitOriginalTotal;
      _updateSplitTotal();
    });
  }

  Future<void> _disableSplit() async {
    if (_parts.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable split?'),
          content: const Text('All split parts will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _dirty = true;
      _splitMode = false;
      _parts.clear();
      _splitOriginalTotal = null;
    });
  }

  void _shiftDate(int days) {
    setState(() {
      _dirty = true;
      _date = _date.add(Duration(days: days));
      _valueDate = _date;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _dirty = true;
      _date = DateTime(now.year, now.month, now.day, _date.hour, _date.minute);
      _valueDate = _date;
    });
  }

  String get _accountCurrency {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    return accounts
            .where((account) => account.id == _accountId)
            .firstOrNull
            ?.currency ??
        ref.read(settingsProvider).homeCurrency;
  }

  String get _currency {
    if (_type == DraftType.transfer) return _accountCurrency;
    return _accountCurrency;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final payees = ref.watch(payeesProvider).value ?? const <Payee>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final debts = ref.watch(debtsProvider).value ?? const <Debt>[];
    final debt = debts.where((item) => item.id == _debtId).firstOrNull;
    final source = accounts.where((a) => a.id == _accountId).firstOrNull;
    final target = accounts.where((a) => a.id == _targetAccountId).firstOrNull;
    final sameCurrency =
        source != null && target != null && source.currency == target.currency;
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editId == null ? 'New transaction' : 'Edit transaction'),
          actions: [
            if (_editId != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            SegmentedButton<DraftType>(
              segments: [
                const ButtonSegment(
                  value: DraftType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
                const ButtonSegment(
                  value: DraftType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: DraftType.transfer,
                  label: const Text('Transfer'),
                  icon: const Icon(Icons.swap_horiz),
                  enabled: !_splitMode,
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                if (_splitMode && selection.first == DraftType.transfer) return;
                setState(() {
                  _dirty = true;
                  _type = selection.first;
                  if (_type == DraftType.transfer) {
                    _splitMode = false;
                    _targetAccountId ??= accounts
                        .where((account) => account.id != _accountId)
                        .firstOrNull
                        ?.id;
                  }
                });
              },
            ),
            if (_type != DraftType.transfer) ...[
              _SectionCard(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Payee'),
                    subtitle: Text(
                      _payeeId == null
                          ? 'None'
                          : payees
                                    .where((payee) => payee.id == _payeeId)
                                    .firstOrNull
                                    ?.name ??
                                'None',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Add payee',
                          icon: const Icon(Icons.add),
                          onPressed: _addPayee,
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _pickPayee,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_splitMode) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.call_split),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Split transaction')),
                    TextButton(
                      onPressed: _disableSplit,
                      child: const Text('Disable'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SplitSection(
                parts: _parts,
                categories: categories,
                currency: _currency,
                onAdd: _addSplitPart,
                onEdit: _editSplitPart,
                onDelete: (index) => setState(() {
                  _dirty = true;
                  _parts.removeAt(index);
                  _updateSplitTotal();
                }),
              ),
              const SizedBox(height: 16),
            ],
            _AmountCard(
              controller: _amountController,
              currency: _currency,
              label: _splitMode
                  ? 'Split total'
                  : _type == DraftType.transfer
                  ? 'Transfer amount'
                  : 'Amount',
              readOnly: _splitMode,
              negative: _type == DraftType.expense,
              onChanged: (_) {
                _dirty = true;
                setState(() {});
              },
            ),
            const SizedBox(height: 16),
            _SectionCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Date'),
                  subtitle: Text(formatDateTime(_date)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Previous day',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _shiftDate(-1),
                      ),
                      IconButton(
                        tooltip: 'Today',
                        icon: const Icon(Icons.today),
                        onPressed: _setToday,
                      ),
                      IconButton(
                        tooltip: 'Next day',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _shiftDate(1),
                      ),
                    ],
                  ),
                  onTap: _pickDate,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.block),
                  title: const Text('Void'),
                  subtitle: const Text(
                    'Void transactions stay in the list but are ignored in '
                    'balances and statistics',
                  ),
                  value: _crStatus == 'VOID',
                  onChanged: (value) => setState(() {
                    _dirty = true;
                    _crStatus = value ? 'VOID' : 'RECONCILED';
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Account'),
                  subtitle: Text(
                    source == null
                        ? 'None'
                        : '${source.label} (${source.currency})',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickAccount,
                ),
                if (_type == DraftType.transfer)
                  ListTile(
                    leading: Icon(
                      Icons.swap_horiz,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Transfer to'),
                    subtitle: Text(
                      target == null
                          ? 'None'
                          : '${target.label} (${target.currency})',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickTargetAccount,
                  ),
                if (_type == DraftType.transfer && !sameCurrency)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _targetAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            'Amount received (${target?.currency ?? ''})',
                        helperText: 'Leave empty to use the same number',
                      ),
                      onChanged: (_) => _dirty = true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_splitMode) ...[
              _SectionCard(
                children: [
                  if (_type != DraftType.transfer)
                    ListTile(
                      leading: Icon(
                        iconForCategory(category?.icon),
                        color: category == null
                            ? theme.colorScheme.onSurfaceVariant
                            : colorFromDb(category.color),
                      ),
                      title: const Text('Category'),
                      subtitle: Text(category?.displayPath ?? 'No category'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickCategory,
                    ),
                  ListTile(
                    enabled: _type != DraftType.transfer,
                    leading: const Icon(Icons.call_split),
                    title: const Text('Split into categories'),
                    subtitle: Text(
                      _type == DraftType.transfer
                          ? 'Not available for transfers'
                          : 'Divide this transaction into parts',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _type == DraftType.transfer ? null : _enableSplit,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (!_splitMode && _type != DraftType.transfer) ...[
              _SectionCard(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.handshake_outlined,
                      color: _debtId == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                    title: const Text('Debt'),
                    subtitle: Text(
                      debt == null
                          ? 'None'
                          : '${debt.label} • ${formatMoney(debt.currentBalance, debt.currency)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDebt,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            _SectionCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Tags'),
                  subtitle: Text(
                    _tagIds.isEmpty
                        ? 'None'
                        : tags
                              .where((tag) => _tagIds.contains(tag.id))
                              .map((tag) => tag.label)
                              .join(', '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickTags(tags),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes),
                    ),
                    onChanged: (_) => _dirty = true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AttachmentsSection(
              existing: _attachments.where(
                (attachment) => !_removedAttachmentIds.contains(attachment.id),
              ),
              newFiles: _newAttachments,
              onAdd: _addAttachment,
              onRemoveExisting: (id) => setState(() {
                _dirty = true;
                _removedAttachmentIds.add(id);
              }),
              onRemoveNew: (file) => setState(() {
                _dirty = true;
                _newAttachments.remove(file);
              }),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save transaction'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      context.pop();
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _dirty = true;
      _date = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _date.hour,
        time?.minute ?? _date.minute,
      );
      _valueDate = _date;
    });
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a category first.')));
      return;
    }
    final type = _type == DraftType.income ? 2 : 1;
    final selected = await showCategoryPicker(
      context,
      categories
          .where((category) => category.type == type || category.type == 0)
          .toList(),
      initialId: _categoryId,
      allowNone: true,
    );
    if (selected == null) return;
    setState(() {
      _dirty = true;
      _categoryId = selected == noCategoryId ? null : selected;
    });
  }

  Future<void> _addSplitPart() async {
    final result = await _editPartDialog();
    if (result == null) return;
    setState(() {
      _dirty = true;
      _parts.add(result);
      _updateSplitTotal();
    });
  }

  Future<void> _editSplitPart(int index) async {
    final result = await _editPartDialog(initial: _parts[index]);
    if (result == null) return;
    setState(() {
      _dirty = true;
      _parts[index] = result;
      _updateSplitTotal();
    });
  }

  Future<SplitDraft?> _editPartDialog({SplitDraft? initial}) async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final debts = ref.read(debtsProvider).value ?? const <Debt>[];
    final amountController = TextEditingController(
      text: initial == null
          ? ''
          : formatMoneyPlain(initial.amount.abs(), _currency),
    );
    final commentController = TextEditingController(
      text: initial?.comment ?? '',
    );
    var selectedCategory = initial?.categoryId ?? _categoryId;
    var expense = initial == null
        ? _type == DraftType.expense
        : initial.amount < 0;
    var debtId = initial?.debtId;
    var error = '';
    if (!mounted) return null;

    final result = await showDialog<SplitDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final category = categories
              .where((item) => item.id == selectedCategory)
              .firstOrNull;
          final debt = debts.where((item) => item.id == debtId).firstOrNull;
          return AlertDialog(
            title: Text(initial == null ? 'Add split part' : 'Edit split part'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Expense')),
                      ButtonSegment(value: false, label: Text('Income')),
                    ],
                    selected: {expense},
                    onSelectionChanged: (value) =>
                        setDialogState(() => expense = value.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      suffixText: _currency,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      iconForCategory(category?.icon),
                      color: category == null
                          ? null
                          : colorFromDb(category.color),
                    ),
                    title: const Text('Category'),
                    subtitle: Text(category?.displayPath ?? 'No category'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selected = await showCategoryPicker(
                        context,
                        categories
                            .where(
                              (item) =>
                                  item.type == (expense ? 1 : 2) ||
                                  item.type == 0,
                            )
                            .toList(),
                        initialId: selectedCategory,
                        allowNone: true,
                      );
                      if (selected == null) return;
                      setDialogState(() {
                        selectedCategory = selected == noCategoryId
                            ? null
                            : selected;
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('Debt'),
                    subtitle: Text(debt == null ? 'None' : debt.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Debt',
                        hint: 'Search debts',
                        selected: debtId ?? -1,
                        allowNone: true,
                        noneValue: -1,
                        noneLabel: 'None',
                        entries: [
                          for (final item in debts.where(
                            (item) => !item.isArchived,
                          ))
                            PickerEntry(
                              value: item.id,
                              label: item.label,
                              subtitle: item.payeeName,
                              icon: Icons.handshake_outlined,
                            ),
                        ],
                      );
                      if (value == null) return;
                      setDialogState(() {
                        debtId = value == -1 ? null : value;
                      });
                    },
                  ),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = parseAmountToMinor(
                    amountController.text,
                    _currency,
                  );
                  if (parsed == null || parsed == 0) {
                    setDialogState(() => error = 'Enter an amount.');
                    return;
                  }
                  Navigator.of(context).pop(
                    SplitDraft(
                      id: initial?.id,
                      categoryId: selectedCategory,
                      amount: expense ? -parsed.abs() : parsed.abs(),
                      comment: commentController.text.trim(),
                      debtId: debtId,
                    ),
                  );
                },
                child: Text(initial == null ? 'Add' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    disposeAfterDialog([amountController, commentController]);
    return result;
  }

  Future<void> _pickAccount() async {
    final accounts =
        ref.read(activeAccountsProvider).value ?? const <Account>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Account',
      hint: 'Search accounts',
      selected: _accountId,
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
    setState(() {
      _dirty = true;
      _accountId = value;
      if (_targetAccountId == value) {
        _targetAccountId = accounts
            .where((account) => account.id != value)
            .firstOrNull
            ?.id;
      }
    });
  }

  Future<void> _pickTargetAccount() async {
    final accounts =
        ref.read(activeAccountsProvider).value ?? const <Account>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Transfer to',
      hint: 'Search accounts',
      selected: _targetAccountId,
      entries: [
        for (final account in accounts)
          if (account.id != _accountId)
            PickerEntry(
              value: account.id,
              label: account.label,
              subtitle: account.currency,
              icon: iconForAccountType(account.type),
            ),
      ],
    );
    if (value == null) return;
    setState(() {
      _dirty = true;
      _targetAccountId = value;
      _targetAmountController.clear();
    });
  }

  Future<void> _pickPayee() async {
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Payee',
      hint: 'Search payees',
      selected: _payeeId ?? -1,
      allowNone: true,
      noneValue: -1,
      entries: [
        for (final payee in payees)
          PickerEntry(
            value: payee.id,
            label: payee.name,
            subtitle: payee.description,
            icon: Icons.person_outline,
          ),
      ],
    );
    if (value == null) return;
    await _selectPayee(value == -1 ? null : value);
  }

  Future<void> _selectPayee(int? payeeId) async {
    setState(() {
      _dirty = true;
      _payeeId = payeeId;
    });
    if (payeeId == null || _splitMode || _type == DraftType.transfer) return;
    final repo = ref.read(repositoryProvider);
    final previous = await repo.lastTransactionForPayee(payeeId);
    final categoryId = previous?.catId;
    if (!mounted || categoryId == null) return;
    final category = await repo.category(categoryId);
    final expected = _type == DraftType.income ? 2 : 1;
    if (!mounted ||
        category == null ||
        (category.type != expected && category.type != 0)) {
      return;
    }
    setState(() => _categoryId = categoryId);
  }

  Future<void> _pickDebt() async {
    final debts = ref.read(debtsProvider).value ?? const <Debt>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Debt',
      hint: 'Search debts',
      selected: _debtId ?? -1,
      allowNone: true,
      noneValue: -1,
      noneLabel: 'None',
      entries: [
        for (final debt in debts.where((item) => !item.isArchived))
          PickerEntry(
            value: debt.id,
            label: debt.label,
            subtitle:
                '${debt.payeeName ?? 'No payee'} • '
                '${formatMoney(debt.currentBalance, debt.currency)}',
            icon: Icons.handshake_outlined,
          ),
      ],
    );
    if (value == null) return;
    setState(() {
      _dirty = true;
      _debtId = value == -1 ? null : value;
    });
  }

  Future<void> _addPayee() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New payee'),
        content: TextField(
          controller: controller,
          autofocus: true,
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    disposeAfterDialog([controller]);
    if (name == null || name.trim().isEmpty) return;
    final id = await ref.read(repositoryProvider).insertPayee(name.trim());
    ref.invalidate(payeesProvider);
    await _selectPayee(id);
  }

  Future<void> _pickTags(List<Tag> tags) async {
    final selected = Set<int>.from(_tagIds);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Tags', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('New tag'),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                              onSubmitted: (value) =>
                                  Navigator.of(context).pop(value),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(controller.text),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        );
                        disposeAfterDialog([controller]);
                        if (name != null && name.trim().isNotEmpty) {
                          final id = await ref
                              .read(repositoryProvider)
                              .insertTag(name.trim());
                          ref.invalidate(tagsProvider);
                          setSheetState(() => selected.add(id));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No tags yet.'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        FilterChip(
                          label: Text(tag.label),
                          selected: selected.contains(tag.id),
                          onSelected: (value) => setSheetState(() {
                            if (value) {
                              selected.add(tag.id);
                            } else {
                              selected.remove(tag.id);
                            }
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _dirty = true;
                      _tagIds
                        ..clear()
                        ..addAll(selected);
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addAttachment() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final files = await picker.pickMultiImage(imageQuality: 90);
      if (files.isNotEmpty) {
        setState(() {
          _dirty = true;
          _newAttachments.addAll(files.map((file) => File(file.path)));
        });
      }
    } else {
      final file = await picker.pickImage(source: source, imageQuality: 90);
      if (file != null) {
        setState(() {
          _dirty = true;
          _newAttachments.add(File(file.path));
        });
      }
    }
  }

  Future<void> _save() async {
    if (_accountId == null) {
      _snack('Choose an account.');
      return;
    }
    if (_type == DraftType.transfer && _targetAccountId == null) {
      _snack('Choose a destination account.');
      return;
    }
    if (_type == DraftType.transfer && _targetAccountId == _accountId) {
      _snack('Choose two different accounts for a transfer.');
      return;
    }
    if (_splitMode && _parts.isEmpty) {
      _snack('Add at least one split part.');
      return;
    }
    final parsed = parseAmountToMinor(_amountController.text, _currency);
    if (!_splitMode && (parsed == null || parsed == 0)) {
      _snack('Enter an amount.');
      return;
    }
    int? targetAmount;
    if (_type == DraftType.transfer) {
      final accounts =
          ref.read(activeAccountsProvider).value ?? const <Account>[];
      final source = accounts.where((a) => a.id == _accountId).firstOrNull;
      final target = accounts
          .where((a) => a.id == _targetAccountId)
          .firstOrNull;
      if (source != null &&
          target != null &&
          source.currency != target.currency) {
        final targetParsed = parseAmountToMinor(
          _targetAmountController.text,
          target.currency,
        );
        if (targetParsed == null || targetParsed == 0) {
          _snack('Enter the amount received.');
          return;
        }
        targetAmount = targetParsed;
      }
    }

    setState(() => _saving = true);
    try {
      final draft = TransactionDraft(
        id: _editId,
        type: _splitMode ? DraftType.split : _type,
        amount: parsed ?? 0,
        accountId: _accountId,
        targetAccountId: _targetAccountId,
        targetAmount: targetAmount ?? 0,
        date: _date,
        valueDate: _valueDate,
        categoryId: _categoryId,
        payeeId: _payeeId,
        comment: _commentController.text.trim(),
        number: _number,
        crStatus: _crStatus,
        parts: _splitMode ? _parts : [],
        tagIds: _tagIds.toList(),
        debtId: _splitMode ? null : _debtId,
      );
      final repo = ref.read(repositoryProvider);
      final id = await repo.saveTransaction(draft);
      for (final file in _newAttachments) {
        await repo.addAttachment(id, file);
      }
      for (final attachmentId in _removedAttachmentIds) {
        await repo.removeAttachment(attachmentId);
      }
      if (!mounted) return;
      _dirty = false;
      invalidateTransactionData(ref);
      context.pop();
    } catch (error) {
      if (mounted) _snack('Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || _editId == null) return;
    await ref.read(repositoryProvider).deleteTransaction(_editId!);
    if (!mounted) return;
    _dirty = false;
    invalidateTransactionData(ref);
    context.pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.controller,
    required this.currency,
    required this.label,
    required this.readOnly,
    required this.negative,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final bool readOnly;
  final bool negative;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: readOnly,
            autofocus: controller.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: negative
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixText: negative ? '− ' : '',
              suffixText: currencySymbol(currency),
              hintText: '0.00',
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(children: children),
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.parts,
    required this.categories,
    required this.currency,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SplitDraft> parts;
  final List<Category> categories;
  final String currency;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          for (var i = 0; i < parts.length; i++)
            Builder(
              builder: (context) {
                final part = parts[i];
                final category = categories
                    .where((c) => c.id == part.categoryId)
                    .firstOrNull;
                return ListTile(
                  leading: Icon(
                    iconForCategory(category?.icon),
                    color: part.amount < 0
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(category?.displayPath ?? 'No category'),
                  subtitle: part.comment.isEmpty ? null : Text(part.comment),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMoney(part.amount, currency),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => onDelete(i),
                      ),
                    ],
                  ),
                  onTap: () => onEdit(i),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add part'),
                ),
                const Spacer(),
                Text(
                  '${parts.length} ${parts.length == 1 ? 'part' : 'parts'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.existing,
    required this.newFiles,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final Iterable<Attachment> existing;
  final List<File> newFiles;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<File> onRemoveNew;

  @override
  Widget build(BuildContext context) {
    final items = existing.toList();
    return _SectionCard(
      children: [
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: const Text('Attachments'),
          subtitle: Text(
            items.isEmpty && newFiles.isEmpty
                ? 'Add receipts or photos'
                : '${items.length + newFiles.length} attached',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: onAdd,
          ),
        ),
        if (items.isNotEmpty || newFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final attachment in items)
                  _AttachmentThumb(
                    label: p.basename(attachment.uri),
                    file: File(attachment.uri),
                    onRemove: () => onRemoveExisting(attachment.id),
                  ),
                for (final file in newFiles)
                  _AttachmentThumb(
                    label: p.basename(file.path),
                    file: file,
                    onRemove: () => onRemoveNew(file),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.label,
    required this.file,
    required this.onRemove,
  });

  final String label;
  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 84,
            height: 84,
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(Icons.insert_drive_file_outlined),
                  ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}
