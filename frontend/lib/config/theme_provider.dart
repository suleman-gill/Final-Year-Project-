import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/hive_storage.dart';
import 'theme.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const _storageKey = 'theme_mode';

  ThemeNotifier() : super(_getInitialMode());

  static ThemeMode _getInitialMode() {
    final mode = HiveStorage.get<String>(_storageKey);
    if (mode == 'dark') {
      AppColors.isDarkMode = true;
      return ThemeMode.dark;
    } else {
      AppColors.isDarkMode = false;
      return ThemeMode.light;
    }
  }

  Future<void> toggleTheme(bool isDarkMode) async {
    final mode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    AppColors.isDarkMode = isDarkMode;
    state = mode;
    await HiveStorage.put(_storageKey, isDarkMode ? 'dark' : 'light');
  }
}

final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
