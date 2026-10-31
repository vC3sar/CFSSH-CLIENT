import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool useSafFilePicker;
  final double defaultFontSize;
  final bool enableDoubleTabAutocomplete;

  const SettingsState({
    this.useSafFilePicker = true,
    this.defaultFontSize = 14.0,
    this.enableDoubleTabAutocomplete = true,
  });

  SettingsState copyWith({
    bool? useSafFilePicker,
    double? defaultFontSize,
    bool? enableDoubleTabAutocomplete,
  }) {
    return SettingsState(
      useSafFilePicker: useSafFilePicker ?? this.useSafFilePicker,
      defaultFontSize: defaultFontSize ?? this.defaultFontSize,
      enableDoubleTabAutocomplete: enableDoubleTabAutocomplete ?? this.enableDoubleTabAutocomplete,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _init();
    return const SettingsState();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final useSaf = prefs.getBool('useSafFilePicker') ?? true; // By default, use SAF as requested
    final fontSize = prefs.getDouble('defaultFontSize') ?? 14.0;
    final doubleTab = prefs.getBool('enableDoubleTabAutocomplete') ?? true;
    
    state = SettingsState(
      useSafFilePicker: useSaf,
      defaultFontSize: fontSize,
      enableDoubleTabAutocomplete: doubleTab,
    );
  }

  Future<void> setUseSafFilePicker(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useSafFilePicker', value);
    state = state.copyWith(useSafFilePicker: value);
  }

  Future<void> setDefaultFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('defaultFontSize', value);
    state = state.copyWith(defaultFontSize: value);
  }

  Future<void> setEnableDoubleTabAutocomplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableDoubleTabAutocomplete', value);
    state = state.copyWith(enableDoubleTabAutocomplete: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
