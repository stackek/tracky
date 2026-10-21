import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/search_picker.dart';
import '../transactions/transaction_editor_screen.dart'
    show noCategoryId, showCategoryPicker;

class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key, this.templateId});

  final int? templateId;

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();

  bool _loading = true;
  bool _dirty = false;
  bool _transfer = false;
  bool _income = false;
  int? _templateId;
  int? _accountId;
  int? _targetAccountId;
  int? _categoryId;
  int? _payeeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final accounts = await repo.activeAccounts();
    if (widget.templateId != null) {
      final template = await repo.template(widget.templateId!);
      if (template != null) {
        _templateId = template.id;
        _titleController.text = template.title;
        _commentController.text = template.comment;
        _amountController.text = formatMoneyPlain(
          template.amount.abs(),
          template.currency,
        );
        _transfer = template.transferAccount != null;
        _income = template.amount >= 0 && !_transfer;
        _accountId = template.accountId;
        _targetAccountId = template.transferAccount;
        _categoryId = template.catId;
        _payeeId = template.payeeId;
      }
    } else {
      _accountId = accounts.firstOrNull?.id;
    }
    _dirty = false;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final payees = ref.watch(payeesProvider).value ?? const <Payee>[];
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;
    final currency =
        accounts
            .where((account) => account.id == _accountId)
            .firstOrNull
            ?.currency ??
        ref.read(settingsProvider).homeCurrency;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_templateId == null ? 'New template' : 'Edit template'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(
            controller: _titleController,
            autofocus: _templateId == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Template name',
              prefixIcon: Icon(Icons.label_outline),
            ),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Expense'),
                icon: Icon(Icons.north_east),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Income'),
                icon: Icon(Icons.south_west),
              ),
              ButtonSegment(
                value: 2,
                label: Text('Transfer'),
                icon: Icon(Icons.swap_horiz),
              ),
            ],
            selected: {_transfer ? 2 : (_income ? 1 : 0)},
            onSelectionChanged: (selection) => setState(() {
              _dirty = true;
              final value = selection.first;
              _transfer = value == 2;
              _income = value == 1;
              if (_transfer && _targetAccountId == _accountId) {
                _targetAccountId = accounts
                    .where((account) => account.id != _accountId)
                    .firstOrNull
                    ?.id;
              }
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixIcon: const Icon(Icons.payments_outlined),
              suffixText: currency,
            ),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Account'),
            subtitle: Text(
              accounts
                      .where((account) => account.id == _accountId)
                      .firstOrNull
                      ?.label ??
                  'None',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickAccount,
          ),
          if (_transfer) ...[
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer to'),
              subtitle: Text(
                accounts
                        .where((account) => account.id == _targetAccountId)
                        .firstOrNull
                        ?.label ??
                    'None',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTargetAccount,
            ),
          ] else ...[
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: Icon(
                iconForCategory(category?.icon),
                color: colorFromDb(category?.color),
              ),
              title: const Text('Category'),
              subtitle: Text(category?.displayPath ?? 'No category'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await showCategoryPicker(
                  context,
                  categories
                      .where((c) => c.type == (_income ? 2 : 1) || c.type == 0)
                      .toList(),
                  initialId: _categoryId,
                  allowNone: true,
                );
                if (selected == null) return;
                setState(() {
                  _dirty = true;
                  _categoryId = selected == noCategoryId ? null : selected;
                });
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: const Icon(Icons.person_outline),
              title: const Text('Payee'),
              subtitle: Text(
                payees
                        .where((payee) => payee.id == _payeeId)
                        .firstOrNull
                        ?.name ??
                    'None',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickPayee,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note',
              prefixIcon: Icon(Icons.notes),
            ),
            onChanged: (_) => _dirty = true,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _save(currency),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _save(currency, addTransaction: true),
                  child: const Text('Save & add'),
                ),
              ),
            ],
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
    if (value != null) {
      setState(() {
        _dirty = true;
        _targetAccountId = value;
      });
    }
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
    if (value != null) {
      setState(() {
        _dirty = true;
        _payeeId = value == -1 ? null : value;
      });
    }
  }

  Future<void> _save(String currency, {bool addTransaction = false}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a template name.')));
      return;
    }
    final amount = parseAmountToMinor(_amountController.text, currency) ?? 0;
    if (amount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount.')));
      return;
    }
    if (_accountId == null) return;
    final signedAmount = (_transfer || !_income) ? -amount.abs() : amount.abs();
    final repo = ref.read(repositoryProvider);
    try {
      final int templateId;
      if (_templateId == null) {
        templateId = await repo.insertTemplate(
          title: title,
          comment: _commentController.text.trim(),
          amount: signedAmount,
          categoryId: _transfer ? null : _categoryId,
          accountId: _accountId!,
          payeeId: _payeeId,
          transferAccount: _transfer ? _targetAccountId : null,
        );
      } else {
        templateId = _templateId!;
        await repo.updateTemplate(
          templateId,
          title: title,
          comment: _commentController.text.trim(),
          amount: signedAmount,
          categoryId: _transfer ? null : _categoryId,
          accountId: _accountId!,
          payeeId: _payeeId,
          transferAccount: _transfer ? _targetAccountId : null,
        );
      }
      ref.invalidate(templatesProvider);
      _dirty = false;
      if (!addTransaction) {
        if (mounted) context.pop();
        return;
      }
      final template = await repo.template(templateId);
      if (template == null) return;
      final transactionId = await repo.applyTemplate(template);
      invalidateTransactionData(ref);
      ref.invalidate(templatesProvider);
      if (mounted) context.pushReplacement('/edit?tx=$transactionId');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    }
  }
}
