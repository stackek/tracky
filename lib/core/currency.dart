import 'package:intl/intl.dart';

const Map<String, int> currencyFractionDigits = {
  'BIF': 0,
  'CLP': 0,
  'DJF': 0,
  'GNF': 0,
  'ISK': 0,
  'JPY': 0,
  'KMF': 0,
  'KRW': 0,
  'PYG': 0,
  'RWF': 0,
  'UGX': 0,
  'VND': 0,
  'VUV': 0,
  'XAF': 0,
  'XOF': 0,
  'XPF': 0,
  'BHD': 3,
  'IQD': 3,
  'JOD': 3,
  'KWD': 3,
  'LYD': 3,
  'OMR': 3,
  'TND': 3,
};

class MoneyFormatConfig {
  static int? customFractionDigits;
  static String decimalSeparator = '.';
  static String groupSeparator = ',';

  static int digitsFor(String currency) =>
      customFractionDigits ?? currencyFractionDigits[currency] ?? 2;
}

int fractionDigitsFor(String currency) => MoneyFormatConfig.digitsFor(currency);

String _applySeparators(String number) {
  if (MoneyFormatConfig.decimalSeparator == '.' &&
      MoneyFormatConfig.groupSeparator == ',') {
    return number;
  }
  var text = number.replaceAll(',', '\u0001').replaceAll('.', '\u0002');
  text = text.replaceAll('\u0001', MoneyFormatConfig.groupSeparator);
  text = text.replaceAll('\u0002', MoneyFormatConfig.decimalSeparator);
  return text;
}

const Map<String, String> currencySymbols = {
  'AED': 'د.إ',
  'AFN': '؋',
  'ALL': 'L',
  'AMD': '֏',
  'ANG': 'ƒ',
  'AOA': 'Kz',
  'ARS': 'AR\$',
  'AUD': 'A\$',
  'AZN': '₼',
  'BAM': 'KM',
  'BBD': 'Bds\$',
  'BDT': '৳',
  'BGN': 'лв',
  'BHD': 'ب.د',
  'BIF': 'FBu',
  'BMD': 'BD\$',
  'BND': 'B\$',
  'BOB': 'Bs',
  'BRL': 'R\$',
  'BSD': 'B\$',
  'BTN': 'Nu.',
  'BWP': 'P',
  'BYN': 'Br',
  'BZD': 'BZ\$',
  'CAD': 'CA\$',
  'CDF': 'FC',
  'CHF': 'CHF',
  'CLP': 'CLP\$',
  'CNY': '¥',
  'COP': 'COL\$',
  'CRC': '₡',
  'CUP': '\$',
  'CVE': 'Esc',
  'CZK': 'Kč',
  'DJF': 'Fdj',
  'DKK': 'kr',
  'DOP': 'RD\$',
  'DZD': 'د.ج',
  'EGP': 'E£',
  'ERN': 'Nfk',
  'ETB': 'Br',
  'EUR': '€',
  'FJD': 'FJ\$',
  'FKP': 'FK£',
  'GBP': '£',
  'GEL': '₾',
  'GHS': '₵',
  'GIP': '£',
  'GMD': 'D',
  'GNF': 'FG',
  'GTQ': 'Q',
  'GYD': 'G\$',
  'HKD': 'HK\$',
  'HNL': 'L',
  'HRK': 'kn',
  'HTG': 'G',
  'HUF': 'Ft',
  'IDR': 'Rp',
  'ILS': '₪',
  'INR': '₹',
  'IQD': 'ع.د',
  'IRR': '﷼',
  'ISK': 'kr',
  'JMD': 'J\$',
  'JOD': 'د.ا',
  'JPY': '¥',
  'KES': 'KSh',
  'KGS': 'с',
  'KHR': '៛',
  'KMF': 'CF',
  'KPW': '₩',
  'KRW': '₩',
  'KWD': 'د.ك',
  'KYD': 'CI\$',
  'KZT': '₸',
  'LAK': '₭',
  'LBP': 'ل.ل',
  'LKR': 'Rs',
  'LRD': 'L\$',
  'LSL': 'L',
  'LYD': 'ل.د',
  'MAD': 'د.م.',
  'MDL': 'L',
  'MGA': 'Ar',
  'MKD': 'ден',
  'MMK': 'K',
  'MNT': '₮',
  'MOP': 'MOP\$',
  'MRU': 'UM',
  'MUR': '₨',
  'MVR': 'Rf',
  'MWK': 'MK',
  'MXN': 'MX\$',
  'MYR': 'RM',
  'MZN': 'MT',
  'NAD': 'N\$',
  'NGN': '₦',
  'NIO': 'C\$',
  'NOK': 'kr',
  'NPR': '₨',
  'NZD': 'NZ\$',
  'OMR': 'ر.ع.',
  'PAB': 'B/.',
  'PEN': 'S/',
  'PGK': 'K',
  'PHP': '₱',
  'PKR': '₨',
  'PLN': 'zł',
  'PYG': '₲',
  'QAR': 'ر.ق',
  'RON': 'lei',
  'RSD': 'дин',
  'RUB': '₽',
  'RWF': 'FRw',
  'SAR': '﷼',
  'SBD': 'SI\$',
  'SCR': '₨',
  'SDG': 'ج.س',
  'SEK': 'kr',
  'SGD': 'S\$',
  'SHP': '£',
  'SLL': 'Le',
  'SOS': 'Sh',
  'SRD': '\$',
  'SSP': '£',
  'STN': 'Db',
  'SVC': '\$',
  'SYP': '£S',
  'SZL': 'E',
  'THB': '฿',
  'TJS': 'SM',
  'TMT': 'm',
  'TND': 'د.ت',
  'TOP': 'T\$',
  'TRY': '₺',
  'TTD': 'TT\$',
  'TWD': 'NT\$',
  'TZS': 'TSh',
  'UAH': '₴',
  'UGX': 'USh',
  'USD': '\$',
  'UYU': 'UY\$',
  'UZS': "soʻm",
  'VES': 'Bs.S',
  'VND': '₫',
  'VUV': 'VT',
  'WST': 'T',
  'XAF': 'FCFA',
  'XCD': 'EC\$',
  'XOF': 'CFA',
  'XPF': '₣',
  'YER': '﷼',
  'ZAR': 'R',
  'ZMW': 'ZK',
  'ZWL': 'Z\$',
};

String currencySymbol(String currency) =>
    currencySymbols[currency] ?? currency;

String formatMoney(
  int minorUnits,
  String currency, {
  bool withSymbol = true,
  bool signed = false,
  String? symbolOverride,
}) {
  final digits = fractionDigitsFor(currency);
  final value = minorUnits / _pow10(digits);
  final format = NumberFormat.decimalPatternDigits(
    locale: 'en_US',
    decimalDigits: digits,
  );
  var text = _applySeparators(format.format(value.abs()));
  if (withSymbol) {
    final symbol = symbolOverride ?? currencySymbol(currency);
    text = symbol.length <= 1 ? '$symbol$text' : '$symbol $text';
  }
  if (value < 0) return '-$text';
  if (signed && value > 0) return '+$text';
  return text;
}

String formatMoneyPlain(int minorUnits, String currency) {
  final digits = fractionDigitsFor(currency);
  final format = NumberFormat.decimalPatternDigits(
    locale: 'en_US',
    decimalDigits: digits,
  );
  return _applySeparators(format.format(minorUnits / _pow10(digits)));
}

int? parseAmountToMinor(String input, String currency) {
  var text = input.trim().replaceAll('\u00a0', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  final negative = text.startsWith('-');
  if (negative || text.startsWith('+')) text = text.substring(1);
  if (text.contains(',') && text.contains('.')) {
    if (text.lastIndexOf(',') > text.lastIndexOf('.')) {
      text = text.replaceAll('.', '').replaceAll(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
  } else if (text.contains(',')) {
    if (MoneyFormatConfig.decimalSeparator == ',' ||
        RegExp(r',\d{1,2}$').hasMatch(text)) {
      text = text.replaceAll(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
  } else if (text.contains('.')) {
    if (MoneyFormatConfig.decimalSeparator == ',' &&
        MoneyFormatConfig.groupSeparator == '.') {
      text = text.replaceAll('.', '');
    }
  }
  if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(text)) return null;
  final parts = text.split('.');
  var whole = parts.first.isEmpty ? '0' : parts.first;
  var fraction = parts.length > 1 ? parts[1] : '';
  final digits = fractionDigitsFor(currency);
  if (fraction.length > digits) {
    fraction = fraction.substring(0, digits);
  }
  fraction = fraction.padRight(digits, '0');
  final value = int.tryParse('$whole$fraction');
  if (value == null) return null;
  return negative ? -value : value;
}

double minorToDouble(int minor, String currency) =>
    minor / _pow10(fractionDigitsFor(currency));

int doubleToMinor(double value, String currency) =>
    (value * _pow10(fractionDigitsFor(currency))).round();

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

String formatRate(double rate) => NumberFormat('#,##0.######', 'en_US').format(rate);
