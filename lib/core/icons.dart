import 'package:flutter/material.dart';

import 'material_icons.dart';

const Map<String, IconData> _fontAwesomeIcons = {
  'bowl-food': Icons.restaurant,
  'utensils': Icons.restaurant,
  'cart-shopping': Icons.shopping_cart,
  'mug-hot': Icons.coffee,
  'car': Icons.directions_car,
  'gas-pump': Icons.local_gas_station,
  'bus': Icons.directions_bus,
  'train': Icons.train,
  'taxi': Icons.local_taxi,
  'plane': Icons.flight,
  'plane-departure': Icons.flight_takeoff,
  'house': Icons.home,
  'city': Icons.location_city,
  'file-invoice-dollar': Icons.receipt_long,
  'screwdriver-wrench': Icons.build,
  'bag-shopping': Icons.shopping_bag,
  'shirt': Icons.checkroom,
  'laptop': Icons.laptop,
  'computer': Icons.computer,
  'gift': Icons.card_giftcard,
  'heart-pulse': Icons.favorite,
  'heart': Icons.favorite,
  'pills': Icons.medication,
  'user-doctor': Icons.medical_services,
  'dumbbell': Icons.fitness_center,
  'film': Icons.movie,
  'masks-theater': Icons.theater_comedy,
  'palette': Icons.palette,
  'school': Icons.school,
  'shield-halved': Icons.shield,
  'ellipsis': Icons.more_horiz,
  'money-bill-wave': Icons.payments,
  'money-bill': Icons.money,
  'money-bill-transfer': Icons.currency_exchange,
  'briefcase': Icons.work,
  'rotate-left': Icons.replay,
  'circle-plus': Icons.add_circle,
  'circle-arrow-down': Icons.arrow_circle_down,
  'circle-arrow-up': Icons.arrow_circle_up,
  'circle-arrow-left': Icons.arrow_circle_left,
  'hand-holding-dollar': Icons.attach_money,
  'hands-holding-circle': Icons.volunteer_activism,
  'credit-card': Icons.credit_card,
  'money-check': Icons.receipt,
  'down-long': Icons.south,
  'up-long': Icons.north,
  'box-archive': Icons.archive,
  'star': Icons.star,
  'soap': Icons.soap,
  'spray-can': Icons.spa,
  'scissors': Icons.content_cut,
  'water': Icons.water,
  'anchor': Icons.anchor,
  'passport': Icons.badge,
  'envelope': Icons.mail,
  'hotdog': Icons.fastfood,
  'bread-slice': Icons.bakery_dining,
  'spoon': Icons.restaurant,
  'phone': Icons.phone_android,
  'door-open': Icons.meeting_room,
  'hammer': Icons.handyman,
  'hornbill': Icons.notifications,
  'wine-glass': Icons.wine_bar,
  'glass-water': Icons.local_drink,
  'person-biking': Icons.directions_bike,
  'truck-medical': Icons.local_hospital,
  'shop': Icons.store,
  'store': Icons.store,
  'lease': Icons.car_rental,
  'calendar': Icons.calendar_month,
  'tag': Icons.sell,
  'wallet': Icons.account_balance_wallet,
};

IconData iconForCategory(String? name) {
  if (name == null) return Icons.category_outlined;
  return materialIcons[name] ??
      _fontAwesomeIcons[name] ??
      Icons.category_outlined;
}

final List<MapEntry<String, IconData>> allCategoryIcons = [
  ...materialIcons.entries,
  ..._fontAwesomeIcons.entries.where(
    (entry) => !materialIcons.containsKey(entry.key),
  ),
];

String iconSearchLabel(String key) =>
    categoryIconChoices[key] ?? materialIconDisplayName(key);

IconData iconForAccountType(int type) {
  switch (type) {
    case 1:
      return Icons.payments_outlined;
    case 2:
      return Icons.account_balance_outlined;
    case 3:
      return Icons.credit_card;
    case 4:
      return Icons.savings_outlined;
    case 5:
      return Icons.request_quote_outlined;
    case 6:
      return Icons.show_chart;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

const Map<String, String> categoryIconChoices = {
  'bowl-food': 'Food',
  'cart-shopping': 'Groceries',
  'utensils': 'Restaurant',
  'mug-hot': 'Coffee',
  'car': 'Car',
  'gas-pump': 'Fuel',
  'bus': 'Bus',
  'train': 'Train',
  'taxi': 'Taxi',
  'plane': 'Plane',
  'house': 'Home',
  'city': 'Rent',
  'file-invoice-dollar': 'Bills',
  'screwdriver-wrench': 'Repair',
  'bag-shopping': 'Shopping',
  'shirt': 'Clothes',
  'laptop': 'Electronics',
  'gift': 'Gift',
  'heart-pulse': 'Health',
  'pills': 'Pharmacy',
  'user-doctor': 'Doctor',
  'dumbbell': 'Sport',
  'film': 'Entertainment',
  'masks-theater': 'Theater',
  'palette': 'Hobby',
  'school': 'Education',
  'shield-halved': 'Insurance',
  'money-bill-wave': 'Salary',
  'briefcase': 'Business',
  'rotate-left': 'Refund',
  'ellipsis': 'Other',
  'star': 'Favourite',
  'tag': 'Tag',
  'calendar': 'Calendar',
  'wallet': 'Wallet',
};

const List<int> categoryColorChoices = [
  0xFFEF5350,
  0xFFEC407A,
  0xFFAB47BC,
  0xFF7E57C2,
  0xFF5C6BC0,
  0xFF42A5F5,
  0xFF29B6F6,
  0xFF26C6DA,
  0xFF26A69A,
  0xFF66BB6A,
  0xFF9CCC65,
  0xFFD4E157,
  0xFFFFCA28,
  0xFFFFA726,
  0xFFFF7043,
  0xFF8D6E63,
  0xFF78909C,
  0xFF90A4AE,
  0xFF546E7A,
  0xFF455A64,
];

Color colorFromDb(int? value) {
  if (value == null) return const Color(0xFF90A4AE);
  return Color(value & 0xFFFFFFFF);
}
