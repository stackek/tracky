import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._(this._prefs);

  final SharedPreferences _prefs;

  static const _homeCurrency = 'home_currency';
  static const _onboardingDone = 'onboarding_done';
  static const _legacyPrefsXml = 'legacy_prefs_xml';
  static const _themeMode = 'theme_mode';
  static const _dynamicColor = 'dynamic_color';
  static const _lastBackupAt = 'last_backup_at';
  static const _lastBackupName = 'last_backup_name';
  static const _autoBackupEnabled = 'auto_backup_enabled';
  static const _autoBackupPeriod = 'auto_backup_period';
  static const _autoBackupFolder = 'auto_backup_folder';
  static const _lastAutoBackupAt = 'last_auto_backup_at';
  static const _lastAutoBackupName = 'last_auto_backup_name';
  static const _currencyDecimals = 'currency_decimals';
  static const _decimalSeparator = 'decimal_separator';
  static const _groupSeparator = 'group_separator';

  static Future<AppPreferences> load() async =>
      AppPreferences._(await SharedPreferences.getInstance());

  bool get onboardingDone => _prefs.getBool(_onboardingDone) ?? false;
  set onboardingDone(bool value) => _prefs.setBool(_onboardingDone, value);

  String get homeCurrency => _prefs.getString(_homeCurrency) ?? 'EUR';
  set homeCurrency(String value) => _prefs.setString(_homeCurrency, value);

  String? get legacyPrefsXml => _prefs.getString(_legacyPrefsXml);
  set legacyPrefsXml(String? value) {
    if (value == null) {
      _prefs.remove(_legacyPrefsXml);
    } else {
      _prefs.setString(_legacyPrefsXml, value);
    }
  }

  ThemeMode get themeMode {
    switch (_prefs.getString(_themeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  set themeMode(ThemeMode mode) => _prefs.setString(_themeMode, mode.name);

  bool get dynamicColor => _prefs.getBool(_dynamicColor) ?? true;
  set dynamicColor(bool value) => _prefs.setBool(_dynamicColor, value);

  int? get currencyDecimals => _prefs.getInt(_currencyDecimals);

  Future<void> setCurrencyDecimals(int? value) async {
    if (value == null) {
      await _prefs.remove(_currencyDecimals);
    } else {
      await _prefs.setInt(_currencyDecimals, value);
    }
  }

  String get decimalSeparator => _prefs.getString(_decimalSeparator) ?? '.';

  Future<void> setDecimalSeparator(String value) async {
    await _prefs.setString(_decimalSeparator, value);
  }

  String get groupSeparator => _prefs.getString(_groupSeparator) ?? ',';

  Future<void> setGroupSeparator(String value) async {
    await _prefs.setString(_groupSeparator, value);
  }

  DateTime? get lastBackupAt {
    final value = _prefs.getInt(_lastBackupAt);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  String? get lastBackupName => _prefs.getString(_lastBackupName);

  Future<void> recordBackup(String name) async {
    await _prefs.setInt(_lastBackupAt, DateTime.now().millisecondsSinceEpoch);
    await _prefs.setString(_lastBackupName, name);
  }

  bool get autoBackupEnabled => _prefs.getBool(_autoBackupEnabled) ?? false;
  set autoBackupEnabled(bool value) =>
      _prefs.setBool(_autoBackupEnabled, value);

  String get autoBackupPeriod =>
      _prefs.getString(_autoBackupPeriod) ?? 'weekly';
  set autoBackupPeriod(String value) =>
      _prefs.setString(_autoBackupPeriod, value);

  String? get autoBackupFolder => _prefs.getString(_autoBackupFolder);
  set autoBackupFolder(String? value) {
    if (value == null) {
      _prefs.remove(_autoBackupFolder);
    } else {
      _prefs.setString(_autoBackupFolder, value);
    }
  }

  DateTime? get lastAutoBackupAt {
    final value = _prefs.getInt(_lastAutoBackupAt);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  String? get lastAutoBackupName => _prefs.getString(_lastAutoBackupName);

  Future<void> recordAutoBackup(String name) async {
    await _prefs.setInt(
      _lastAutoBackupAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _prefs.setString(_lastAutoBackupName, name);
  }
}

class AppSettings {
  const AppSettings({
    required this.homeCurrency,
    required this.themeMode,
    required this.dynamicColor,
    required this.currencyDecimals,
    required this.decimalSeparator,
    required this.groupSeparator,
  });

  final String homeCurrency;
  final ThemeMode themeMode;
  final bool dynamicColor;
  final int? currencyDecimals;
  final String decimalSeparator;
  final String groupSeparator;

  AppSettings copyWith({
    String? homeCurrency,
    ThemeMode? themeMode,
    bool? dynamicColor,
    int? currencyDecimals,
    bool clearCurrencyDecimals = false,
    String? decimalSeparator,
    String? groupSeparator,
  }) => AppSettings(
    homeCurrency: homeCurrency ?? this.homeCurrency,
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    currencyDecimals: clearCurrencyDecimals
        ? null
        : (currencyDecimals ?? this.currencyDecimals),
    decimalSeparator: decimalSeparator ?? this.decimalSeparator,
    groupSeparator: groupSeparator ?? this.groupSeparator,
  );
}
