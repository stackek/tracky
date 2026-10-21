import 'package:my_expenses_open/core/dates.dart';

int? asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

int asIntOr(Object? value, int fallback) => asInt(value) ?? fallback;

String? asString(Object? value) => value?.toString();

String asStringOr(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

bool asBool(Object? value) => value == 1 || value == true || value == '1';

class Account {
  const Account({
    required this.id,
    required this.label,
    required this.openingBalance,
    required this.currency,
    required this.type,
    required this.color,
    required this.grouping,
    required this.excludeFromTotals,
    required this.flag,
    required this.sealed,
    required this.uuid,
    required this.description,
    required this.typeLabel,
    required this.isAsset,
    required this.sortKey,
    required this.balance,
  });

  final int id;
  final String label;
  final int openingBalance;
  final String currency;
  final int type;
  final int color;
  final String grouping;
  final bool excludeFromTotals;
  final int flag;
  final bool sealed;
  final String? uuid;
  final String description;
  final String typeLabel;
  final bool isAsset;
  final int sortKey;
  final int balance;

  bool get isArchived => flag == 2;
  bool get isFavorite => flag == 1;

  String get typeDisplayName => accountTypeDisplayName(typeLabel, type);

  factory Account.fromMap(Map<String, Object?> map) => Account(
        id: asIntOr(map['_id'], 0),
        label: asStringOr(map['label']),
        openingBalance: asIntOr(map['opening_balance'], 0),
        currency: asStringOr(map['currency'], 'EUR'),
        type: asIntOr(map['type'], 1),
        color: asIntOr(map['color'], 0xFF90A4AE),
        grouping: asStringOr(map['grouping'], 'NONE'),
        excludeFromTotals: asBool(map['exclude_from_totals']),
        flag: asIntOr(map['flag'], 0),
        sealed: asBool(map['sealed']),
        uuid: asString(map['uuid']),
        description: asStringOr(map['description']),
        typeLabel: asStringOr(map['type_label']),
        isAsset: asBool(map['isAsset']),
        sortKey: asIntOr(map['sort_key'], 0),
        balance: asIntOr(map['balance'], 0),
      );
}

String accountTypeDisplayName(String label, int type) {
  switch (label) {
    case '_CASH_':
      return 'Cash';
    case '_BANK_':
      return 'Bank account';
    case '_CCARD_':
      return 'Credit card';
    case '_ASSET_':
      return 'Asset';
    case '_LIABILITY_':
      return 'Liability';
    case '_INVST_':
      return 'Investment';
  }
  switch (type) {
    case 1:
      return 'Cash';
    case 2:
      return 'Bank account';
    case 3:
      return 'Credit card';
    case 4:
      return 'Asset';
    case 5:
      return 'Liability';
    case 6:
      return 'Investment';
    default:
      return label.replaceAll('_', '');
  }
}

class AccountType {
  const AccountType({
    required this.id,
    required this.label,
    required this.isAsset,
    required this.supportsReconciliation,
    required this.sortKey,
  });

  final int id;
  final String label;
  final bool isAsset;
  final bool supportsReconciliation;
  final int sortKey;

  factory AccountType.fromMap(Map<String, Object?> map) => AccountType(
        id: asIntOr(map['_id'], 0),
        label: asStringOr(map['label']),
        isAsset: asBool(map['isAsset'] ?? map['is_asset']),
        supportsReconciliation:
            asBool(map['supportsReconciliation'] ?? map['supports_reconciliation']),
        sortKey: asIntOr(map['type_sort_key'], 0),
      );

  String get displayName {
    switch (label) {
      case '_CASH_':
        return 'Cash';
      case '_BANK_':
        return 'Bank account';
      case '_CCARD_':
        return 'Credit card';
      case '_ASSET_':
        return 'Asset';
      case '_LIABILITY_':
        return 'Liability';
      case '_INVST_':
        return 'Investment';
      default:
        return label.replaceAll('_', '');
    }
  }

  String get storageLabel {
    switch (label) {
      case '_CASH_':
        return 'Cash';
      case '_BANK_':
        return 'Bank account';
      case '_CCARD_':
        return 'Credit card';
      case '_ASSET_':
        return 'Asset';
      case '_LIABILITY_':
        return 'Liability';
      case '_INVST_':
        return 'Investment';
      default:
        return label;
    }
  }
}

class Category {
  const Category({
    required this.id,
    required this.label,
    required this.parentId,
    required this.type,
    required this.color,
    required this.icon,
    required this.uuid,
    required this.usages,
    this.parentLabel,
    this.path,
    this.children = const [],
  });

  final int id;
  final String label;
  final int? parentId;
  final int type;
  final int? color;
  final String? icon;
  final String? uuid;
  final int usages;
  final String? parentLabel;
  final String? path;
  final List<Category> children;

  bool get isExpense => type == 1;
  bool get isIncome => type == 2;
  bool get isSplit => id == 0;
  bool get isTransfer => id == 1;
  bool get isRoot => parentId == null || parentId == 0 || parentId == id;

  String get displayPath =>
      path ?? (parentLabel == null ? label : '$parentLabel > $label');

  factory Category.fromMap(Map<String, Object?> map) => Category(
        id: asIntOr(map['_id'], 0),
        label: asStringOr(map['label']),
        parentId: asInt(map['parent_id']),
        type: asIntOr(map['type'], 0),
        color: asInt(map['color']),
        icon: asString(map['icon']),
        uuid: asString(map['uuid']),
        usages: asIntOr(map['usages'], 0),
        parentLabel: asString(map['parent_label']),
        path: asString(map['path']),
      );

  Category copyWith({List<Category>? children}) => Category(
        id: id,
        label: label,
        parentId: parentId,
        type: type,
        color: color,
        icon: icon,
        uuid: uuid,
        usages: usages,
        parentLabel: parentLabel,
        path: path,
        children: children ?? this.children,
      );
}

class Payee {
  const Payee({
    required this.id,
    required this.name,
    this.shortName,
    this.iban,
  });

  final int id;
  final String name;
  final String? shortName;
  final String? iban;

  String get displayName =>
      (shortName != null && shortName!.isNotEmpty) ? shortName! : name;

  factory Payee.fromMap(Map<String, Object?> map) => Payee(
        id: asIntOr(map['_id'], 0),
        name: asStringOr(map['name']),
        shortName: asString(map['short_name']),
        iban: asString(map['iban']),
      );
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.icon,
    required this.type,
  });

  final int id;
  final String label;
  final String? icon;
  final int type;

  String get displayName {
    switch (label) {
      case '__NULL__':
        return 'None';
      case 'CHEQUE':
        return 'Cheque';
      case 'CREDITCARD':
        return 'Credit card';
      case 'DEPOSIT':
        return 'Deposit';
      case 'DIRECTDEBIT':
        return 'Direct debit';
      default:
        return label;
    }
  }

  factory PaymentMethod.fromMap(Map<String, Object?> map) => PaymentMethod(
        id: asIntOr(map['_id'], 0),
        label: asStringOr(map['label']),
        icon: asString(map['icon']),
        type: asIntOr(map['type'], 0),
      );
}

class Tag {
  const Tag({required this.id, required this.label, this.color});

  final int id;
  final String label;
  final int? color;

  factory Tag.fromMap(Map<String, Object?> map) => Tag(
        id: asIntOr(map['_id'], 0),
        label: asStringOr(map['label']),
        color: asInt(map['color']),
      );
}

class Transaction {
  const Transaction({
    required this.id,
    required this.comment,
    required this.date,
    required this.valueDate,
    required this.amount,
    required this.accountId,
    required this.status,
    required this.crStatus,
    required this.uuid,
    this.catId,
    this.payeeId,
    this.transferPeer,
    this.transferAccount,
    this.methodId,
    this.parentId,
    this.number,
    this.originalAmount,
    this.originalCurrency,
    this.debtId,
    this.categoryLabel,
    this.categoryPath,
    this.categoryIcon,
    this.categoryColor,
    this.categoryType,
    this.payeeName,
    this.methodLabel,
    this.accountLabel,
    this.accountCurrency = 'EUR',
    this.transferAccountLabel,
    this.transferAccountCurrency,
    this.tagIds = const [],
    this.attachmentCount = 0,
    this.splitCount = 0,
  });

  final int id;
  final String comment;
  final DateTime date;
  final DateTime valueDate;
  final int amount;
  final int? catId;
  final int accountId;
  final int? payeeId;
  final int? transferPeer;
  final int? transferAccount;
  final int? methodId;
  final int? parentId;
  final int status;
  final String crStatus;
  final String? number;
  final String? uuid;
  final int? originalAmount;
  final String? originalCurrency;
  final int? debtId;
  final String? categoryLabel;
  final String? categoryPath;
  final String? categoryIcon;
  final int? categoryColor;
  final int? categoryType;
  final String? payeeName;
  final String? methodLabel;
  final String? accountLabel;
  final String accountCurrency;
  final String? transferAccountLabel;
  final String? transferAccountCurrency;
  final List<int> tagIds;
  final int attachmentCount;
  final int splitCount;

  bool get isTransfer => transferPeer != null || catId == 1;
  bool get isSplit => catId == 0;
  bool get isArchived => status == 5;
  bool get isVoid => crStatus == 'VOID';
  bool get isIncome => categoryType == 2 || (categoryType == 0 && amount > 0);
  bool get isExpense => categoryType == 1 || (categoryType == 0 && amount < 0);
  String get currency => accountCurrency;

  String get title {
    if (isTransfer) {
      final other = transferAccountLabel;
      if (other == null) return 'Transfer';
      return amount < 0 ? 'Transfer to $other' : 'Transfer from $other';
    }
    if (isSplit) return comment.isNotEmpty ? comment : 'Split transaction';
    if (payeeName != null && payeeName!.isNotEmpty) return payeeName!;
    if (comment.isNotEmpty) return comment;
    if (categoryLabel != null && categoryLabel!.isNotEmpty) return categoryLabel!;
    return 'Uncategorized';
  }

  String get subtitle {
    if (isSplit) {
      return '${splitCount == 0 ? 'Split' : '$splitCount parts'}${comment.isEmpty ? '' : ' • $comment'}';
    }
    final parts = <String>[];
    if (categoryPath != null && categoryPath!.isNotEmpty) {
      parts.add(categoryPath!);
    }
    if (payeeName != null && payeeName!.isNotEmpty && title != payeeName) {
      parts.add(payeeName!);
    }
    if (comment.isNotEmpty && title != comment) parts.add(comment);
    return parts.join(' • ');
  }

  factory Transaction.fromMap(Map<String, Object?> map) {
    final tagString = asString(map['tag_ids']);
    return Transaction(
      id: asIntOr(map['_id'], 0),
      comment: asStringOr(map['comment']),
      date: fromUnixTimestamp(asIntOr(map['date'], 0)),
      valueDate: fromUnixTimestamp(asIntOr(map['value_date'], asIntOr(map['date'], 0))),
      amount: asIntOr(map['amount'], 0),
      catId: asInt(map['cat_id']),
      accountId: asIntOr(map['account_id'], 0),
      payeeId: asInt(map['payee_id']),
      transferPeer: asInt(map['transfer_peer']),
      transferAccount: asInt(map['transfer_account']),
      methodId: asInt(map['method_id']),
      parentId: asInt(map['parent_id']),
      status: asIntOr(map['status'], 0),
      crStatus: asStringOr(map['cr_status'], 'RECONCILED'),
      number: asString(map['number']),
      uuid: asString(map['uuid']),
      originalAmount: asInt(map['original_amount']),
      originalCurrency: asString(map['original_currency']),
      debtId: asInt(map['debt_id']),
      categoryLabel: asString(map['cat_label']),
      categoryPath: asString(map['cat_path']),
      categoryIcon: asString(map['cat_icon']),
      categoryColor: asInt(map['cat_color']),
      categoryType: asInt(map['cat_type']),
      payeeName: asString(map['payee_name']),
      methodLabel: asString(map['method_label']),
      accountLabel: asString(map['account_label']),
      accountCurrency: asStringOr(map['currency'], 'EUR'),
      transferAccountLabel: asString(map['transfer_account_label']),
      transferAccountCurrency: asString(map['transfer_account_currency']),
      tagIds: tagString == null || tagString.isEmpty
          ? const []
          : tagString
              .split(',')
              .map(int.tryParse)
              .whereType<int>()
              .toList(),
      attachmentCount: asIntOr(map['attachment_count'], 0),
      splitCount: asIntOr(map['split_count'], 0),
    );
  }
}

enum StatsType { expense, income }

enum TransactionFlowFilter { both, income, expense }

enum TransactionVoidFilter { both, voidOnly, nonVoid }

enum TransactionPeriod { all, thisMonth, lastMonth, last3Months, thisYear, custom }

extension TransactionPeriodLabel on TransactionPeriod {
  String get label {
    switch (this) {
      case TransactionPeriod.all:
        return 'All time';
      case TransactionPeriod.thisMonth:
        return 'This month';
      case TransactionPeriod.lastMonth:
        return 'Last month';
      case TransactionPeriod.last3Months:
        return 'Last 3 months';
      case TransactionPeriod.thisYear:
        return 'This year';
      case TransactionPeriod.custom:
        return 'Custom range';
    }
  }
}

class TransactionFilter {
  const TransactionFilter({
    this.accountId,
    this.search = '',
    this.from,
    this.to,
    this.categoryId,
    this.payeeId,
    this.tagId,
    this.minAmount,
    this.maxAmount,
    this.flow = TransactionFlowFilter.both,
    this.voidFilter = TransactionVoidFilter.both,
    this.period = TransactionPeriod.thisMonth,
  });

  final int? accountId;
  final String search;
  final DateTime? from;
  final DateTime? to;
  final int? categoryId;
  final int? payeeId;
  final int? tagId;
  final int? minAmount;
  final int? maxAmount;
  final TransactionFlowFilter flow;
  final TransactionVoidFilter voidFilter;
  final TransactionPeriod period;

  DateTime? get effectiveFrom {
    final now = DateTime.now();
    switch (period) {
      case TransactionPeriod.all:
        return null;
      case TransactionPeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case TransactionPeriod.lastMonth:
        return DateTime(now.year, now.month - 1, 1);
      case TransactionPeriod.last3Months:
        return DateTime(now.year, now.month - 2, 1);
      case TransactionPeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case TransactionPeriod.custom:
        return from;
    }
  }

  DateTime? get effectiveTo {
    final now = DateTime.now();
    switch (period) {
      case TransactionPeriod.all:
        return null;
      case TransactionPeriod.thisMonth:
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case TransactionPeriod.lastMonth:
        return DateTime(now.year, now.month, 0, 23, 59, 59);
      case TransactionPeriod.last3Months:
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case TransactionPeriod.thisYear:
        return DateTime(now.year, 12, 31, 23, 59, 59);
      case TransactionPeriod.custom:
        return to;
    }
  }

  TransactionFilter copyWith({
    int? accountId,
    bool clearAccount = false,
    String? search,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    int? categoryId,
    bool clearCategory = false,
    int? payeeId,
    bool clearPayee = false,
    int? tagId,
    bool clearTag = false,
    int? minAmount,
    bool clearMinAmount = false,
    int? maxAmount,
    bool clearMaxAmount = false,
    bool clearAmounts = false,
    TransactionFlowFilter? flow,
    TransactionVoidFilter? voidFilter,
    TransactionPeriod? period,
  }) =>
      TransactionFilter(
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        search: search ?? this.search,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
        tagId: clearTag ? null : (tagId ?? this.tagId),
        minAmount: clearAmounts || clearMinAmount
            ? null
            : (minAmount ?? this.minAmount),
        maxAmount: clearAmounts || clearMaxAmount
            ? null
            : (maxAmount ?? this.maxAmount),
        flow: flow ?? this.flow,
        voidFilter: voidFilter ?? this.voidFilter,
        period: period ?? this.period,
      );

  bool get isActive =>
      accountId != null ||
      search.isNotEmpty ||
      from != null ||
      to != null ||
      categoryId != null ||
      payeeId != null ||
      tagId != null ||
      minAmount != null ||
      maxAmount != null ||
      flow != TransactionFlowFilter.both ||
      voidFilter != TransactionVoidFilter.both ||
      period != TransactionPeriod.thisMonth;
}

enum DebtMode { none, create, resolve }

class Debt {
  const Debt({
    required this.id,
    required this.payeeId,
    required this.label,
    required this.description,
    required this.date,
    required this.amount,
    required this.currency,
    required this.equivalentAmount,
    required this.sealed,
    this.payeeName,
    this.balance,
  });

  final int id;
  final int? payeeId;
  final String label;
  final String description;
  final DateTime date;
  final int amount;
  final String currency;
  final int? equivalentAmount;
  final bool sealed;
  final String? payeeName;
  final int? balance;

  int get currentBalance => balance ?? amount;
  bool get isArchived => sealed;
  bool get isClosed => currentBalance == 0;

  factory Debt.fromMap(Map<String, Object?> map) => Debt(
        id: asIntOr(map['_id'], 0),
        payeeId: asInt(map['payee_id']),
        label: asStringOr(map['label']),
        description: asStringOr(map['description']),
        date: fromUnixTimestamp(asIntOr(map['date'], 0)),
        amount: asIntOr(map['amount'], 0),
        currency: asStringOr(map['currency'], 'EUR'),
        equivalentAmount: asInt(map['equivalent_amount']),
        sealed: asBool(map['sealed']),
        payeeName: asString(map['payee_name']),
        balance: asInt(map['balance']),
      );
}

enum DebtTransactionFilter { all, increasing, resolving }

enum DebtRemovalAction { deleteTransactions, reassign, detach }

class DebtTransactionEntry {
  const DebtTransactionEntry({
    required this.transaction,
    required this.resolving,
  });

  final Transaction transaction;
  final bool resolving;
}

class Budget {
  const Budget({
    required this.id,
    required this.title,
    required this.description,
    required this.grouping,
    required this.accountId,
    required this.currency,
    required this.isDefault,
    required this.uuid,
    this.totalBudget = 0,
  });

  final int id;
  final String title;
  final String description;
  final String grouping;
  final int? accountId;
  final String currency;
  final bool isDefault;
  final String? uuid;
  final int totalBudget;

  factory Budget.fromMap(Map<String, Object?> map) => Budget(
        id: asIntOr(map['_id'], 0),
        title: asStringOr(map['title']),
        description: asStringOr(map['description']),
        grouping: asStringOr(map['grouping'], 'MONTH'),
        accountId: asInt(map['account_id']),
        currency: asStringOr(map['currency'], 'EUR'),
        isDefault: asBool(map['is_default']),
        uuid: asString(map['uuid']),
        totalBudget: asIntOr(map['total_budget'], 0),
      );
}

class BudgetAllocation {
  const BudgetAllocation({
    required this.budgetId,
    required this.categoryId,
    required this.budget,
    required this.rollOverPrevious,
    required this.rollOverNext,
    required this.oneTime,
    required this.spent,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.categoryColor,
  });

  final int budgetId;
  final int categoryId;
  final int budget;
  final int rollOverPrevious;
  final int rollOverNext;
  final bool oneTime;
  final int spent;
  final String categoryLabel;
  final String? categoryIcon;
  final int? categoryColor;
}

class Template {
  const Template({
    required this.id,
    required this.title,
    required this.comment,
    required this.amount,
    required this.catId,
    required this.accountId,
    required this.payeeId,
    required this.methodId,
    required this.transferAccount,
    required this.uuid,
    required this.status,
    this.categoryLabel,
    this.categoryIcon,
    this.categoryColor,
    this.categoryPath,
    this.accountLabel,
    this.currency = 'EUR',
    this.payeeName,
  });

  final int id;
  final String title;
  final String comment;
  final int amount;
  final int? catId;
  final int accountId;
  final int? payeeId;
  final int? methodId;
  final int? transferAccount;
  final String? uuid;
  final int status;
  final String? categoryLabel;
  final String? categoryIcon;
  final int? categoryColor;
  final String? categoryPath;
  final String? accountLabel;
  final String currency;
  final String? payeeName;

  factory Template.fromMap(Map<String, Object?> map) => Template(
        id: asIntOr(map['_id'], 0),
        title: asStringOr(map['title']),
        comment: asStringOr(map['comment']),
        amount: asIntOr(map['amount'], 0),
        catId: asInt(map['cat_id']),
        accountId: asIntOr(map['account_id'], 0),
        payeeId: asInt(map['payee_id']),
        methodId: asInt(map['method_id']),
        transferAccount: asInt(map['transfer_account']),
        uuid: asString(map['uuid']),
        status: asIntOr(map['status'], 0),
        categoryLabel: asString(map['cat_label']),
        categoryIcon: asString(map['cat_icon']),
        categoryColor: asInt(map['cat_color']),
        categoryPath: asString(map['cat_path']),
        accountLabel: asString(map['account_label']),
        currency: asStringOr(map['currency'], 'EUR'),
        payeeName: asString(map['payee_name']),
      );
}

class Attachment {
  const Attachment({required this.id, required this.uri});

  final int id;
  final String uri;

  factory Attachment.fromMap(Map<String, Object?> map) => Attachment(
        id: asIntOr(map['_id'], 0),
        uri: asStringOr(map['uri']),
      );
}

class CurrencyInfo {
  const CurrencyInfo({required this.code, this.label});

  final String code;
  final String? label;

  String get display =>
      label == null || label!.isEmpty ? code : '$code – $label';
}

class PeriodTotals {
  const PeriodTotals({
    required this.income,
    required this.expense,
    required this.currency,
  });

  final int income;
  final int expense;
  final String currency;
}

class MonthlyTotal {
  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  final int year;
  final int month;
  final int income;
  final int expense;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.label,
    required this.icon,
    required this.color,
    required this.amount,
  });

  final int categoryId;
  final String label;
  final String? icon;
  final int? color;
  final int amount;
}

class StatsData {
  const StatsData({
    required this.income,
    required this.expense,
    required this.monthly,
    required this.byCategoryExpense,
    required this.byCategoryIncome,
    required this.currency,
  });

  final int income;
  final int expense;
  final List<MonthlyTotal> monthly;
  final List<CategoryTotal> byCategoryExpense;
  final List<CategoryTotal> byCategoryIncome;
  final String currency;

  List<CategoryTotal> byCategoryFor(StatsType type) =>
      type == StatsType.income ? byCategoryIncome : byCategoryExpense;

  int get net => income + expense;
}
