import 'package:hive_flutter/hive_flutter.dart';

class HiveStorage {
  static late Box _settingsBox;
  static late Box _bookmarksBox;
  static late Box _historyBox;

  static Future<void> initialize() async {
    await Hive.initFlutter();
    
    // Open boxes
    _settingsBox = await Hive.openBox('settings');
    _bookmarksBox = await Hive.openBox('bookmarks');
    _historyBox = await Hive.openBox('history');
  }

  static void initializeTest({
    required Box settingsBox,
    required Box bookmarksBox,
    required Box historyBox,
  }) {
    _settingsBox = settingsBox;
    _bookmarksBox = bookmarksBox;
    _historyBox = historyBox;
  }

  // Settings
  static double getFontSizeMultiplier() {
    return _settingsBox.get('font_size_multiplier', defaultValue: 1.0) as double;
  }

  static Future<void> setFontSizeMultiplier(double val) async {
    await _settingsBox.put('font_size_multiplier', val);
  }

  static bool isLightMode() {
    return _settingsBox.get('light_mode', defaultValue: false) as bool;
  }

  static Future<void> setLightMode(bool val) async {
    await _settingsBox.put('light_mode', val);
  }

  // Bookmarks
  static List<int> getBookmarks() {
    final list = _bookmarksBox.get('surahs', defaultValue: <int>[]) as List;
    return list.cast<int>();
  }

  static Future<void> toggleBookmark(int surahNum) async {
    final list = getBookmarks();
    if (list.contains(surahNum)) {
      list.remove(surahNum);
    } else {
      list.add(surahNum);
    }
    await _bookmarksBox.put('surahs', list);
  }

  static bool isBookmarked(int surahNum) {
    return getBookmarks().contains(surahNum);
  }

  // User History, XP, and Streak Tracking
  static Future<void> saveSession({
    required int surahNum,
    required int correctCount,
    required int totalWords,
    required List<int> ayahs,
  }) async {
    await _historyBox.add({
      'surahNum': surahNum,
      'correctCount': correctCount,
      'totalWords': totalWords,
      'ayahs': ayahs,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static List<Map<String, dynamic>> getSessionHistory() {
    final List<Map<String, dynamic>> list = [];
    for (var i = 0; i < _historyBox.length; i++) {
      final item = _historyBox.getAt(i);
      if (item is Map) {
        list.add(Map<String, dynamic>.from(item));
      }
    }
    list.sort((a, b) {
      final tA = a['timestampMs'] as int? ?? 0;
      final tB = b['timestampMs'] as int? ?? 0;
      return tB.compareTo(tA);
    });
    return list;
  }

  static int getTotalXp() {
    int xp = 0;
    for (var i = 0; i < _historyBox.length; i++) {
      final item = _historyBox.getAt(i);
      if (item is Map) {
        final correct = item['correctCount'] as int? ?? 0;
        xp += correct * 5;
      }
    }
    return xp;
  }

  static int getStreak({required bool getLongest}) {
    final sessions = getSessionHistory();
    if (sessions.isEmpty) return 0;

    // Rule 1: dedup by local calendar day
    final Set<DateTime> practiceDays = {};
    for (final s in sessions) {
      final ms = s['timestampMs'] as int? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      practiceDays.add(DateTime(dt.year, dt.month, dt.day));
    }
    final sortedDays = practiceDays.toList()..sort();

    if (getLongest) {
      // Rule 3: longest run in the full set, independent of "today"
      int longest = 1;
      int current = 1;
      for (int i = 1; i < sortedDays.length; i++) {
        final diff = sortedDays[i].difference(sortedDays[i - 1]).inDays;
        current = (diff == 1) ? current + 1 : 1;
        if (current > longest) longest = current;
      }
      return longest;
    } else {
      // Rule 2: grace period — active if today or yesterday was practiced
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final yesterday = todayDate.subtract(const Duration(days: 1));

      if (!practiceDays.contains(todayDate) && !practiceDays.contains(yesterday)) {
        return 0; // two+ day gap — streak is broken
      }

      DateTime cursor = practiceDays.contains(todayDate) ? todayDate : yesterday;
      int streak = 0;
      while (practiceDays.contains(cursor)) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      return streak;
    }
  }

  static Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  static dynamic getHistoryListenable() {
    return _historyBox.listenable();
  }

  // Generic helpers for settings box
  static T? get<T>(String key) {
    return _settingsBox.get(key) as T?;
  }

  static Future<void> put(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }
}

