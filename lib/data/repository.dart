import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../models/models.dart';
import 'database.dart';

const int splitCategoryId = 0;
const int transferCategoryId = 1;
const int statusVoid = 2;
const int statusArchived = 5;

const _uuid = Uuid();

String newUuid() => _uuid.v4();

class Repository {
  Repository(this.database);

  final AppDatabase database;
  final Map<String, bool> _columnCache = {};

  Database get db => database.db;

  Future<bool> _hasColumn(String table, String column) async {
    final key = '$table.$column';
    if (_columnCache.containsKey(key)) return _columnCache[key]!;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final result = columns.any((row) => row['name'] == column);
    _columnCache[key] = result;
    return result;
  }

  Future<String> get schemaVersion async {
    final value = await db.rawQuery('PRAGMA user_version');
    return (value.first.values.first ?? 0).toString();
  }

  Future<DateTime?> earliestTransactionDate() async {
    final rows = await db.rawQuery(
      'SELECT MIN(date) AS d FROM transactions WHERE status != $statusVoid AND cr_status != \'VOID\'',
    );
    if (rows.isEmpty) return null;
    final value = asInt(rows.first['d']);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }

  Future<Map<String, int>> counts() async {
    Future<int> count(String table) async => Sqflite.firstIntValue(
          await db.rawQuery('SELECT count(*) FROM $table'),
        ) ??
        0;
    return {
      'accounts': await count('accounts'),
      'transactions': await count('transactions'),
      'categories': await count('categories'),
      'payees': await count('payee'),
      'templates': await count('templates'),
    };
  }

  // ---------------------------------------------------------------- accounts

  Future<List<Account>> accounts({bool includeArchived = true}) async {
    final flagColumn = await _hasColumn('accounts', 'flag') ? 'flag' : 'hidden';
    final rows = await db.rawQuery('''
      SELECT a._id, a.label, a.opening_balance, a.description, a.currency,
             a.type, a.color, a.grouping, a.usages, a.last_used, a.sort_key,
             a.sync_account_name, a.exclude_from_totals, a.uuid, a.sort_by,
             a.sort_direction, a.criterion, a.$flagColumn AS flag, a.sealed,
             a.dynamic, a.bank_id,
             ty.label AS type_label, ty.isAsset,
             a.opening_balance + COALESCE((
                SELECT SUM(t.amount) FROM transactions t
                WHERE t.account_id = a._id
                  AND t.status != $statusVoid
                  AND t.status != $statusArchived
                  AND t.cr_status != 'VOID'
                  AND (t.cat_id IS NULL OR t.cat_id != $splitCategoryId)
             ), 0) AS balance
      FROM accounts a
      LEFT JOIN account_types ty ON ty._id = a.type
      ${includeArchived ? '' : 'WHERE a.$flagColumn != 2'}
      ORDER BY (a.$flagColumn = 2), a.sort_key, a._id
    ''');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> account(int id) async {
    final all = await accounts();
    for (final account in all) {
      if (account.id == id) return account;
    }
    return null;
  }

  Future<List<Account>> activeAccounts() async =>
      (await accounts()).where((account) => !account.isArchived).toList();

  Future<void> reorderAccounts(List<int> ids) async {
    final batch = db.batch();
    for (var index = 0; index < ids.length; index++) {
      batch.update(
        'accounts',
        {'sort_key': index},
        where: '_id = ?',
        whereArgs: [ids[index]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<AccountType>> accountTypes() async {
    final rows = await db.rawQuery(
      'SELECT _id, label, type_sort_key, isAsset, supportsReconciliation '
      'FROM account_types ORDER BY type_sort_key, _id',
    );
    return rows.map(AccountType.fromMap).toList();
  }

  Future<int> insertAccountType({
    required String label,
    required bool isAsset,
    required bool supportsReconciliation,
    required int sortKey,
  }) async {
    return db.insert('account_types', {
      'label': label,
      'type_sort_key': sortKey,
      'isAsset': isAsset ? 1 : 0,
      'supportsReconciliation': supportsReconciliation ? 1 : 0,
    });
  }

  Future<void> updateAccountType(
    int id, {
    required String label,
    required bool isAsset,
    required bool supportsReconciliation,
    required int sortKey,
  }) async {
    await db.update(
      'account_types',
      {
        'label': label,
        'type_sort_key': sortKey,
        'isAsset': isAsset ? 1 : 0,
        'supportsReconciliation': supportsReconciliation ? 1 : 0,
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> accountTypeUsage(int id) async {
    final rows = await db.rawQuery(
      'SELECT count(*) AS c FROM accounts WHERE type = ?',
      [id],
    );
    return rows.isEmpty ? 0 : asIntOr(rows.first['c'], 0);
  }

  Future<void> deleteAccountType(int id) async {
    final usage = await accountTypeUsage(id);
    if (usage > 0) {
      throw StateError(
        'This account type is used by $usage account(s) and cannot be deleted.',
      );
    }
    await db.transaction((txn) async {
      await txn.delete('accounttype_paymentmethod',
          where: 'type = ?', whereArgs: [id]);
      await txn.delete('account_types', where: '_id = ?', whereArgs: [id]);
    });
  }

  Future<int> insertAccount({
    required String label,
    required String currency,
    required int type,
    int openingBalance = 0,
    String description = '',
    int color = 0xFF90A4AE,
    String grouping = 'NONE',
    bool excludeFromTotals = false,
    int flag = 0,
  }) async {
    return db.insert('accounts', {
      'label': label,
      'opening_balance': openingBalance,
      'description': description,
      'currency': currency,
      'type': type,
      'color': color,
      'grouping': grouping,
      'exclude_from_totals': excludeFromTotals ? 1 : 0,
      'uuid': newUuid(),
      'sort_by': 'date',
      'sort_direction': 'DESC',
      'sealed': 0,
      'dynamic': 0,
      'flag': flag,
      'usages': 0,
    });
  }

  Future<void> updateAccount(
    int id, {
    required String label,
    required String currency,
    required int type,
    required int openingBalance,
    required String description,
    required int color,
    required String grouping,
    required bool excludeFromTotals,
    required int flag,
  }) async {
    await db.update(
      'accounts',
      {
        'label': label,
        'currency': currency,
        'type': type,
        'opening_balance': openingBalance,
        'description': description,
        'color': color,
        'grouping': grouping,
        'exclude_from_totals': excludeFromTotals ? 1 : 0,
        'flag': flag,
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAccount(int id) async {
    await db.transaction((txn) async {
      final peerRows = await txn.rawQuery(
        'SELECT transfer_peer FROM transactions WHERE account_id = ? AND transfer_peer IS NOT NULL',
        [id],
      );
      for (final row in peerRows) {
        final peer = asInt(row['transfer_peer']);
        if (peer != null) {
          await txn.delete('transactions', where: '_id = ?', whereArgs: [peer]);
        }
      }
      await txn.delete('accounts', where: '_id = ?', whereArgs: [id]);
    });
  }

  Future<int> accountBalance(int id) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(a.opening_balance, 0) + COALESCE(SUM(t.amount), 0) AS balance
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a._id
        AND t.status != $statusVoid
        AND t.status != $statusArchived
        AND t.cr_status != 'VOID'
        AND (t.cat_id IS NULL OR t.cat_id != $splitCategoryId)
      WHERE a._id = ?
      GROUP BY a._id
    ''', [id]);
    return rows.isEmpty ? 0 : asIntOr(rows.first['balance'], 0);
  }

  /// Returns the latest available exchange rate from each currency to
  /// [homeCurrency], using the compatible prices table.
  Future<Map<String, double>> exchangeRatesTo(String homeCurrency) async {
    final rates = <String, double>{homeCurrency: 1.0};
    final direct = await db.rawQuery('''
      SELECT p.commodity, p.value
      FROM prioritized_prices p
      WHERE p.currency = ?
        AND p.date <= date('now', 'localtime')
        AND p.date = (
          SELECT max(p2.date) FROM prioritized_prices p2
          WHERE p2.currency = p.currency AND p2.commodity = p.commodity
            AND p2.date <= date('now', 'localtime')
        )
    ''', [homeCurrency]);
    for (final row in direct) {
      final code = asStringOr(row['commodity']);
      final value = (row['value'] as num?)?.toDouble();
      if (code.isNotEmpty && value != null && value > 0) {
        rates[code] = value;
      }
    }
    final inverse = await db.rawQuery('''
      SELECT p.currency, p.value
      FROM prioritized_prices p
      WHERE p.commodity = ?
        AND p.date <= date('now', 'localtime')
        AND p.date = (
          SELECT max(p2.date) FROM prioritized_prices p2
          WHERE p2.commodity = p.commodity AND p2.currency = p.currency
            AND p2.date <= date('now', 'localtime')
        )
    ''', [homeCurrency]);
    for (final row in inverse) {
      final code = asStringOr(row['currency']);
      final value = (row['value'] as num?)?.toDouble();
      if (code.isNotEmpty && value != null && value > 0) {
        rates.putIfAbsent(code, () => 1 / value);
      }
    }
    return rates;
  }

  // -------------------------------------------------------------- categories

  Future<List<Category>> categories() async {
    final rows = await db.rawQuery('''
      WITH RECURSIVE tree(_id, label, parent_id, type, color, icon, uuid, usages, path) AS (
        SELECT c._id, c.label, c.parent_id, c.type, c.color, c.icon, c.uuid, c.usages, c.label
        FROM categories c
        WHERE c.parent_id IS NULL OR c.parent_id = c._id
        UNION ALL
        SELECT c._id, c.label, c.parent_id, c.type,
               COALESCE(c.color, tree.color), c.icon, c.uuid, c.usages,
               tree.path || ' > ' || c.label
        FROM categories c
        JOIN tree ON c.parent_id = tree._id
        WHERE c._id != tree._id
      )
      SELECT t._id, t.label, t.parent_id, t.type, t.color, t.icon, t.uuid,
             t.usages, t.path,
             (SELECT label FROM categories p WHERE p._id = t.parent_id) AS parent_label
      FROM tree t
      WHERE t._id NOT IN ($splitCategoryId, $transferCategoryId)
      ORDER BY t.label COLLATE NOCASE
    ''');
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> categoryTree() async {
    final all = await categories();
    final roots = <Category>[];
    final byParent = <int, List<Category>>{};
    for (final category in all) {
      final parent = category.parentId;
      if (parent == null || parent == 0 || parent == category.id) {
        roots.add(category);
      } else {
        byParent.putIfAbsent(parent, () => []).add(category);
      }
    }
    Category withChildren(Category category) => category.copyWith(
          children: (byParent[category.id] ?? const [])
              .map(withChildren)
              .toList()
            ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
        );
    return roots.map(withChildren).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  Future<Category?> category(int id) async {
    final all = await categories();
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<List<Category>> categoriesForType(int type) async {
    final all = await categories();
    return all.where((category) => category.type == type).toList();
  }

  Future<int> insertCategory({
    required String label,
    required int type,
    int? parentId,
    int? color,
    String? icon,
  }) async {
    return db.insert('categories', {
      'label': label,
      'label_normalized': label.toLowerCase(),
      'parent_id': parentId,
      'type': parentId == null ? type : null,
      'color': color,
      'icon': icon,
      'uuid': newUuid(),
      'usages': 0,
    });
  }

  Future<void> updateCategory(
    int id, {
    required String label,
    required int? color,
    required String? icon,
    int? parentId,
    int? type,
    bool updateParent = false,
  }) async {
    await db.update(
      'categories',
      {
        'label': label,
        'label_normalized': label.toLowerCase(),
        if (updateParent) 'parent_id': parentId,
        if (updateParent && parentId == null && type != null) 'type': type,
        if (!updateParent && type != null) 'type': type,
        'color': color,
        'icon': icon,
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<List<int>> categoryDescendants(int id) async {
    final rows = await db.rawQuery('''
      WITH RECURSIVE tree(_id) AS (
        SELECT _id FROM categories WHERE _id = ?
        UNION ALL
        SELECT c._id FROM categories c JOIN tree ON c.parent_id = tree._id
      ) SELECT _id FROM tree
    ''', [id]);
    return rows.map((row) => asIntOr(row['_id'], 0)).toList();
  }

  Future<void> deleteCategory(int id) async {
    final category = await this.category(id);
    if (category == null) return;
    final ids = await categoryDescendants(id);
    final parentId = category.parentId;
    final replacement = parentId == null || parentId == id ? null : parentId;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE transactions SET cat_id = ? WHERE cat_id IN ($placeholders)',
        [replacement, ...ids],
      );
      await txn.rawUpdate(
        'UPDATE templates SET cat_id = ? WHERE cat_id IN ($placeholders)',
        [replacement, ...ids],
      );
      await txn.delete('categories', where: '_id = ?', whereArgs: [id]);
    });
  }

  Future<List<int>> usedCategoryIds() async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT cat_id FROM transactions WHERE cat_id IS NOT NULL',
    );
    return rows.map((row) => asIntOr(row['cat_id'], 0)).toSet().toList();
  }

  // ------------------------------------------------------------------ payees

  Future<List<Payee>> payees() async {
    final rows = await db.rawQuery(
      'SELECT _id, name, short_name, iban FROM payee WHERE _id != 0 ORDER BY name COLLATE NOCASE',
    );
    return rows.map(Payee.fromMap).toList();
  }

  Future<Payee?> payee(int id) async {
    final rows = await db.query(
      'payee',
      columns: ['_id', 'name', 'short_name', 'iban'],
      where: '_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Payee.fromMap(rows.first);
  }

  Future<int> insertPayee(String name, {String? shortName, String? iban}) async {
    return db.insert('payee', {
      'name': name,
      'short_name': shortName,
      'iban': iban,
      'name_normalized': name.toLowerCase(),
    });
  }

  Future<void> updatePayee(
    int id, {
    required String name,
    String? shortName,
    String? iban,
  }) async {
    await db.update(
      'payee',
      {
        'name': name,
        'short_name': shortName,
        'iban': iban,
        'name_normalized': name.toLowerCase(),
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePayee(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        WITH RECURSIVE tree(_id) AS (
          SELECT _id FROM payee WHERE _id = ?
          UNION ALL
          SELECT p._id FROM payee p JOIN tree ON p.parent_id = tree._id
        ) SELECT _id FROM tree
      ''', [id]);
      final ids = rows.map((row) => asIntOr(row['_id'], 0)).toList();
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(',');
        await txn.rawUpdate(
          'UPDATE transactions SET payee_id = NULL WHERE payee_id IN ($placeholders)',
          ids,
        );
        await txn.rawUpdate(
          'UPDATE templates SET payee_id = NULL WHERE payee_id IN ($placeholders)',
          ids,
        );
      }
      await txn.delete('payee', where: '_id = ?', whereArgs: [id]);
    });
  }

  // -------------------------------------------------------- payment methods

  Future<List<PaymentMethod>> paymentMethods({bool includeNull = false}) async {
    final rows = await db.rawQuery(
      'SELECT _id, label, is_numbered, type, icon FROM paymentmethods '
      '${includeNull ? '' : "WHERE label != '__NULL__'"} ORDER BY _id',
    );
    return rows.map(PaymentMethod.fromMap).toList();
  }

  Future<int> insertPaymentMethod(String label) async => db.insert(
        'paymentmethods',
        {'label': label, 'is_numbered': 0, 'type': 0},
      );

  Future<void> updatePaymentMethod(
    int id, {
    required String label,
    String? icon,
  }) async {
    await db.update(
      'paymentmethods',
      {'label': label, 'icon': icon},
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePaymentMethod(int id) async {
    await db.transaction((txn) async {
      await txn.update('transactions', {'method_id': null},
          where: 'method_id = ?', whereArgs: [id]);
      await txn.update('templates', {'method_id': null},
          where: 'method_id = ?', whereArgs: [id]);
      await txn.delete('paymentmethods', where: '_id = ?', whereArgs: [id]);
    });
  }

  // -------------------------------------------------------------------- tags

  Future<List<Tag>> tags() async {
    final rows = await db.rawQuery('SELECT _id, label, color FROM tags ORDER BY label COLLATE NOCASE');
    return rows.map(Tag.fromMap).toList();
  }

  Future<int> insertTag(String label) async =>
      db.insert('tags', {'label': label});

  Future<void> updateTag(int id, {required String label}) async {
    await db.update('tags', {'label': label}, where: '_id = ?', whereArgs: [id]);
  }

  Future<void> deleteTag(int id) async {
    await db.delete('tags', where: '_id = ?', whereArgs: [id]);
  }

  Future<List<Tag>> tagsForTransaction(int transactionId) async {
    final rows = await db.rawQuery('''
      SELECT t._id, t.label, t.color FROM tags t
      JOIN transactions_tags tt ON tt.tag_id = t._id
      WHERE tt.transaction_id = ?
      ORDER BY t.label
    ''', [transactionId]);
    return rows.map(Tag.fromMap).toList();
  }

  Future<void> setTags(int transactionId, Iterable<int> tagIds) async {
    await db.transaction((txn) async {
      await txn.delete('transactions_tags',
          where: 'transaction_id = ?', whereArgs: [transactionId]);
      for (final tagId in tagIds.toSet()) {
        await txn.insert('transactions_tags', {
          'transaction_id': transactionId,
          'tag_id': tagId,
        });
      }
    });
  }

  // ------------------------------------------------------------------ debts

  Future<List<Debt>> debts({int? payeeId}) async {
    final args = <Object?>[];
    var condition = '';
    if (payeeId != null) {
      condition = 'WHERE d.payee_id = ?';
      args.add(payeeId);
    }
    final rows = await db.rawQuery('''
      SELECT d._id, d.payee_id, d.label, d.description, d.date, d.amount,
             d.equivalent_amount, d.currency, d.sealed,
             p.name AS payee_name,
             d.amount - COALESCE((
               SELECT SUM(
                 CASE WHEN t.original_currency = d.currency
                       AND t.original_amount IS NOT NULL
                      THEN t.original_amount ELSE t.amount END)
               FROM transactions t
               WHERE t.debt_id = d._id
                 AND t.status != $statusVoid
                 AND t.status != $statusArchived
                 AND t.cr_status != 'VOID'
             ), 0) AS balance
      FROM debts d
      LEFT JOIN payee p ON p._id = d.payee_id
      $condition
      ORDER BY d.date DESC, d._id DESC
    ''', args);
    return rows.map(Debt.fromMap).toList();
  }

  Future<Debt?> debt(int id) async {
    final all = await debts();
    for (final debt in all) {
      if (debt.id == id) return debt;
    }
    return null;
  }

  Future<int> insertDebt({
    required int? payeeId,
    required String label,
    required String description,
    required int amount,
    required DateTime date,
    required String currency,
    int? equivalentAmount,
  }) {
    return db.insert('debts', {
      'payee_id': payeeId,
      'label': label,
      'description': description,
      'date': toUnixTimestamp(date),
      'amount': amount,
      'equivalent_amount': equivalentAmount ?? amount,
      'currency': currency,
      'sealed': 0,
    });
  }

  Future<void> updateDebt(
    int id, {
    required int? payeeId,
    required String label,
    required String description,
    required int amount,
    required DateTime date,
    required String currency,
    int? equivalentAmount,
  }) async {
    await db.update(
      'debts',
      {
        'payee_id': payeeId,
        'label': label,
        'description': description,
        'date': toUnixTimestamp(date),
        'amount': amount,
        'equivalent_amount': equivalentAmount ?? amount,
        'currency': currency,
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDebt(int id) async {
    await db.delete('debts', where: '_id = ?', whereArgs: [id]);
  }

  Future<int?> createdDebtIdForTransaction(int transactionId) async {
    final rows = await db.query(
      'app_debt_transactions',
      columns: ['debt_id'],
      where: "transaction_id = ? AND role = 'creation'",
      whereArgs: [transactionId],
      limit: 1,
    );
    return rows.isEmpty ? null : asInt(rows.first['debt_id']);
  }

  Future<Map<int, int>> debtBalances() async {
    final list = await debts();
    return {
      for (final debt in list) debt.id: debt.currentBalance,
    };
  }

  // ---------------------------------------------------------------- currency

  Future<List<CurrencyInfo>> currencies() async {
    final rows = await db.rawQuery(
      'SELECT code, label FROM currency ORDER BY code COLLATE NOCASE',
    );
    return rows
        .map((row) => CurrencyInfo(
              code: asStringOr(row['code']),
              label: asString(row['label']),
            ))
        .toList();
  }

  Future<String> suggestedHomeCurrency() async {
    final rows = await db.rawQuery('''
      SELECT currency, COUNT(*) AS n FROM accounts GROUP BY currency ORDER BY n DESC LIMIT 1
    ''');
    if (rows.isNotEmpty) return asStringOr(rows.first['currency'], 'EUR');
    return 'EUR';
  }
}
