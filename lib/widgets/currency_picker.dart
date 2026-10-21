import 'package:flutter/material.dart';

import '../models/models.dart';

Future<String?> showCurrencyPicker(
  BuildContext context,
  List<CurrencyInfo> currencies, {
  String? selected,
}) {
  var query = '';
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final filtered = currencies
            .where((currency) =>
                currency.code.toLowerCase().contains(query.toLowerCase()) ||
                (currency.label ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()))
            .toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search currency',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final currency = filtered[index];
                    return ListTile(
                      selected: currency.code == selected,
                      title: Text(currency.code),
                      subtitle: currency.label == null ||
                              currency.label!.isEmpty
                          ? null
                          : Text(currency.label!),
                      trailing: currency.code == selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(currency.code),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
