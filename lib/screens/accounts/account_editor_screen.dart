import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/currency_picker.dart';

class AccountEditorScreen extends ConsumerStatefulWidget {
  const AccountEditorScreen({super.key, this.accountId});

  final int? accountId;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _openingBalanceController = TextEditingController();

  bool _loading = true;
  int? _accountId;
  int _type = 1;
  String _currency = 'EUR';
  int _color = categoryColorChoices.first;
  bool _excludeFromTotals = false;
  int _flag = 0;
  String _grouping = 'NONE';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _labelController.dispose();
    _descriptionController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _currency = ref.read(settingsProvider).homeCurrency;
    if (widget.accountId != null) {
      final account = await ref.read(repositoryProvider).account(widget.accountId!);
      if (account != null) {
        _accountId = account.id;
        _labelController.text = account.label;
        _descriptionController.text = account.description;
        _openingBalanceController.text =
            formatMoneyPlain(account.openingBalance, account.currency);
        _type = account.type;
        _currency = account.currency;
        _color = account.color;
        _excludeFromTotals = account.excludeFromTotals;
        _flag = account.flag;
        _grouping = account.grouping;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final types = ref.watch(accountTypesProvider).value ?? const <AccountType>[];
    final currencies = ref.watch(currenciesProvider).value ?? const <CurrencyInfo>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_accountId == null ? 'New account' : 'Edit account'),
        actions: [
          if (_accountId != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(
            controller: _labelController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Account name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Account type',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: types
                .map((type) => DropdownMenuItem(
                      value: type.id,
                      child: Text(type.displayName),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final result =
                  await showCurrencyPicker(context, currencies, selected: _currency);
              if (result != null) setState(() => _currency = result);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Currency',
                prefixIcon: Icon(Icons.public),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_currency)),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _openingBalanceController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Opening balance',
              prefixIcon: const Icon(Icons.account_balance),
              suffixText: _currency,
              helperText: 'The balance before the first transaction',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 20),
          Text('Colour', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in categoryColorChoices)
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorFromDb(color),
                      shape: BoxShape.circle,
                      border: _color == color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: _color == color
                        ? const Icon(Icons.check, size: 20, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exclude from totals'),
            subtitle: const Text('Hide this account in the grand total'),
            value: _excludeFromTotals,
            onChanged: (value) => setState(() => _excludeFromTotals = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _flag,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Normal')),
              DropdownMenuItem(value: 1, child: Text('Favourite')),
              DropdownMenuItem(value: 2, child: Text('Archived')),
            ],
            onChanged: (value) => setState(() => _flag = value ?? 0),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _grouping,
            decoration: const InputDecoration(
              labelText: 'Grouping in transaction list',
              prefixIcon: Icon(Icons.view_agenda_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('None')),
              DropdownMenuItem(value: 'DAY', child: Text('Day')),
              DropdownMenuItem(value: 'WEEK', child: Text('Week')),
              DropdownMenuItem(value: 'MONTH', child: Text('Month')),
              DropdownMenuItem(value: 'YEAR', child: Text('Year')),
            ],
            onChanged: (value) => setState(() => _grouping = value ?? 'NONE'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _save,
            child: const Text('Save account'),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an account name.')),
      );
      return;
    }
    final opening =
        parseAmountToMinor(_openingBalanceController.text, _currency) ?? 0;
    final repo = ref.read(repositoryProvider);
    if (_accountId == null) {
      await repo.insertAccount(
        label: label,
        currency: _currency,
        type: _type,
        openingBalance: opening,
        description: _descriptionController.text.trim(),
        color: _color,
        grouping: _grouping,
        excludeFromTotals: _excludeFromTotals,
        flag: _flag,
      );
    } else {
      await repo.updateAccount(
        _accountId!,
        label: label,
        currency: _currency,
        type: _type,
        openingBalance: opening,
        description: _descriptionController.text.trim(),
        color: _color,
        grouping: _grouping,
        excludeFromTotals: _excludeFromTotals,
        flag: _flag,
      );
    }
    invalidateTransactionData(ref);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_accountId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'All transactions in this account will be deleted. This cannot be undone.',
        ),
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
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteAccount(_accountId!);
      invalidateTransactionData(ref);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $error')),
        );
      }
    }
  }
}
