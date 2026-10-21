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
  final _numberController = TextEditingController();
  final _debtRateController = TextEditingController();
  final _debtAmountController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _splitMode = false;
  int? _editId;
  DraftType _type = DraftType.expense;
  int? _accountId;
  int? _targetAccountId;
  int? _categoryId;
  int? _payeeId;
  int? _methodId;
  DebtMode _debtMode = DebtMode.none;
  int? _debtPayeeId;
  int? _resolveDebtId;
  Debt? _resolvedDebt;
  int? _debtAmount;
  String? _debtCurrency;
  DateTime _date = DateTime.now();
  DateTime _valueDate = DateTime.now();
  String _crStatus = 'UNRECONCILED';
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
    _numberController.dispose();
    _debtRateController.dispose();
    _debtAmountController.dispose();
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
        _numberController.text = existing.number ?? '';
        _accountId = existing.accountId;
        _categoryId = existing.catId;
        _payeeId = existing.payeeId;
        _methodId = existing.methodId;
        _date = existing.date;
        _valueDate = existing.valueDate;
        _crStatus = existing.crStatus;
        _tagIds.addAll(existing.tagIds);
        _attachments.addAll(await repo.attachmentsForTransaction(existing.id));
        if (!existing.isSplit) {
          if (existing.debtId != null) {
            _debtMode = DebtMode.resolve;
            _resolveDebtId = existing.debtId;
            _resolvedDebt = await repo.debt(existing.debtId!);
            if (existing.originalAmount != null &&
                existing.originalCurrency != null) {
              _debtAmount = existing.originalAmount;
              _debtCurrency = existing.originalCurrency;
            }
          } else {
            final debtId = await repo.createdDebtIdForTransaction(existing.id);
            if (debtId != null) {
              final debt = await repo.debt(debtId);
              if (debt != null) {
                _debtMode = DebtMode.create;
                _debtPayeeId = debt.payeeId;
                _debtAmount = -debt.amount;
                _debtCurrency = debt.currency;
                _debtAmountController.text = formatMoneyPlain(
                  debt.amount.abs(),
                  debt.currency,
                );
              }
            }
          }
        }
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
          final children = await repo.children(existing.id);
          for (final child in children) {
            var debtMode = DebtMode.none;
            int? debtPayeeId;
            int? resolveDebtId;
            int? debtAmount;
            if (child.debtId != null) {
              debtMode = DebtMode.resolve;
              resolveDebtId = child.debtId;
              if (child.originalAmount != null &&
                  child.originalCurrency != null) {
                debtAmount = child.originalAmount;
              }
            } else {
              final debtId = await repo.createdDebtIdForTransaction(child.id);
              if (debtId != null) {
                final debt = await repo.debt(debtId);
                if (debt != null) {
                  debtMode = DebtMode.create;
                  debtPayeeId = debt.payeeId;
                  debtAmount = -debt.amount;
                }
              }
            }
            _parts.add(
              SplitDraft(
                id: child.id,
                categoryId: child.catId,
                amount: child.amount,
                comment: child.comment,
                debtMode: debtMode,
                debtPayeeId: debtPayeeId,
                resolveDebtId: resolveDebtId,
                debtAmount: debtAmount,
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
    if (!_splitMode &&
        _debtMode != DebtMode.none &&
        _debtAmount != null &&
        _debtNeedsConversion) {
      _debtAmountController.text = formatMoneyPlain(
        _debtAmount!.abs(),
        _debtCurrency ?? _homeCurrency,
      );
      final parsed = parseAmountToMinor(_amountController.text, _currency);
      if (parsed != null && parsed != 0) {
        _debtRateController.text = formatRate(
          _debtAmount!.abs() / parsed.abs(),
        );
      }
    }
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
    final total = _parts.fold<int>(0, (sum, part) => sum + part.amount);
    final currency = _accountCurrency;
    _amountController.text = formatMoneyPlain(total.abs(), currency);
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
    final methods =
        ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final source = accounts.where((a) => a.id == _accountId).firstOrNull;
    final target = accounts.where((a) => a.id == _targetAccountId).firstOrNull;
    final sameCurrency =
        source != null && target != null && source.currency == target.currency;
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;

    return Scaffold(
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
          if (!_splitMode)
            SegmentedButton<DraftType>(
              segments: const [
                ButtonSegment(
                  value: DraftType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: DraftType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: DraftType.transfer,
                  label: Text('Transfer'),
                  icon: Icon(Icons.swap_horiz),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() {
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
          if (_splitMode)
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
                    onPressed: () => setState(() {
                      _splitMode = false;
                      _parts.clear();
                    }),
                    child: const Text('Disable'),
                  ),
                ],
              ),
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
                ListTile(
                  leading: Icon(
                    Icons.payment,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Payment method'),
                  subtitle: Text(
                    _methodId == null
                        ? 'None'
                        : methods
                                  .where((method) => method.id == _methodId)
                                  .firstOrNull
                                  ?.displayName ??
                              'None',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickMethod,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _AmountCard(
            controller: _amountController,
            currency: _splitMode ? _currency : _currency,
            label: _splitMode
                ? 'Split total'
                : _type == DraftType.transfer
                ? 'Transfer amount'
                : 'Amount',
            readOnly: _splitMode,
            negative: _type == DraftType.expense,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Date'),
                subtitle: Text(formatDateTime(_date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Status'),
                subtitle: Text(_crStatusLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickStatus,
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
                      labelText: 'Amount received (${target?.currency ?? ''})',
                      helperText: 'Leave empty to use the same number',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_splitMode && _type != DraftType.transfer) ...[
            _SectionCard(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.handshake_outlined,
                    color: _debtMode == DebtMode.none
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                  title: const Text('Debt'),
                  subtitle: Text(_debtSummary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDebtMode,
                ),
                if (_debtMode == DebtMode.create)
                  ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Debt payee'),
                    subtitle: Text(
                      _debtPayeeId == null
                          ? 'Same as transaction payee'
                          : payees
                                    .where(
                                      (payee) => payee.id == _debtPayeeId,
                                    )
                                    .firstOrNull
                                    ?.name ??
                                'Same as transaction payee',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDebtPayee,
                  ),
                if (_debtMode == DebtMode.resolve)
                  ListTile(
                    leading: Icon(
                      Icons.receipt_long_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Debt to resolve'),
                    subtitle: Text(
                      _resolvedDebt == null
                          ? 'Choose a debt'
                          : '${_resolvedDebt!.label} • '
                                '${formatMoney(_resolvedDebt!.currentBalance, _resolvedDebt!.currency)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final debt = await _pickDebt();
                      if (debt == null) return;
                      setState(() {
                        _resolveDebtId = debt.id;
                        _resolvedDebt = debt;
                      });
                      await _prepareDebtConversion();
                    },
                  ),
                if (_debtMode != DebtMode.none && _debtNeedsConversion)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Debt amount is kept in $_homeCurrency.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _debtRateController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Exchange rate',
                                  helperText:
                                      '1 $_accountCurrency = ? $_homeCurrency',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Calculate amount',
                              icon: const Icon(Icons.south),
                              onPressed: _calculateDebtAmountFromRate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _debtAmountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Amount in $_homeCurrency',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Calculate rate',
                              icon: const Icon(Icons.north),
                              onPressed: _calculateRateFromDebtAmount,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_splitMode)
            _SplitSection(
              parts: _parts,
              categories: categories,
              currency: _currency,
              onAdd: _addSplitPart,
              onEdit: _editSplitPart,
              onDelete: (index) => setState(() {
                _parts.removeAt(index);
                _updateSplitTotal();
              }),
            )
          else if (_type != DraftType.transfer)
            _SectionCard(
              children: [
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
                  leading: const Icon(Icons.call_split),
                  title: const Text('Split into categories'),
                  subtitle: const Text('Divide this transaction into parts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() {
                      _splitMode = true;
                      if (_parts.isEmpty) {
                        final parsed = parseAmountToMinor(
                          _amountController.text,
                          _currency,
                        );
                        _parts.add(
                          SplitDraft(
                            categoryId: _categoryId,
                            amount: _type == DraftType.income
                                ? (parsed ?? 0)
                                : -(parsed ?? 0),
                          ),
                        );
                      }
                      _updateSplitTotal();
                    });
                  },
                ),
              ],
            ),
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: TextField(
                  controller: _numberController,
                  decoration: const InputDecoration(
                    labelText: 'Reference number',
                    prefixIcon: Icon(Icons.tag),
                  ),
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
            onRemoveExisting: (id) =>
                setState(() => _removedAttachmentIds.add(id)),
            onRemoveNew: (file) => setState(() => _newAttachments.remove(file)),
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
    );
  }

  String get _crStatusLabel {
    switch (_crStatus) {
      case 'CLEARED':
        return 'Cleared';
      case 'RECONCILED':
        return 'Reconciled';
      case 'VOID':
        return 'Void';
      default:
        return 'Unreconciled';
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

  Future<void> _pickStatus() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final status in const [
              'UNRECONCILED',
              'CLEARED',
              'RECONCILED',
              'VOID',
            ])
              ListTile(
                title: Text(status[0] + status.substring(1).toLowerCase()),
                trailing: _crStatus == status ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(status),
              ),
          ],
        ),
      ),
    );
    if (value != null) setState(() => _crStatus = value);
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
    setState(() => _categoryId = selected == noCategoryId ? null : selected);
  }

  Future<void> _addSplitPart() async {
    final result = await _editPartDialog();
    if (result == null) return;
    setState(() {
      _parts.add(result);
      _updateSplitTotal();
    });
  }

  Future<void> _editSplitPart(int index) async {
    final result = await _editPartDialog(initial: _parts[index]);
    if (result == null) return;
    setState(() {
      _parts[index] = result;
      _updateSplitTotal();
    });
  }

  Future<SplitDraft?> _editPartDialog({SplitDraft? initial}) async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final home = _homeCurrency;
    final amountController = TextEditingController(
      text: initial == null
          ? ''
          : formatMoneyPlain(initial.amount.abs(), _currency),
    );
    final commentController = TextEditingController(
      text: initial?.comment ?? '',
    );
    final rateController = TextEditingController();
    final homeAmountController = TextEditingController();
    var selectedCategory = initial?.categoryId;
    var expense = initial == null
        ? _type == DraftType.expense
        : initial.amount < 0;
    var debtMode = initial?.debtMode ?? DebtMode.none;
    var debtPayeeId = initial?.debtPayeeId;
    var resolveDebtId = initial?.resolveDebtId;
    var convertedAmount = initial?.debtAmount;
    var resolvedDebt = resolveDebtId == null
        ? null
        : await ref.read(repositoryProvider).debt(resolveDebtId);
    if (convertedAmount != null) {
      homeAmountController.text = formatMoneyPlain(
        convertedAmount.abs(),
        home,
      );
    }
    if (initial != null && initial.amount != 0 && _accountCurrency != home) {
      final rate = (initial.debtAmount ?? 0).abs() / initial.amount.abs();
      if (rate > 0) rateController.text = formatRate(rate);
    }
    var error = '';
    if (!mounted) return null;

    final result = await showDialog<SplitDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needsConversion = _accountCurrency != home;
          void calculateAmount() {
            final rate = double.tryParse(
              rateController.text.trim().replaceAll(',', '.'),
            );
            final parsed =
                parseAmountToMinor(amountController.text, _currency) ?? 0;
            if (rate == null || rate <= 0 || parsed == 0) return;
            final converted = (parsed * rate).round();
            convertedAmount = expense ? -converted : converted;
            homeAmountController.text = formatMoneyPlain(converted, home);
            setDialogState(() => error = '');
          }

          void calculateRate() {
            final homeAmount =
                parseAmountToMinor(homeAmountController.text, home) ?? 0;
            final parsed =
                parseAmountToMinor(amountController.text, _currency) ?? 0;
            if (homeAmount == 0 || parsed == 0) return;
            rateController.text = formatRate(homeAmount.abs() / parsed.abs());
            convertedAmount = expense
                ? -homeAmount.abs()
                : homeAmount.abs();
            setDialogState(() => error = '');
          }

          Future<void> prepareConversion() async {
            if (!needsConversion || debtMode == DebtMode.none) {
              convertedAmount = null;
              homeAmountController.clear();
              return;
            }
            if (rateController.text.trim().isEmpty) {
              final rates = await ref
                  .read(repositoryProvider)
                  .exchangeRatesTo(home);
              final rate = rates[_accountCurrency];
              if (rate != null && rate > 0) {
                rateController.text = formatRate(rate);
              }
            }
            calculateAmount();
            setDialogState(() {});
          }

          Future<void> chooseMode() async {
            final mode = await showActionSheet<DebtMode>(
              context,
              title: 'Debt',
              actions: [
                const SheetAction(
                  value: DebtMode.none,
                  label: 'Not linked',
                  icon: Icons.link_off,
                ),
                const SheetAction(
                  value: DebtMode.create,
                  label: 'Write part to debt',
                  icon: Icons.add_card,
                ),
                const SheetAction(
                  value: DebtMode.resolve,
                  label: 'Resolve a debt',
                  icon: Icons.check_circle_outline,
                ),
              ],
            );
            if (mode == null) return;
            if (mode == DebtMode.resolve) {
              final debt = await _pickDebt();
              if (debt == null) return;
              setDialogState(() {
                debtMode = DebtMode.resolve;
                resolveDebtId = debt.id;
                resolvedDebt = debt;
              });
            } else {
              setDialogState(() {
                debtMode = mode;
                if (mode == DebtMode.create) {
                  debtPayeeId ??= _payeeId;
                } else {
                  resolveDebtId = null;
                  resolvedDebt = null;
                }
              });
            }
            await prepareConversion();
          }

          Future<void> choosePayee() async {
            final value = await showSearchPicker<int>(
              context: context,
              title: 'Debt payee',
              hint: 'Search payees',
              selected: debtPayeeId ?? -1,
              allowNone: true,
              noneValue: -1,
              noneLabel: 'Same as transaction payee',
              entries: [
                for (final payee in payees)
                  PickerEntry(
                    value: payee.id,
                    label: payee.name,
                    subtitle: payee.iban,
                    icon: Icons.person_outline,
                  ),
              ],
            );
            if (value == null) return;
            setDialogState(
              () => debtPayeeId = value == -1 ? null : value,
            );
          }

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
                    onSelectionChanged: (value) => setDialogState(() {
                      expense = value.first;
                      if (convertedAmount != null) {
                        convertedAmount = expense
                            ? -convertedAmount!.abs()
                            : convertedAmount!.abs();
                      }
                    }),
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
                    onChanged: (_) {
                      if (needsConversion && debtMode != DebtMode.none) {
                        calculateAmount();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      iconForCategory(
                        categories
                            .where(
                              (category) => category.id == selectedCategory,
                            )
                            .firstOrNull
                            ?.icon,
                      ),
                    ),
                    title: const Text('Category'),
                    subtitle: Text(
                      categories
                              .where(
                                (category) => category.id == selectedCategory,
                              )
                              .firstOrNull
                              ?.displayPath ??
                          'No category',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selected = await showCategoryPicker(
                        context,
                        categories
                            .where(
                              (category) =>
                                  category.type == (expense ? 1 : 2) ||
                                  category.type == 0,
                            )
                            .toList(),
                        initialId: selectedCategory,
                        allowNone: true,
                      );
                      if (selected == null) return;
                      setDialogState(
                        () => selectedCategory = selected == noCategoryId
                            ? null
                            : selected,
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.handshake_outlined,
                      color: debtMode == DebtMode.none
                          ? null
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('Debt'),
                    subtitle: Text(
                      switch (debtMode) {
                        DebtMode.none => 'Not linked',
                        DebtMode.create =>
                          debtPayeeId == null
                              ? 'Write part to debt'
                              : 'Write part to '
                                    '${payees.where((payee) => payee.id == debtPayeeId).firstOrNull?.name ?? 'debt'}',
                        DebtMode.resolve =>
                          resolvedDebt == null
                              ? 'Resolve a debt'
                              : 'Resolve ${resolvedDebt!.label}',
                      },
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseMode,
                  ),
                  if (debtMode == DebtMode.create)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Debt payee'),
                      subtitle: Text(
                        debtPayeeId == null
                            ? 'Same as transaction payee'
                            : payees
                                      .where(
                                        (payee) => payee.id == debtPayeeId,
                                      )
                                      .firstOrNull
                                      ?.name ??
                                  'Same as transaction payee',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: choosePayee,
                    ),
                  if (debtMode == DebtMode.resolve)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Debt to resolve'),
                      subtitle: Text(
                        resolvedDebt == null
                            ? 'Choose a debt'
                            : '${resolvedDebt!.label} • '
                                  '${formatMoney(resolvedDebt!.currentBalance, resolvedDebt!.currency)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final debt = await _pickDebt();
                        if (debt == null) return;
                        setDialogState(() {
                          resolveDebtId = debt.id;
                          resolvedDebt = debt;
                        });
                        await prepareConversion();
                      },
                    ),
                  if (debtMode != DebtMode.none && needsConversion) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Debt amount is kept in $home.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rateController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Exchange rate',
                              helperText: '1 $_accountCurrency = ? $home',
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Calculate amount',
                          icon: const Icon(Icons.south),
                          onPressed: calculateAmount,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: homeAmountController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Amount in $home',
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Calculate rate',
                          icon: const Icon(Icons.north),
                          onPressed: calculateRate,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
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
                  if (debtMode == DebtMode.resolve && resolveDebtId == null) {
                    setDialogState(() => error = 'Choose a debt.');
                    return;
                  }
                  if (debtMode != DebtMode.none && needsConversion) {
                    final homeAmount = parseAmountToMinor(
                      homeAmountController.text,
                      home,
                    );
                    final rate = double.tryParse(
                      rateController.text.trim().replaceAll(',', '.'),
                    );
                    if (homeAmount == null ||
                        homeAmount == 0 ||
                        rate == null ||
                        rate <= 0) {
                      setDialogState(
                        () => error =
                            'Enter an exchange rate or the amount in $home.',
                      );
                      return;
                    }
                    convertedAmount = expense
                        ? -homeAmount.abs()
                        : homeAmount.abs();
                  } else if (debtMode == DebtMode.none) {
                    convertedAmount = null;
                  }
                  Navigator.of(context).pop(
                    SplitDraft(
                      id: initial?.id,
                      categoryId: selectedCategory,
                      amount: expense ? -parsed.abs() : parsed.abs(),
                      comment: commentController.text.trim(),
                      debtMode: debtMode,
                      debtPayeeId: debtPayeeId,
                      resolveDebtId: debtMode == DebtMode.resolve
                          ? resolveDebtId
                          : null,
                      debtAmount: debtMode == DebtMode.none
                          ? null
                          : convertedAmount,
                    ),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    disposeAfterDialog([
      amountController,
      commentController,
      rateController,
      homeAmountController,
    ]);
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
            subtitle: payee.iban,
            icon: Icons.person_outline,
          ),
      ],
    );
    if (value == null) return;
    await _selectPayee(value == -1 ? null : value);
  }

  Future<void> _pickMethod() async {
    final methods =
        ref.read(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Payment method',
      hint: 'Search payment methods',
      selected: _methodId ?? -1,
      allowNone: true,
      noneValue: -1,
      entries: [
        for (final method in methods)
          PickerEntry(
            value: method.id,
            label: method.displayName,
            icon: iconForPaymentMethod(method.icon),
          ),
      ],
    );
    if (value == null) return;
    setState(() => _methodId = value == -1 ? null : value);
  }

  Future<void> _selectPayee(int? payeeId) async {
    setState(() => _payeeId = payeeId);
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

  String get _homeCurrency => ref.read(settingsProvider).homeCurrency;

  bool get _debtNeedsConversion => _accountCurrency != _homeCurrency;

  String get _debtSummary {
    switch (_debtMode) {
      case DebtMode.none:
        return 'Not linked';
      case DebtMode.create:
        final payees = ref.read(payeesProvider).value ?? const <Payee>[];
        final name = _debtPayeeId == null
            ? null
            : payees
                  .where((payee) => payee.id == _debtPayeeId)
                  .firstOrNull
                  ?.name;
        return name == null
            ? 'Write amount to debt'
            : 'Write amount to $name\'s debt';
      case DebtMode.resolve:
        final debt = _resolvedDebt;
        if (debt == null) return 'Resolve a debt';
        return 'Resolve ${debt.label}';
    }
  }

  Future<void> _pickDebtMode() async {
    final mode = await showActionSheet<DebtMode>(
      context,
      title: 'Debt',
      actions: [
        const SheetAction(
          value: DebtMode.none,
          label: 'Not linked',
          icon: Icons.link_off,
        ),
        const SheetAction(
          value: DebtMode.create,
          label: 'Write amount to debt',
          icon: Icons.add_card,
        ),
        const SheetAction(
          value: DebtMode.resolve,
          label: 'Resolve a debt',
          icon: Icons.check_circle_outline,
        ),
      ],
    );
    if (mode == null) return;
    if (mode == DebtMode.resolve) {
      final debt = await _pickDebt();
      if (debt == null) return;
      setState(() {
        _debtMode = DebtMode.resolve;
        _resolveDebtId = debt.id;
        _resolvedDebt = debt;
      });
    } else {
      setState(() {
        _debtMode = mode;
        if (mode == DebtMode.create) {
          _debtPayeeId ??= _payeeId;
        } else {
          _resolveDebtId = null;
          _resolvedDebt = null;
        }
      });
    }
    await _prepareDebtConversion();
  }

  Future<void> _pickDebtPayee() async {
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Debt payee',
      hint: 'Search payees',
      selected: _debtPayeeId ?? -1,
      allowNone: true,
      noneValue: -1,
      noneLabel: 'Same as transaction payee',
      entries: [
        for (final payee in payees)
          PickerEntry(
            value: payee.id,
            label: payee.name,
            subtitle: payee.iban,
            icon: Icons.person_outline,
          ),
      ],
    );
    if (value == null) return;
    setState(() => _debtPayeeId = value == -1 ? null : value);
  }

  Future<Debt?> _pickDebt() async {
    final debts = (await ref.read(repositoryProvider).debts())
        .where((debt) => !debt.sealed && debt.currentBalance != 0)
        .toList();
    if (!mounted) return null;
    if (debts.isEmpty) {
      _snack('There are no open debts to resolve.');
      return null;
    }
    final value = await showSearchPicker<int>(
      context: context,
      title: 'Resolve debt',
      hint: 'Search debts',
      selected: _resolveDebtId,
      entries: [
        for (final debt in debts)
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
    if (value == null) return null;
    return debts.where((debt) => debt.id == value).firstOrNull;
  }

  Future<void> _prepareDebtConversion() async {
    if (!_debtNeedsConversion) {
      _debtAmountController.clear();
      _debtAmount = null;
      _debtCurrency = null;
      return;
    }
    _debtCurrency = _homeCurrency;
    await _prefillDebtRate();
  }

  Future<void> _prefillDebtRate() async {
    if (!_debtNeedsConversion) return;
    if (_debtRateController.text.trim().isNotEmpty) {
      _calculateDebtAmountFromRate();
      return;
    }
    final rates = await ref
        .read(repositoryProvider)
        .exchangeRatesTo(_homeCurrency);
    final rate = rates[_accountCurrency];
    if (!mounted || rate == null || rate <= 0) return;
    _debtRateController.text = formatRate(rate);
    _calculateDebtAmountFromRate();
  }

  void _calculateDebtAmountFromRate() {
    final rate = double.tryParse(
      _debtRateController.text.trim().replaceAll(',', '.'),
    );
    final parsed = parseAmountToMinor(_amountController.text, _currency) ?? 0;
    if (rate == null || rate <= 0 || parsed == 0 || !_debtNeedsConversion) {
      _debtAmount = null;
      _debtAmountController.clear();
      return;
    }
    final converted = (parsed * rate).round();
    _debtAmount = _type == DraftType.income ? converted : -converted;
    _debtCurrency = _homeCurrency;
    _debtAmountController.text = formatMoneyPlain(converted, _homeCurrency);
    if (mounted) setState(() {});
  }

  void _calculateRateFromDebtAmount() {
    final homeAmount =
        parseAmountToMinor(_debtAmountController.text, _homeCurrency) ?? 0;
    final parsed = parseAmountToMinor(_amountController.text, _currency) ?? 0;
    if (homeAmount == 0 || parsed == 0) return;
    final rate = homeAmount.abs() / parsed.abs();
    _debtRateController.text = formatRate(rate);
    final converted = homeAmount.abs();
    _debtAmount = _type == DraftType.income ? converted : -converted;
    _debtCurrency = _homeCurrency;
    setState(() {});
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
        setState(
          () => _newAttachments.addAll(files.map((file) => File(file.path))),
        );
      }
    } else {
      final file = await picker.pickImage(source: source, imageQuality: 90);
      if (file != null) {
        setState(() => _newAttachments.add(File(file.path)));
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
    if (!_splitMode && _type != DraftType.transfer) {
      if (_debtMode == DebtMode.create &&
          _debtPayeeId == null &&
          _payeeId == null) {
        _snack('Choose a payee for the debt.');
        return;
      }
      if (_debtMode == DebtMode.resolve && _resolveDebtId == null) {
        _snack('Choose the debt to resolve.');
        return;
      }
      if (_debtMode != DebtMode.none) {
        if (_debtNeedsConversion) {
          final homeAmount = parseAmountToMinor(
            _debtAmountController.text,
            _homeCurrency,
          );
          final rate = double.tryParse(
            _debtRateController.text.trim().replaceAll(',', '.'),
          );
          if (homeAmount == null ||
              homeAmount == 0 ||
              rate == null ||
              rate <= 0) {
            _snack(
              'Enter an exchange rate or the amount in $_homeCurrency.',
            );
            return;
          }
          final converted = homeAmount.abs();
          _debtAmount = _type == DraftType.income
              ? converted
              : -converted;
          _debtCurrency = _homeCurrency;
        } else {
          _debtAmount = null;
          _debtCurrency = null;
        }
      }
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
        methodId: _methodId,
        comment: _commentController.text.trim(),
        number: _numberController.text.trim(),
        crStatus: _crStatus,
        parts: _splitMode ? _parts : [],
        tagIds: _tagIds.toList(),
        debtMode: _splitMode ? DebtMode.none : _debtMode,
        debtPayeeId: _debtPayeeId,
        resolveDebtId: _resolveDebtId,
        debtAmount: _debtAmount,
        debtCurrency: _splitMode && _accountCurrency != _homeCurrency
            ? _homeCurrency
            : _debtCurrency,
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

const int noCategoryId = -1;
const int cancelCategoryId = -2;

Future<int?> showCategoryPicker(
  BuildContext context,
  List<Category> categories, {
  int? initialId,
  bool allowNone = false,
}) {
  var query = '';
  final ids = categories.map((category) => category.id).toSet();
  final roots =
      categories
          .where(
            (category) =>
                category.parentId == null ||
                category.parentId == 0 ||
                category.parentId == category.id ||
                !ids.contains(category.parentId),
          )
          .toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
  final children = <int, List<Category>>{};
  for (final category in categories) {
    final parent = category.parentId;
    if (parent != null &&
        parent != 0 &&
        parent != category.id &&
        ids.contains(parent)) {
      children.putIfAbsent(parent, () => []).add(category);
    }
  }
  for (final list in children.values) {
    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  bool containsId(Category category, int? id) {
    if (id == null) return false;
    if (category.id == id) return true;
    return (children[category.id] ?? const []).any(
      (child) => containsId(child, id),
    );
  }

  Widget tile(Category category) {
    final selected = category.id == initialId;
    final leading = Icon(
      iconForCategory(category.icon),
      color: colorFromDb(category.color),
    );
    final title = Text(category.label);
    final trailing = selected ? const Icon(Icons.check) : null;
    final childCategories = children[category.id] ?? const <Category>[];
    if (childCategories.isEmpty) {
      return ListTile(
        selected: selected,
        leading: leading,
        title: title,
        trailing: trailing,
        onTap: () => Navigator.of(context).pop(category.id),
      );
    }
    return ExpansionTile(
      initiallyExpanded: containsId(category, initialId),
      leading: leading,
      title: title,
      trailing: trailing,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 24, right: 16),
          leading: Icon(
            iconForCategory(category.icon),
            size: 20,
            color: colorFromDb(category.color),
          ),
          title: Text(category.label),
          trailing: selected ? const Icon(Icons.check) : null,
          selected: selected,
          onTap: () => Navigator.of(context).pop(category.id),
        ),
        for (final child in childCategories) tile(child),
      ],
    );
  }

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final searching = query.trim().isNotEmpty;
        final filtered = categories
            .where(
              (category) => category.displayPath.toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search categories',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              if (allowNone && !searching)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('No category'),
                  onTap: () => Navigator.of(context).pop(noCategoryId),
                ),
              Expanded(
                child: searching
                    ? ListView.builder(
                        controller: controller,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final category = filtered[index];
                          final selected = category.id == initialId;
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              iconForCategory(category.icon),
                              color: colorFromDb(category.color),
                            ),
                            title: Text(category.label),
                            subtitle: category.parentId == null
                                ? null
                                : Text(category.displayPath),
                            trailing: selected ? const Icon(Icons.check) : null,
                            onTap: () => Navigator.of(context).pop(category.id),
                          );
                        },
                      )
                    : ListView(
                        controller: controller,
                        children: [for (final root in roots) tile(root)],
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
