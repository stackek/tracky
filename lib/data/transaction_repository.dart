import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../core/dates.dart';
import '../models/models.dart';
import 'repository.dart';

enum DraftType { expense, income, transfer, split }

class SplitDraft {
  SplitDraft({
    this.id,
    this.categoryId,
    this.amount = 0,
    this.comment = '',
    this.debtMode = DebtMode.none,
    this.debtPayeeId,
    this.resolveDebtId,
    this.debtAmount,
  });

  int? id;
  int? categoryId;
  int amount;
  String comment;
  DebtMode debtMode;
  int? debtPayeeId;
  int? resolveDebtId;
  int? debtAmount;
}

class TransactionDraft {
  TransactionDraft({
    this.id,
    this.type = DraftType.expense,
    this.amount = 0,
    this.accountId,
    this.targetAccountId,
    this.targetAmount = 0,
    DateTime? date,
    DateTime? valueDate,
    this.categoryId,
    this.payeeId,
    this.methodId,
    this.comment = '',
    this.number = '',
    this.crStatus = 'UNRECONCILED',
    List<SplitDraft>? parts,
    List<int>? tagIds,
    this.debtMode = DebtMode.none,
    this.debtPayeeId,
    this.resolveDebtId,
    this.debtAmount,
    this.debtCurrency,
  }) : date = date ?? DateTime.now(),
       valueDate = valueDate ?? date ?? DateTime.now(),
       parts = parts ?? [],
       tagIds = tagIds ?? [];

  int? id;
  DraftType type;
  int amount;
  int? accountId;
  int? targetAccountId;
  int targetAmount;
  DateTime date;
  DateTime valueDate;
  int? categoryId;
  int? payeeId;
  int? methodId;
  String comment;
  String number;
  String crStatus;
  List<SplitDraft> parts;
  List<int> tagIds;
  DebtMode debtMode;
  int? debtPayeeId;
  int? resolveDebtId;
  int? debtAmount;
  String? debtCurrency;
}

extension TransactionRepository on Repository {
  Future<List<Transaction>> transactions(
    TransactionFilter filter, {
    bool includeArchived = false,
  }) async {
    final args = <Object?>[];
    final conditions = <String>['t.parent_id IS NULL'];
    switch (filter.voidFilter) {
      case TransactionVoidFilter.both:
        break;
      case TransactionVoidFilter.voidOnly:
        conditions.add('t.status = $statusVoid');
      case TransactionVoidFilter.nonVoid:
        conditions.add('t.status != $statusVoid');
    }
    if (!includeArchived) conditions.add('t.status != $statusArchived');
    if (filter.accountId != null) {
      conditions.add('t.account_id = ?');
      args.add(filter.accountId);
    }
    if (filter.payeeId != null) {
      conditions.add('t.payee_id = ?');
      args.add(filter.payeeId);
    }
    if (filter.tagId != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM transactions_tags tt '
        'WHERE tt.transaction_id = t._id AND tt.tag_id = ?)',
      );
      args.add(filter.tagId);
    }
    if (filter.minAmount != null) {
      conditions.add('ABS(t.amount) >= ?');
      args.add(filter.minAmount);
    }
    if (filter.maxAmount != null) {
      conditions.add('ABS(t.amount) <= ?');
      args.add(filter.maxAmount);
    }
    switch (filter.flow) {
      case TransactionFlowFilter.both:
        break;
      case TransactionFlowFilter.income:
        conditions.add('t.amount > 0');
      case TransactionFlowFilter.expense:
        conditions.add('t.amount < 0');
    }
    if (filter.categoryId != null) {
      final ids = await categoryDescendants(filter.categoryId!);
      if (ids.isEmpty) {
        conditions.add('1 = 0');
      } else {
        conditions.add(
          't.cat_id IN (${List.filled(ids.length, '?').join(',')})',
        );
        args.addAll(ids);
      }
    }
    if (filter.effectiveFrom != null || filter.effectiveTo != null) {
      if (filter.effectiveFrom != null) {
        conditions.add('t.date >= ?');
        args.add(toUnixTimestamp(filter.effectiveFrom!));
      }
      if (filter.effectiveTo != null) {
        conditions.add('t.date <= ?');
        args.add(toUnixTimestamp(filter.effectiveTo!));
      }
    }
    if (filter.search.trim().isNotEmpty) {
      final term = '%${filter.search.trim()}%';
      conditions.add(
        '(t.comment LIKE ? OR t.number LIKE ? OR p.name LIKE ? OR c.label LIKE ? OR a.label LIKE ?)',
      );
      args.addAll([term, term, term, term, term]);
    }

    final rows = await db.rawQuery('''
      WITH RECURSIVE cat_tree(_id, path, icon, color) AS (
        SELECT c._id, c.label, c.icon, c.color
        FROM categories c
        WHERE c.parent_id IS NULL OR c.parent_id = c._id
        UNION ALL
        SELECT c._id, cat_tree.path || ' > ' || c.label,
               COALESCE(c.icon, cat_tree.icon),
               COALESCE(c.color, cat_tree.color)
        FROM categories c
        JOIN cat_tree ON c.parent_id = cat_tree._id
        WHERE c._id != cat_tree._id
      )
      SELECT t._id, t.comment, t.date, t.value_date, t.amount, t.cat_id,
             t.account_id, t.payee_id, t.transfer_peer, t.transfer_account,
             t.method_id, t.parent_id, t.status, t.cr_status, t.number, t.uuid,
             t.original_amount, t.original_currency, t.debt_id,
             c.label AS cat_label, cat_tree.path AS cat_path,
             cat_tree.icon AS cat_icon, cat_tree.color AS cat_color,
             c.type AS cat_type,
             p.name AS payee_name, m.label AS method_label,
             a.label AS account_label, a.currency AS currency,
             ta.label AS transfer_account_label,
             ta.currency AS transfer_account_currency,
             (SELECT group_concat(tt.tag_id, ',') FROM transactions_tags tt
                WHERE tt.transaction_id = t._id) AS tag_ids,
             (SELECT count(*) FROM transaction_attachments x
                WHERE x.transaction_id = t._id) AS attachment_count,
             (SELECT count(*) FROM transactions ch
                WHERE ch.parent_id = t._id) AS split_count
      FROM transactions t
      LEFT JOIN categories c ON c._id = t.cat_id
      LEFT JOIN cat_tree ON cat_tree._id = t.cat_id
      LEFT JOIN payee p ON p._id = t.payee_id
      LEFT JOIN paymentmethods m ON m._id = t.method_id
      LEFT JOIN accounts a ON a._id = t.account_id
      LEFT JOIN accounts ta ON ta._id = t.transfer_account
      WHERE ${conditions.join(' AND ')}
      ORDER BY t.date DESC, t._id DESC
    ''', args);
    return rows.map(Transaction.fromMap).toList();
  }

  Future<Transaction?> lastTransactionForAccount(int accountId) async {
    final list = await transactions(
      TransactionFilter(accountId: accountId, period: TransactionPeriod.all),
    );
    for (final transaction in list) {
      if (!transaction.isSplit &&
          !transaction.isTransfer &&
          !transaction.isVoid &&
          transaction.payeeId != null) {
        return transaction;
      }
    }
    return null;
  }

  Future<Transaction?> lastTransactionForPayee(int payeeId) async {
    final list = await transactions(
      TransactionFilter(payeeId: payeeId, period: TransactionPeriod.all),
    );
    for (final transaction in list) {
      if (!transaction.isSplit &&
          !transaction.isTransfer &&
          !transaction.isVoid &&
          transaction.catId != null) {
        return transaction;
      }
    }
    return null;
  }

  Future<Transaction?> transaction(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.*, c.label AS cat_label, c.type AS cat_type, c.icon AS cat_icon,
             c.color AS cat_color, p.name AS payee_name, m.label AS method_label,
             a.label AS account_label, a.currency AS currency,
             ta.label AS transfer_account_label,
             ta.currency AS transfer_account_currency,
             (SELECT group_concat(tt.tag_id, ',') FROM transactions_tags tt
                WHERE tt.transaction_id = t._id) AS tag_ids,
             (SELECT count(*) FROM transaction_attachments x
                WHERE x.transaction_id = t._id) AS attachment_count,
             (SELECT count(*) FROM transactions ch
                WHERE ch.parent_id = t._id) AS split_count,
             c.label AS cat_path
      FROM transactions t
      LEFT JOIN categories c ON c._id = t.cat_id
      LEFT JOIN payee p ON p._id = t.payee_id
      LEFT JOIN paymentmethods m ON m._id = t.method_id
      LEFT JOIN accounts a ON a._id = t.account_id
      LEFT JOIN accounts ta ON ta._id = t.transfer_account
      WHERE t._id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  Future<List<Transaction>> children(int parentId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.*, c.label AS cat_label, c.type AS cat_type, c.icon AS cat_icon,
             c.color AS cat_color, c.label AS cat_path
      FROM transactions t
      LEFT JOIN categories c ON c._id = t.cat_id
      WHERE t.parent_id = ?
      ORDER BY t._id
    ''',
      [parentId],
    );
    return rows.map(Transaction.fromMap).toList();
  }

  Future<int> _insert(
    DatabaseExecutor txn, {
    required int accountId,
    required int amount,
    required DateTime date,
    DateTime? valueDate,
    int? catId,
    int? payeeId,
    int? methodId,
    int? parentId,
    int? transferPeer,
    int? transferAccount,
    String comment = '',
    String number = '',
    String crStatus = 'UNRECONCILED',
    String? uuid,
    int? debtId,
    int? originalAmount,
    String? originalCurrency,
  }) {
    return txn.insert('transactions', {
      'comment': comment,
      'date': toUnixTimestamp(date),
      'value_date': toUnixTimestamp(valueDate ?? date),
      'amount': amount,
      'cat_id': catId,
      'account_id': accountId,
      'payee_id': payeeId,
      'transfer_peer': transferPeer,
      'transfer_account': transferAccount,
      'method_id': methodId,
      'parent_id': parentId,
      'status': 0,
      'cr_status': crStatus,
      'number': number,
      'uuid': uuid ?? newUuid(),
      'debt_id': crStatus == 'VOID' ? null : debtId,
      'original_amount': crStatus == 'VOID' ? null : originalAmount,
      'original_currency': crStatus == 'VOID' ? null : originalCurrency,
    });
  }

  Future<int> saveTransaction(TransactionDraft draft) async {
    final id = await db.transaction((txn) async {
      Transaction? existing;
      if (draft.id != null) {
        existing = await _transactionWithTxn(txn, draft.id!);
      }
      int? previousCreationDebtId;
      if (existing != null) {
        previousCreationDebtId = await _createdDebtId(txn, existing.id);
        if (existing.isSplit) {
          final oldChildren = await _childIds(txn, existing.id);
          for (final childId in oldChildren) {
            await _removeCreatedDebt(txn, childId);
          }
        }
        if (draft.type == DraftType.transfer || draft.parts.isNotEmpty) {
          await _removeCreatedDebt(txn, existing.id);
          previousCreationDebtId = null;
        }
      }

      int resultId;
      if (existing == null) {
        resultId = await _insertDraft(txn, draft);
      } else if (existing.isTransfer) {
        if (draft.type != DraftType.transfer) {
          await _deleteWithTxn(txn, existing.id);
          resultId = await _insertDraft(txn, draft);
        } else {
          resultId = await _updateTransfer(txn, existing, draft);
        }
      } else if (draft.type == DraftType.transfer) {
        await _deleteWithTxn(txn, existing.id);
        resultId = await _insertDraft(txn, draft);
      } else if (draft.parts.isNotEmpty) {
        resultId = await _updateSplit(txn, existing, draft);
      } else {
        if (existing.isSplit) {
          await txn.delete(
            'transactions',
            where: 'parent_id = ?',
            whereArgs: [existing.id],
          );
        }
        resultId = await _updateSimple(txn, existing, draft);
      }

      if (draft.type != DraftType.transfer && draft.crStatus != 'VOID') {
        if (draft.parts.isNotEmpty) {
          final childIds = await _childIds(txn, resultId);
          for (var i = 0; i < draft.parts.length && i < childIds.length; i++) {
            final part = draft.parts[i];
            await _applyCreatedDebt(
              txn,
              transactionId: childIds[i],
              previousDebtId: null,
              mode: part.debtMode,
              payeeId: part.debtPayeeId ?? draft.payeeId,
              convertedAmount: part.debtAmount,
              transactionAmount: part.amount,
              date: draft.date,
              comment: part.comment.isNotEmpty ? part.comment : draft.comment,
              currency: draft.debtCurrency,
              accountId: draft.accountId!,
            );
          }
        } else {
          final amount = draft.type == DraftType.income
              ? draft.amount.abs()
              : -draft.amount.abs();
          await _applyCreatedDebt(
            txn,
            transactionId: resultId,
            previousDebtId: previousCreationDebtId,
            mode: draft.debtMode,
            payeeId: draft.debtPayeeId ?? draft.payeeId,
            convertedAmount: draft.debtAmount,
            transactionAmount: amount,
            date: draft.date,
            comment: draft.comment,
            currency: draft.debtCurrency,
            accountId: draft.accountId!,
          );
        }
      }
      return resultId;
    });
    await setTags(id, draft.tagIds);
    return id;
  }

  Future<List<int>> _childIds(DatabaseExecutor txn, int parentId) async {
    final rows = await txn.query(
      'transactions',
      columns: ['_id'],
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: '_id',
    );
    return rows.map((row) => asIntOr(row['_id'], 0)).toList();
  }

  Future<int?> _createdDebtId(
    DatabaseExecutor txn,
    int transactionId,
  ) async {
    final rows = await txn.query(
      'app_debt_transactions',
      columns: ['debt_id'],
      where: "transaction_id = ? AND role = 'creation'",
      whereArgs: [transactionId],
      limit: 1,
    );
    return rows.isEmpty ? null : asInt(rows.first['debt_id']);
  }

  Future<void> _removeCreatedDebt(
    DatabaseExecutor txn,
    int transactionId,
  ) async {
    final debtId = await _createdDebtId(txn, transactionId);
    if (debtId == null) return;
    await txn.delete(
      'app_debt_transactions',
      where: "transaction_id = ? AND role = 'creation'",
      whereArgs: [transactionId],
    );
    await txn.delete('debts', where: '_id = ?', whereArgs: [debtId]);
  }

  Future<String> _accountCurrency(
    DatabaseExecutor txn,
    int accountId,
  ) async {
    final rows = await txn.query(
      'accounts',
      columns: ['currency'],
      where: '_id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isEmpty ? 'EUR' : asStringOr(rows.first['currency'], 'EUR');
  }

  Future<void> _applyCreatedDebt(
    DatabaseExecutor txn, {
    required int transactionId,
    required int? previousDebtId,
    required DebtMode mode,
    required int? payeeId,
    required int? convertedAmount,
    required int transactionAmount,
    required DateTime date,
    required String comment,
    required String? currency,
    required int accountId,
  }) async {
    if (mode != DebtMode.create) {
      if (previousDebtId != null) {
        await _removeCreatedDebt(txn, transactionId);
      }
      return;
    }
    final debtCurrency =
        currency ?? await _accountCurrency(txn, accountId);
    final amount = -(convertedAmount ?? transactionAmount);
    final label = comment.trim().isEmpty ? 'Debt' : comment.trim();
    final values = {
      'payee_id': payeeId,
      'label': label,
      'description': comment.trim(),
      'date': toUnixTimestamp(date),
      'amount': amount,
      'equivalent_amount': amount,
      'currency': debtCurrency,
    };
    if (previousDebtId != null) {
      await txn.update(
        'debts',
        values,
        where: '_id = ?',
        whereArgs: [previousDebtId],
      );
      final link = await txn.query(
        'app_debt_transactions',
        columns: ['debt_id'],
        where: "transaction_id = ? AND role = 'creation'",
        whereArgs: [transactionId],
        limit: 1,
      );
      if (link.isEmpty) {
        await txn.insert('app_debt_transactions', {
          'transaction_id': transactionId,
          'debt_id': previousDebtId,
          'role': 'creation',
        });
      }
      return;
    }
    final debtId = await txn.insert('debts', values);
    await txn.insert('app_debt_transactions', {
      'transaction_id': transactionId,
      'debt_id': debtId,
      'role': 'creation',
    });
  }

  Future<int> _insertDraft(DatabaseExecutor txn, TransactionDraft draft) async {
    if (draft.type == DraftType.transfer) {
      return _insertTransfer(txn, draft);
    }
    if (draft.parts.isNotEmpty) {
      return _insertSplit(txn, draft);
    }
    final amount = draft.type == DraftType.income
        ? draft.amount.abs()
        : -draft.amount.abs();
    return _insert(
      txn,
      accountId: draft.accountId!,
      amount: amount,
      date: draft.date,
      valueDate: draft.valueDate,
      catId: draft.categoryId,
      payeeId: draft.payeeId,
      methodId: draft.methodId,
      comment: draft.comment,
      number: draft.number,
      crStatus: draft.crStatus,
      debtId: draft.resolveDebtId,
      originalAmount: draft.resolveDebtId == null ? null : draft.debtAmount,
      originalCurrency: draft.resolveDebtId == null ? null : draft.debtCurrency,
    );
  }

  Future<int> _insertSplit(DatabaseExecutor txn, TransactionDraft draft) async {
    final total = draft.parts.fold<int>(0, (sum, part) => sum + part.amount);
    final parentId = await _insert(
      txn,
      accountId: draft.accountId!,
      amount: total,
      date: draft.date,
      valueDate: draft.valueDate,
      catId: splitCategoryId,
      payeeId: draft.payeeId,
      methodId: draft.methodId,
      comment: draft.comment,
      number: draft.number,
      crStatus: draft.crStatus,
    );
    for (final part in draft.parts) {
      await _insert(
        txn,
        accountId: draft.accountId!,
        amount: part.amount,
        date: draft.date,
        valueDate: draft.valueDate,
        catId: part.categoryId,
        payeeId: draft.payeeId,
        methodId: draft.methodId,
        parentId: parentId,
        comment: part.comment,
        number: draft.number,
        crStatus: draft.crStatus,
        debtId: part.resolveDebtId,
        originalAmount: part.resolveDebtId == null ? null : part.debtAmount,
        originalCurrency: part.resolveDebtId == null ? null : draft.debtCurrency,
      );
    }
    return parentId;
  }

  Future<int> _insertTransfer(
    DatabaseExecutor txn,
    TransactionDraft draft,
  ) async {
    final source = draft.accountId!;
    final target = draft.targetAccountId!;
    final uuid = newUuid();
    final sourceAmount = -draft.amount.abs();
    final targetAmount = draft.targetAmount == 0
        ? draft.amount.abs()
        : draft.targetAmount.abs();
    final sourceId = await _insert(
      txn,
      accountId: source,
      amount: sourceAmount,
      date: draft.date,
      valueDate: draft.valueDate,
      catId: transferCategoryId,
      transferAccount: target,
      methodId: draft.methodId,
      comment: draft.comment,
      number: draft.number,
      crStatus: draft.crStatus,
      uuid: uuid,
    );
    await _insert(
      txn,
      accountId: target,
      amount: targetAmount,
      date: draft.date,
      valueDate: draft.valueDate,
      catId: transferCategoryId,
      transferAccount: source,
      transferPeer: sourceId,
      methodId: draft.methodId,
      comment: draft.comment,
      number: draft.number,
      crStatus: draft.crStatus,
      uuid: uuid,
    );
    return sourceId;
  }

  Future<int> _updateSimple(
    DatabaseExecutor txn,
    Transaction existing,
    TransactionDraft draft,
  ) async {
    final amount = draft.type == DraftType.income
        ? draft.amount.abs()
        : -draft.amount.abs();
    await txn.update(
      'transactions',
      {
        'amount': amount,
        'cat_id': draft.categoryId,
        'account_id': draft.accountId,
        'payee_id': draft.payeeId,
        'method_id': draft.methodId,
        'comment': draft.comment,
        'number': draft.number,
        'date': toUnixTimestamp(draft.date),
        'value_date': toUnixTimestamp(draft.valueDate),
        'cr_status': draft.crStatus,
        'debt_id': draft.crStatus == 'VOID' ? null : draft.resolveDebtId,
        'original_amount': draft.crStatus == 'VOID' || draft.resolveDebtId == null
            ? null
            : draft.debtAmount,
        'original_currency':
            draft.crStatus == 'VOID' || draft.resolveDebtId == null
            ? null
            : draft.debtCurrency,
      },
      where: '_id = ?',
      whereArgs: [existing.id],
    );
    return existing.id;
  }

  Future<int> _updateSplit(
    DatabaseExecutor txn,
    Transaction existing,
    TransactionDraft draft,
  ) async {
    final total = draft.parts.fold<int>(0, (sum, part) => sum + part.amount);
    await txn.update(
      'transactions',
      {
        'amount': total,
        'cat_id': splitCategoryId,
        'account_id': draft.accountId,
        'payee_id': draft.payeeId,
        'method_id': draft.methodId,
        'comment': draft.comment,
        'number': draft.number,
        'date': toUnixTimestamp(draft.date),
        'value_date': toUnixTimestamp(draft.valueDate),
        'cr_status': draft.crStatus,
        'debt_id': null,
        'original_amount': null,
        'original_currency': null,
      },
      where: '_id = ?',
      whereArgs: [existing.id],
    );
    await txn.delete(
      'transactions',
      where: 'parent_id = ?',
      whereArgs: [existing.id],
    );
    for (final part in draft.parts) {
      await _insert(
        txn,
        accountId: draft.accountId!,
        amount: part.amount,
        date: draft.date,
        valueDate: draft.valueDate,
        catId: part.categoryId,
        payeeId: draft.payeeId,
        methodId: draft.methodId,
        parentId: existing.id,
        comment: part.comment,
        number: draft.number,
        crStatus: draft.crStatus,
        debtId: part.resolveDebtId,
        originalAmount: part.resolveDebtId == null ? null : part.debtAmount,
        originalCurrency: part.resolveDebtId == null ? null : draft.debtCurrency,
      );
    }
    return existing.id;
  }

  Future<int> _updateTransfer(
    DatabaseExecutor txn,
    Transaction existing,
    TransactionDraft draft,
  ) async {
    final peer = existing.transferPeer;
    final sourceIsExisting = existing.amount <= 0;
    final sourceId = sourceIsExisting ? existing.id : peer;
    final targetId = sourceIsExisting ? peer : existing.id;
    if (sourceId == null || targetId == null) {
      return _insertDraft(txn, draft);
    }
    final source = draft.accountId!;
    final target = draft.targetAccountId!;
    final targetAmount = draft.targetAmount == 0
        ? draft.amount.abs()
        : draft.targetAmount.abs();
    await txn.update(
      'transactions',
      {
        'amount': -draft.amount.abs(),
        'cat_id': transferCategoryId,
        'account_id': source,
        'transfer_account': target,
        'method_id': draft.methodId,
        'comment': draft.comment,
        'number': draft.number,
        'date': toUnixTimestamp(draft.date),
        'value_date': toUnixTimestamp(draft.valueDate),
        'cr_status': draft.crStatus,
      },
      where: '_id = ?',
      whereArgs: [sourceId],
    );
    await txn.update(
      'transactions',
      {
        'amount': targetAmount,
        'cat_id': transferCategoryId,
        'account_id': target,
        'transfer_account': source,
        'method_id': draft.methodId,
        'comment': draft.comment,
        'number': draft.number,
        'date': toUnixTimestamp(draft.date),
        'value_date': toUnixTimestamp(draft.valueDate),
        'cr_status': draft.crStatus,
      },
      where: '_id = ?',
      whereArgs: [targetId],
    );
    return sourceId;
  }

  Future<int> remapTransactions(
    Iterable<int> ids, {
    int? accountId,
    int? categoryId,
    bool clearCategory = false,
    int? payeeId,
    bool clearPayee = false,
    DateTime? date,
    String? crStatus,
    String? comment,
    bool clearComment = false,
    int? amount,
  }) async {
    var updated = 0;
    await db.transaction((txn) async {
      for (final id in ids.toSet()) {
        final rows = await txn.query(
          'transactions',
          where: '_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final row = rows.first;
        final isTransfer = asInt(row['transfer_peer']) != null;
        final catId = asInt(row['cat_id']);
        final isSplit = catId == splitCategoryId;
        final existingDate = DateTime.fromMillisecondsSinceEpoch(
          asIntOr(row['date'], 0) * 1000,
        );
        final currentAmount = asIntOr(row['amount'], 0);
        final values = <String, Object?>{};
        if (accountId != null && !isTransfer) {
          values['account_id'] = accountId;
        }
        if (!isTransfer && !isSplit) {
          if (categoryId != null) values['cat_id'] = categoryId;
          if (clearCategory) values['cat_id'] = null;
        }
        if (payeeId != null) values['payee_id'] = payeeId;
        if (clearPayee) values['payee_id'] = null;
        if (date != null) {
          final valueDate = DateTime(
            date.year,
            date.month,
            date.day,
            existingDate.hour,
            existingDate.minute,
            existingDate.second,
          );
          values['date'] = toUnixTimestamp(valueDate);
          values['value_date'] = toUnixTimestamp(valueDate);
        }
        if (crStatus != null) values['cr_status'] = crStatus;
        if (comment != null) values['comment'] = comment;
        if (clearComment) values['comment'] = '';
        if (amount != null && !isTransfer && !isSplit) {
          final abs = amount.abs();
          values['amount'] = currentAmount < 0 ? -abs : abs;
        }
        if (values.isEmpty) continue;
        await txn.update(
          'transactions',
          values,
          where: '_id = ?',
          whereArgs: [id],
        );
        updated++;
        if (isSplit) {
          final childValues = <String, Object?>{};
          if (accountId != null) childValues['account_id'] = accountId;
          if (payeeId != null) childValues['payee_id'] = payeeId;
          if (clearPayee) childValues['payee_id'] = null;
          if (date != null) {
            childValues['date'] = values['date'];
            childValues['value_date'] = values['value_date'];
          }
          if (crStatus != null) childValues['cr_status'] = crStatus;
          if (comment != null) childValues['comment'] = comment;
          if (clearComment) childValues['comment'] = '';
          if (childValues.isNotEmpty) {
            await txn.update(
              'transactions',
              childValues,
              where: 'parent_id = ?',
              whereArgs: [id],
            );
          }
        } else if (isTransfer) {
          final peer = asInt(row['transfer_peer']);
          if (peer != null) {
            final peerRows = await txn.query(
              'transactions',
              where: '_id = ?',
              whereArgs: [peer],
              limit: 1,
            );
            if (peerRows.isNotEmpty) {
              final peerRow = peerRows.first;
              final peerValues = <String, Object?>{};
              if (payeeId != null) peerValues['payee_id'] = payeeId;
              if (clearPayee) peerValues['payee_id'] = null;
              if (date != null) {
                peerValues['date'] = values['date'];
                peerValues['value_date'] = values['value_date'];
              }
              if (crStatus != null) peerValues['cr_status'] = crStatus;
              if (comment != null) peerValues['comment'] = comment;
              if (clearComment) peerValues['comment'] = '';
              if (amount != null) {
                final peerAmount = asIntOr(peerRow['amount'], 0);
                final abs = amount.abs();
                peerValues['amount'] = peerAmount < 0 ? -abs : abs;
              }
              if (peerValues.isNotEmpty) {
                await txn.update(
                  'transactions',
                  peerValues,
                  where: '_id = ?',
                  whereArgs: [peer],
                );
                updated++;
              }
            }
          }
        }
      }
    });
    return updated;
  }

  Future<Transaction?> _transactionWithTxn(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'transactions',
      where: '_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final map = rows.first;
    return Transaction.fromMap({
      ...map,
      'date': map['date'],
      'value_date': map['value_date'],
    });
  }

  Future<void> deleteTransaction(int id) async {
    await db.transaction((txn) async {
      await _deleteWithTxn(txn, id);
    });
  }

  Future<void> _deleteWithTxn(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'transactions',
      where: '_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final map = rows.first;
    final peer = asInt(map['transfer_peer']);
    final ids = <int>[id];
    if (peer != null) ids.add(peer);
    final childRows = await txn.query(
      'transactions',
      columns: ['_id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    ids.addAll(childRows.map((row) => asIntOr(row['_id'], 0)));
    for (final transactionId in ids) {
      await _removeCreatedDebt(txn, transactionId);
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    final attachmentRows = await txn.rawQuery('''
      SELECT a._id, a.uri FROM attachments a
      JOIN transaction_attachments ta ON ta.attachment_id = a._id
      WHERE ta.transaction_id IN ($placeholders)
    ''', ids);
    for (final attachment in attachmentRows) {
      final uri = asStringOr(attachment['uri']);
      final file = File(uri);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await txn.delete(
        'attachments',
        where: '_id = ?',
        whereArgs: [asInt(attachment['_id'])],
      );
    }
    for (final transactionId in ids) {
      await txn.delete(
        'transactions',
        where: '_id = ?',
        whereArgs: [transactionId],
      );
    }
  }

  // ------------------------------------------------------------ attachments

  Future<List<Attachment>> attachmentsForTransaction(int transactionId) async {
    final rows = await db.rawQuery(
      '''
      SELECT a._id, a.uri FROM attachments a
      JOIN transaction_attachments ta ON ta.attachment_id = a._id
      WHERE ta.transaction_id = ?
      ORDER BY a._id
    ''',
      [transactionId],
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<Attachment> addAttachment(int transactionId, File source) async {
    await database.picturesDir.create(recursive: true);
    var name = p.basename(source.path);
    var target = File(p.join(database.picturesDir.path, name));
    var counter = 1;
    while (await target.exists()) {
      final extension = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      target = File(
        p.join(database.picturesDir.path, '${base}_${counter++}$extension'),
      );
    }
    await source.copy(target.path);
    final attachmentId = await db.insert('attachments', {
      'uri': target.path,
      'uuid': newUuid(),
    });
    await db.insert('transaction_attachments', {
      'transaction_id': transactionId,
      'attachment_id': attachmentId,
    });
    return Attachment(id: attachmentId, uri: target.path);
  }

  Future<void> removeAttachment(int attachmentId) async {
    final rows = await db.query(
      'attachments',
      columns: ['uri'],
      where: '_id = ?',
      whereArgs: [attachmentId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final file = File(asStringOr(rows.first['uri']));
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await db.delete(
      'transaction_attachments',
      where: 'attachment_id = ?',
      whereArgs: [attachmentId],
    );
    await db.delete('attachments', where: '_id = ?', whereArgs: [attachmentId]);
  }

  Future<List<Map<String, Object?>>> allAttachments() =>
      db.rawQuery('SELECT _id, uri FROM attachments ORDER BY _id');

  Future<void> updateAttachmentUri(int id, String uri) async {
    await db.update(
      'attachments',
      {'uri': uri},
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------------ stats

  Future<List<int>> _statsAccountIds(int? accountId) async {
    if (accountId != null) return [accountId];
    final rows = await db.rawQuery(
      'SELECT _id FROM accounts WHERE exclude_from_totals = 0',
    );
    return rows.map((row) => asIntOr(row['_id'], 0)).toList();
  }

  Future<StatsData> stats({
    int? accountId,
    DateTime? month,
    DateTime? rangeFrom,
    DateTime? rangeTo,
    required String homeCurrency,
  }) async {
    final accountIds = await _statsAccountIds(accountId);
    final selectedAccount = accountId == null ? null : await account(accountId);
    final displayCurrency = selectedAccount?.currency ?? homeCurrency;
    if (accountIds.isEmpty) {
      return StatsData(
        income: 0,
        expense: 0,
        monthly: const [],
        byCategoryExpense: const [],
        byCategoryIncome: const [],
        currency: displayCurrency,
      );
    }
    final rates = accountId == null
        ? await exchangeRatesTo(homeCurrency)
        : <String, double>{displayCurrency: 1.0};
    final rateExpression = accountId != null
        ? '1.0'
        : 'CASE a.currency ${rates.entries.map((entry) => "WHEN '${entry.key.replaceAll("'", "''")}' THEN ${entry.value}").join(' ')} ELSE 1.0 END';
    final baseMonth = month ?? DateTime.now();
    final rangeStart =
        rangeFrom ?? DateTime(baseMonth.year, baseMonth.month, 1);
    final rangeEnd = rangeTo != null
        ? DateTime(rangeTo.year, rangeTo.month, rangeTo.day + 1)
        : DateTime(baseMonth.year, baseMonth.month + 1, 1);
    final placeholders = List.filled(accountIds.length, '?').join(',');
    final rangeArgs = <Object?>[
      ...accountIds,
      toUnixTimestamp(rangeStart),
      toUnixTimestamp(rangeEnd),
    ];
    final currentRows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN t.amount > 0
          THEN CAST(ROUND(t.amount * $rateExpression) AS INTEGER) ELSE 0 END) AS income,
        SUM(CASE WHEN t.amount < 0
          THEN CAST(ROUND(t.amount * $rateExpression) AS INTEGER) ELSE 0 END) AS expense
      FROM transactions t
      JOIN accounts a ON a._id = t.account_id
      WHERE t.account_id IN ($placeholders)
        AND t.date >= ? AND t.date < ?
        AND t.status != $statusVoid AND t.status != $statusArchived
        AND t.cr_status != 'VOID'
        AND (t.cat_id IS NULL OR t.cat_id NOT IN ($splitCategoryId, $transferCategoryId))
    ''', rangeArgs);
    final current = currentRows.isEmpty ? const {} : currentRows.first;

    Future<List<CategoryTotal>> categoryBreakdown(bool income) async {
      final categoryAmount = income ? 't.amount' : '-t.amount';
      final categoryRows = await db.rawQuery('''
        SELECT COALESCE(c.parent_id, c._id, 0) AS group_id,
               COALESCE(pc.label, c.label, 'Uncategorized') AS label,
               COALESCE(pc.icon, c.icon) AS icon,
               COALESCE(pc.color, c.color) AS color,
               SUM(CAST(ROUND($categoryAmount * $rateExpression) AS INTEGER)) AS amount
        FROM transactions t
        JOIN accounts a ON a._id = t.account_id
        LEFT JOIN categories c ON c._id = t.cat_id
        LEFT JOIN categories pc ON pc._id = c.parent_id
        WHERE t.account_id IN ($placeholders)
          AND t.date >= ? AND t.date < ?
          AND t.status != $statusVoid AND t.status != $statusArchived
          AND t.cr_status != 'VOID'
          AND t.amount ${income ? '>' : '<'} 0
          AND (t.cat_id IS NULL OR t.cat_id NOT IN ($splitCategoryId, $transferCategoryId))
        GROUP BY group_id
        HAVING SUM($categoryAmount * $rateExpression) > 0
        ORDER BY SUM($categoryAmount * $rateExpression) DESC
      ''', rangeArgs);
      return categoryRows
          .map(
            (row) => CategoryTotal(
              categoryId: asIntOr(row['group_id'], 0),
              label: asStringOr(row['label'], 'Uncategorized'),
              icon: asString(row['icon']),
              color: asInt(row['color']),
              amount: asIntOr(row['amount'], 0),
            ),
          )
          .toList();
    }

    final expenseByCategory = await categoryBreakdown(false);
    final incomeByCategory = await categoryBreakdown(true);

    return StatsData(
      income: asIntOr(current['income'], 0),
      expense: asIntOr(current['expense'], 0),
      monthly: const [],
      byCategoryExpense: expenseByCategory,
      byCategoryIncome: incomeByCategory,
      currency: displayCurrency,
    );
  }

  Future<PeriodTotals> periodTotals({
    int? accountId,
    DateTime? from,
    DateTime? to,
    required String homeCurrency,
  }) async {
    final accountIds = await _statsAccountIds(accountId);
    final selectedAccount = accountId == null ? null : await account(accountId);
    final displayCurrency = selectedAccount?.currency ?? homeCurrency;
    if (accountIds.isEmpty) {
      return PeriodTotals(income: 0, expense: 0, currency: displayCurrency);
    }
    final rates = accountId == null
        ? await exchangeRatesTo(homeCurrency)
        : <String, double>{displayCurrency: 1.0};
    final rateExpression = accountId != null
        ? '1.0'
        : 'CASE a.currency ${rates.entries.map((entry) => "WHEN '${entry.key.replaceAll("'", "''")}' THEN ${entry.value}").join(' ')} ELSE 1.0 END';
    final args = <Object?>[...accountIds];
    final conditions = <String>[
      't.account_id IN (${List.filled(accountIds.length, '?').join(',')})',
      't.status != $statusVoid',
      't.status != $statusArchived',
      "t.cr_status != 'VOID'",
      '(t.cat_id IS NULL OR t.cat_id NOT IN ($splitCategoryId, $transferCategoryId))',
    ];
    if (from != null) {
      conditions.add('t.date >= ?');
      args.add(toUnixTimestamp(from));
    }
    if (to != null) {
      conditions.add('t.date <= ?');
      args.add(toUnixTimestamp(to));
    }
    final rows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN t.amount > 0
          THEN CAST(ROUND(t.amount * $rateExpression) AS INTEGER) ELSE 0 END) AS income,
        SUM(CASE WHEN t.amount < 0
          THEN CAST(ROUND(t.amount * $rateExpression) AS INTEGER) ELSE 0 END) AS expense
      FROM transactions t
      JOIN accounts a ON a._id = t.account_id
      WHERE ${conditions.join(' AND ')}
    ''', args);
    final row = rows.isEmpty ? const {} : rows.first;
    return PeriodTotals(
      income: asIntOr(row['income'], 0),
      expense: asIntOr(row['expense'], 0),
      currency: displayCurrency,
    );
  }

  Future<CategoryTotal?> topCategorySpending({
    int? accountId,
    DateTime? from,
    DateTime? to,
    required String homeCurrency,
  }) async {
    final accountIds = await _statsAccountIds(accountId);
    if (accountIds.isEmpty) return null;
    final selectedAccount = accountId == null ? null : await account(accountId);
    final displayCurrency = selectedAccount?.currency ?? homeCurrency;
    final rates = accountId == null
        ? await exchangeRatesTo(homeCurrency)
        : <String, double>{displayCurrency: 1.0};
    final rateExpression = accountId != null
        ? '1.0'
        : 'CASE a.currency ${rates.entries.map((entry) => "WHEN '${entry.key.replaceAll("'", "''")}' THEN ${entry.value}").join(' ')} ELSE 1.0 END';
    final args = <Object?>[...accountIds];
    final conditions = <String>[
      't.account_id IN (${List.filled(accountIds.length, '?').join(',')})',
      't.status != $statusVoid',
      't.status != $statusArchived',
      "t.cr_status != 'VOID'",
      't.amount < 0',
      '(t.cat_id IS NULL OR t.cat_id NOT IN ($splitCategoryId, $transferCategoryId))',
    ];
    if (from != null) {
      conditions.add('t.date >= ?');
      args.add(toUnixTimestamp(from));
    }
    if (to != null) {
      conditions.add('t.date <= ?');
      args.add(toUnixTimestamp(to));
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(c.parent_id, c._id, 0) AS group_id,
             COALESCE(pc.label, c.label, 'Uncategorized') AS label,
             COALESCE(pc.icon, c.icon) AS icon,
             COALESCE(pc.color, c.color) AS color,
             SUM(CAST(ROUND(-t.amount * $rateExpression) AS INTEGER)) AS amount
      FROM transactions t
      JOIN accounts a ON a._id = t.account_id
      LEFT JOIN categories c ON c._id = t.cat_id
      LEFT JOIN categories pc ON pc._id = c.parent_id
      WHERE ${conditions.join(' AND ')}
      GROUP BY group_id
      HAVING SUM(-t.amount * $rateExpression) > 0
      ORDER BY SUM(-t.amount * $rateExpression) DESC
      LIMIT 1
    ''', args);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CategoryTotal(
      categoryId: asIntOr(row['group_id'], 0),
      label: asStringOr(row['label'], 'Uncategorized'),
      icon: asString(row['icon']),
      color: asInt(row['color']),
      amount: asIntOr(row['amount'], 0),
    );
  }

  // ---------------------------------------------------------------- budgets

  Future<List<Budget>> budgets() async {
    final now = DateTime.now();
    final rows = await db.rawQuery(
      '''
      SELECT b.*, COALESCE((
        SELECT SUM(ba.budget) FROM budget_allocations ba
        WHERE ba.budget_id = b._id AND ba.year = ? AND ba.second = ?
      ), 0) AS total_budget
      FROM budgets b ORDER BY b.title COLLATE NOCASE
    ''',
      [now.year, now.month - 1],
    );
    return rows.map(Budget.fromMap).toList();
  }

  Future<int> insertBudget({
    required String title,
    required String description,
    required int? accountId,
    required String currency,
  }) async {
    return db.insert('budgets', {
      'title': title,
      'description': description,
      'grouping': 'MONTH',
      'account_id': accountId,
      'currency': currency,
      'is_default': 0,
      'uuid': newUuid(),
    });
  }

  Future<void> deleteBudget(int id) async {
    await db.delete('budgets', where: '_id = ?', whereArgs: [id]);
  }

  Future<Map<int, int>> _spendingByCategory({
    required int? accountId,
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month + 1, 1);
    final end = DateTime(year, month + 2, 1);
    final args = <Object?>[toUnixTimestamp(start), toUnixTimestamp(end)];
    var accountClause = '';
    if (accountId != null) {
      accountClause = 'AND t.account_id = ?';
      args.add(accountId);
    }
    final rows = await db.rawQuery('''
      SELECT t.cat_id, SUM(-t.amount) AS amount
      FROM transactions t
      WHERE t.date >= ? AND t.date < ?
        AND t.status != $statusVoid AND t.status != $statusArchived
        AND t.cr_status != 'VOID'
        AND t.amount < 0
        AND t.cat_id IS NOT NULL
        AND t.cat_id NOT IN ($splitCategoryId, $transferCategoryId)
        $accountClause
      GROUP BY t.cat_id
    ''', args);
    return {
      for (final row in rows)
        if (asInt(row['cat_id']) != null)
          asInt(row['cat_id'])!: asIntOr(row['amount'], 0),
    };
  }

  Future<Map<int, int?>> categoryParents() async {
    final rows = await db.rawQuery('SELECT _id, parent_id FROM categories');
    return {
      for (final row in rows) asIntOr(row['_id'], 0): asInt(row['parent_id']),
    };
  }

  bool _isDescendant(int categoryId, int ancestorId, Map<int, int?> parents) {
    var current = categoryId;
    var guard = 0;
    while (guard++ < 20) {
      if (current == ancestorId) return true;
      final parent = parents[current];
      if (parent == null || parent == current) return false;
      current = parent;
    }
    return false;
  }

  Future<List<BudgetAllocation>> budgetAllocations({
    required int budgetId,
    required int year,
    required int month,
  }) async {
    final budget = (await budgets()).firstWhere((b) => b.id == budgetId);
    final rows = await db.rawQuery(
      '''
      SELECT ba.*, c.label AS category_label, c.icon AS category_icon,
             c.color AS category_color
      FROM budget_allocations ba
      LEFT JOIN categories c ON c._id = ba.cat_id
      WHERE ba.budget_id = ? AND ba.year = ? AND ba.second = ?
      ORDER BY c.label COLLATE NOCASE
    ''',
      [budgetId, year, month - 1],
    );
    final spending = await _spendingByCategory(
      accountId: budget.accountId,
      year: year,
      month: month - 1,
    );
    final parents = await categoryParents();
    return rows.map((row) {
      final catId = asIntOr(row['cat_id'], 0);
      final spent = spending.entries
          .where((entry) => _isDescendant(entry.key, catId, parents))
          .fold<int>(0, (sum, entry) => sum + entry.value);
      return BudgetAllocation(
        budgetId: budgetId,
        categoryId: catId,
        budget: asIntOr(row['budget'], 0),
        rollOverPrevious: asIntOr(row['rollOverPrevious'], 0),
        rollOverNext: asIntOr(row['rollOverNext'], 0),
        oneTime: asBool(row['oneTime']),
        spent: spent,
        categoryLabel: asStringOr(row['category_label'], 'Category'),
        categoryIcon: asString(row['category_icon']),
        categoryColor: asInt(row['category_color']),
      );
    }).toList();
  }

  Future<void> saveBudgetAllocation({
    required int budgetId,
    required int categoryId,
    required int year,
    required int month,
    required int budget,
  }) async {
    await db.transaction((txn) async {
      final updated = await txn.update(
        'budget_allocations',
        {'budget': budget},
        where: 'budget_id = ? AND cat_id = ? AND year = ? AND second = ?',
        whereArgs: [budgetId, categoryId, year, month - 1],
      );
      if (updated == 0) {
        await txn.insert('budget_allocations', {
          'budget_id': budgetId,
          'cat_id': categoryId,
          'year': year,
          'second': month - 1,
          'budget': budget,
          'rollOverPrevious': 0,
          'rollOverNext': 0,
          'oneTime': 0,
        });
      }
    });
  }

  Future<void> deleteBudgetAllocation(
    int budgetId,
    int categoryId, {
    required int year,
    required int month,
  }) async {
    await db.delete(
      'budget_allocations',
      where: 'budget_id = ? AND cat_id = ? AND year = ? AND second = ?',
      whereArgs: [budgetId, categoryId, year, month - 1],
    );
  }

  // -------------------------------------------------------------- templates

  Future<List<Template>> templates() async {
    final rows = await db.rawQuery('''
      SELECT t.*, c.label AS cat_label, c.icon AS cat_icon,
             c.color AS cat_color, c.label AS cat_path,
             a.label AS account_label, a.currency AS currency,
             p.name AS payee_name
      FROM templates t
      LEFT JOIN categories c ON c._id = t.cat_id
      LEFT JOIN accounts a ON a._id = t.account_id
      LEFT JOIN payee p ON p._id = t.payee_id
      WHERE t.status != 2
      ORDER BY t.title COLLATE NOCASE
    ''');
    return rows.map(Template.fromMap).toList();
  }

  Future<Template?> template(int id) async {
    final list = await templates();
    for (final template in list) {
      if (template.id == id) return template;
    }
    return null;
  }

  Future<int> insertTemplate({
    required String title,
    required String comment,
    required int amount,
    required int? categoryId,
    required int accountId,
    int? payeeId,
    int? methodId,
    int? transferAccount,
  }) async {
    return db.insert('templates', {
      'title': title,
      'comment': comment,
      'amount': amount,
      'cat_id': categoryId,
      'account_id': accountId,
      'payee_id': payeeId,
      'method_id': methodId,
      'transfer_account': transferAccount,
      'usages': 0,
      'plan_execution': 0,
      'uuid': newUuid(),
      'status': 0,
      'plan_execution_advance': 0,
      'default_action': 'SAVE',
    });
  }

  Future<void> updateTemplate(
    int id, {
    required String title,
    required String comment,
    required int amount,
    required int? categoryId,
    required int accountId,
    int? payeeId,
    int? methodId,
    int? transferAccount,
  }) async {
    await db.update(
      'templates',
      {
        'title': title,
        'comment': comment,
        'amount': amount,
        'cat_id': categoryId,
        'account_id': accountId,
        'payee_id': payeeId,
        'method_id': methodId,
        'transfer_account': transferAccount,
      },
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTemplate(int id) async {
    await db.delete('templates', where: '_id = ?', whereArgs: [id]);
  }

  Future<int> applyTemplate(Template template) async {
    final draft = TransactionDraft(
      type: template.transferAccount == null
          ? (template.amount >= 0 ? DraftType.income : DraftType.expense)
          : DraftType.transfer,
      amount: template.amount.abs(),
      accountId: template.accountId,
      targetAccountId: template.transferAccount,
      targetAmount: template.amount.abs(),
      categoryId: template.catId,
      payeeId: template.payeeId,
      methodId: template.methodId,
      comment: template.comment.isEmpty ? template.title : template.comment,
    );
    final id = await saveTransaction(draft);
    await db.rawUpdate(
      'UPDATE templates SET usages = usages + 1, last_used = ? WHERE _id = ?',
      [toUnixTimestamp(DateTime.now()), template.id],
    );
    return id;
  }
}
