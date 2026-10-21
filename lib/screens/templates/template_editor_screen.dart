import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
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
  bool _transfer = false;
  bool _income = false;
  int? _templateId;
  int? _accountId;
  int? _targetAccountId;
  int? _categoryId;
  int? _payeeId;
  int? _methodId;

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
        _amountController.text =
            formatMoneyPlain(template.amount.abs(), template.currency);
        _transfer = template.transferAccount != null;
        _income = template.amount >= 0 && !_transfer;
        _accountId = template.accountId;
        _targetAccountId = template.transferAccount;
        _categoryId = template.catId;
        _payeeId = template.payeeId;
        _methodId = template.methodId;
      }
    } else {
      _accountId = accounts.firstOrNull?.id;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final accounts = ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final payees = ref.watch(payeesProvider).value ?? const <Payee>[];
    final methods =
        ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;
    final currency = accounts
            .where((account) => account.id == _accountId)
            .firstOrNull
            ?.currency ??
        ref.read(settingsProvider).homeCurrency;
    return Scaffold(
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
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Account',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            items: accounts
                .map((account) => DropdownMenuItem(
                      value: account.id,
                      child: Text('${account.label} (${account.currency})'),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _accountId = value),
          ),
          if (_transfer) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _targetAccountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Transfer to',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: accounts
                  .where((account) => account.id != _accountId)
                  .map((account) => DropdownMenuItem(
                        value: account.id,
                        child: Text('${account.label} (${account.currency})'),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _targetAccountId = value),
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
                setState(() =>
                    _categoryId = selected == noCategoryId ? null : selected);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _payeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payee',
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...payees.map((payee) => DropdownMenuItem(
                      value: payee.id,
                      child: Text(payee.name),
                    )),
              ],
              onChanged: (value) => setState(() => _payeeId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _methodId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                prefixIcon: Icon(Icons.payment),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...methods.map((method) => DropdownMenuItem(
                      value: method.id,
                      child: Text(method.displayName),
                    )),
              ],
              onChanged: (value) => setState(() => _methodId = value),
            ),
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
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () => _save(currency),
            child: const Text('Save template'),
          ),
        ),
      ),
    );
  }

  Future<void> _save(String currency) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a template name.')),
      );
      return;
    }
    final amount = parseAmountToMinor(_amountController.text, currency) ?? 0;
    if (amount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount.')),
      );
      return;
    }
    if (_accountId == null) return;
    final signedAmount =
        (_transfer || !_income) ? -amount.abs() : amount.abs();
    final repo = ref.read(repositoryProvider);
    try {
      if (_templateId == null) {
        await repo.insertTemplate(
          title: title,
          comment: _commentController.text.trim(),
          amount: signedAmount,
          categoryId: _transfer ? null : _categoryId,
          accountId: _accountId!,
          payeeId: _payeeId,
          methodId: _methodId,
          transferAccount: _transfer ? _targetAccountId : null,
        );
      } else {
        await repo.updateTemplate(
          _templateId!,
          title: title,
          comment: _commentController.text.trim(),
          amount: signedAmount,
          categoryId: _transfer ? null : _categoryId,
          accountId: _accountId!,
          payeeId: _payeeId,
          methodId: _methodId,
          transferAccount: _transfer ? _targetAccountId : null,
        );
      }
      ref.invalidate(templatesProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $error')),
        );
      }
    }
  }
}
