import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/search_picker.dart';

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
  bool _dirty = false;
  int? _accountId;
  int _type = 1;
  String _currency = 'EUR';
  int _color = categoryColorChoices.first;

  @override
  void initState() {
    super.initState();
    _labelController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _openingBalanceController.addListener(_markDirty);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _markDirty() => _dirty = true;

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
      final account = await ref
          .read(repositoryProvider)
          .account(widget.accountId!);
      if (account != null) {
        _accountId = account.id;
        _labelController.text = account.label;
        _descriptionController.text = account.description;
        _openingBalanceController.text = formatMoneyPlain(
          account.openingBalance,
          account.currency,
        );
        _type = account.type;
        _currency = account.currency;
        _color = account.color;
      }
    }
    _dirty = false;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final types =
        ref.watch(accountTypesProvider).value ?? const <AccountType>[];
    final currencies =
        ref.watch(currenciesProvider).value ?? const <CurrencyInfo>[];
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
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
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: const Icon(Icons.category_outlined),
              title: const Text('Account type'),
              subtitle: Text(
                types
                        .where((type) => type.id == _type)
                        .firstOrNull
                        ?.displayName ??
                    'None',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final value = await showSearchPicker<int>(
                  context: context,
                  title: 'Account type',
                  hint: 'Search account types',
                  selected: _type,
                  entries: [
                    for (final type in types)
                      PickerEntry(
                        value: type.id,
                        label: type.displayName,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                  ],
                );
                if (value != null) {
                  setState(() {
                    _dirty = true;
                    _type = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final result = await showCurrencyPicker(
                  context,
                  currencies,
                  selected: _currency,
                );
                if (result != null) {
                  setState(() {
                    _dirty = true;
                    _currency = result;
                  });
                }
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
                    onTap: () => setState(() {
                      _dirty = true;
                      _color = color;
                    }),
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
                          ? const Icon(
                              Icons.check,
                              size: 20,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
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

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an account name.')));
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
      );
    }
    invalidateTransactionData(ref);
    _dirty = false;
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
      _dirty = false;
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $error')));
      }
    }
  }
}
