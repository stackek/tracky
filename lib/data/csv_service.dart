import 'dart:io';

import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../core/currency.dart';
import '../core/dates.dart';
import '../models/models.dart';
import 'repository.dart';
import 'transaction_repository.dart';

class CsvImportResult {
  const CsvImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

class CsvService {
  CsvService(this.repository);

  final Repository repository;

  Future<File> export(File target) async {
    final transactions = await repository.transactions(
      const TransactionFilter(
        period: TransactionPeriod.all,
        voidFilter: TransactionVoidFilter.nonVoid,
      ),
      includeArchived: true,
    );
    final rows = <List<Object?>>[
      [
        'Date',
        'Time',
        'Amount',
        'Currency',
        'Category',
        'Payee',
        'Account',
        'Comment',
        'Tags',
        'Status',
        'Transfer account',
      ],
    ];
    for (final transaction in transactions) {
      rows.add([
        formatShortDate(transaction.date),
        formatTime(transaction.date),
        formatMoneyPlain(transaction.amount, transaction.currency),
        transaction.currency,
        transaction.categoryPath ?? '',
        transaction.payeeName ?? '',
        transaction.accountLabel ?? '',
        transaction.comment,
        transaction.tagIds.join(' '),
        transaction.crStatus,
        transaction.transferAccountLabel ?? '',
      ]);
    }
    final csv = Csv(lineDelimiter: '\n').encode(rows);
    await target.writeAsString(csv, flush: true);
    return target;
  }

  Future<CsvImportResult> import(
    File file, {
    required int defaultAccountId,
  }) async {
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const CsvImportResult(imported: 0, skipped: 0);
    }
    final rows = Csv().decode(content);
    if (rows.isEmpty) return const CsvImportResult(imported: 0, skipped: 0);
    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    int indexOf(List<String> aliases, [int fallback = -1]) {
      for (final alias in aliases) {
        final index = header.indexOf(alias);
        if (index >= 0) return index;
      }
      return fallback;
    }

    final dateIndex = indexOf(['date', 'datum', 'дата']);
    final timeIndex = indexOf(['time', 'uhrzeit', 'час']);
    final amountIndex = indexOf(['amount', 'betrag', 'сума', 'value']);
    final currencyIndex = indexOf(['currency', 'währung', 'валюта']);
    final categoryIndex = indexOf(['category', 'kategorie', 'категорія']);
    final payeeIndex = indexOf(['payee', 'payee name', 'empfänger']);
    final accountIndex = indexOf(['account', 'konto', 'рахунок']);
    final commentIndex = indexOf(['comment', 'note', 'notiz', 'коментар']);
    final tagsIndex = indexOf(['tags', 'tag', 'теги']);
    final statusIndex = indexOf(['status', 'cr status']);
    if (amountIndex < 0 || dateIndex < 0) {
      throw const FormatException(
        'The CSV file needs at least a Date and an Amount column.',
      );
    }

    final accounts = await repository.accounts();
    final categories = await repository.categories();
    final payees = await repository.payees();
    final tags = await repository.tags();

    var imported = 0;
    var skipped = 0;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String cell(int index) =>
          index < 0 || index >= row.length ? '' : row[index].toString().trim();
      try {
        final date = _parseDate(cell(dateIndex), cell(timeIndex));
        if (date == null) {
          skipped++;
          continue;
        }
        final amountText = cell(amountIndex);
        final amount = parseAmountToMinor(amountText, 'EUR');
        if (amount == null || amount == 0) {
          skipped++;
          continue;
        }
        final account =
            accounts
                .where(
                  (item) =>
                      item.label.toLowerCase() ==
                      cell(accountIndex).toLowerCase(),
                )
                .firstOrNull ??
            accounts.where((item) => item.id == defaultAccountId).firstOrNull ??
            accounts.firstOrNull;
        if (account == null) {
          skipped++;
          continue;
        }
        final currency = cell(currencyIndex).isEmpty
            ? account.currency
            : cell(currencyIndex);
        final normalizedAmount =
            parseAmountToMinor(amountText, currency) ?? amount;
        final isIncome = normalizedAmount > 0;

        Category? category;
        final categoryText = cell(categoryIndex);
        if (categoryText.isNotEmpty) {
          final leaf = categoryText.split('>').last.trim().toLowerCase();
          category = categories
              .where(
                (item) =>
                    item.label.toLowerCase() == leaf &&
                    item.type == (isIncome ? 2 : 1),
              )
              .firstOrNull;
          if (category == null) {
            final id = await repository.insertCategory(
              label: leaf,
              type: isIncome ? 2 : 1,
              color: isIncome ? 0xFF66BB6A : 0xFFEF5350,
              icon: isIncome ? 'money-bill-wave' : 'ellipsis',
            );
            category = Category(
              id: id,
              label: leaf,
              parentId: null,
              type: isIncome ? 2 : 1,
              color: isIncome ? 0xFF66BB6A : 0xFFEF5350,
              icon: isIncome ? 'money-bill-wave' : 'ellipsis',
              uuid: null,
              usages: 0,
            );
            categories.add(category);
          }
        }

        Payee? payee;
        final payeeText = cell(payeeIndex);
        if (payeeText.isNotEmpty) {
          payee = payees
              .where(
                (item) => item.name.toLowerCase() == payeeText.toLowerCase(),
              )
              .firstOrNull;
          if (payee == null) {
            final id = await repository.insertPayee(payeeText);
            payee = Payee(id: id, name: payeeText);
            payees.add(payee);
          }
        }

        final tagIds = <int>[];
        for (final raw in cell(tagsIndex).split(RegExp(r'[,;]'))) {
          final label = raw.trim();
          if (label.isEmpty) continue;
          var tag = tags
              .where((item) => item.label.toLowerCase() == label.toLowerCase())
              .firstOrNull;
          if (tag == null) {
            final id = await repository.insertTag(label);
            tag = Tag(id: id, label: label);
            tags.add(tag);
          }
          tagIds.add(tag.id);
        }

        await repository.saveTransaction(
          TransactionDraft(
            type: isIncome ? DraftType.income : DraftType.expense,
            amount: normalizedAmount.abs(),
            accountId: account.id,
            date: date,
            valueDate: date,
            categoryId: category?.id,
            payeeId: payee?.id,
            comment: cell(commentIndex),
            crStatus: _status(cell(statusIndex)),
            tagIds: tagIds,
          ),
        );
        imported++;
      } catch (_) {
        skipped++;
      }
    }
    return CsvImportResult(imported: imported, skipped: skipped);
  }

  DateTime? _parseDate(String datePart, String timePart) {
    final text = '$datePart $timePart'.trim();
    if (text.isEmpty) return null;
    final formats = [
      'dd/MM/yyyy HH:mm',
      'd/M/yyyy H:mm',
      'dd.MM.yyyy HH:mm',
      'dd.MM.yyyy',
      'dd/MM/yyyy',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'MM/dd/yyyy',
      'd MMM yyyy',
    ];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parseStrict(text);
        if (parsed.year > 1900) return parsed;
      } catch (_) {}
    }
    try {
      final parsed = DateTime.parse(text);
      if (parsed.year > 1900) return parsed;
    } catch (_) {}
    return null;
  }

  String _status(String value) {
    switch (value.toUpperCase()) {
      case 'CLEARED':
        return 'CLEARED';
      case 'RECONCILED':
        return 'RECONCILED';
      case 'VOID':
        return 'VOID';
      default:
        return 'UNRECONCILED';
    }
  }
}
