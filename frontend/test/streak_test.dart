import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tilawah_app/core/storage/hive_storage.dart';

void main() {
  late Box settingsBox;
  late Box bookmarksBox;
  late Box historyBox;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('tilawah_streak_test');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox('settings');
    bookmarksBox = await Hive.openBox('bookmarks');
    historyBox = await Hive.openBox('history');
    HiveStorage.initializeTest(
      settingsBox: settingsBox,
      bookmarksBox: bookmarksBox,
      historyBox: historyBox,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('HiveStorage User History & Progress Tests', () {
    test('saveSession writes to box and getSessionHistory returns sorted results', () async {
      await HiveStorage.saveSession(
        surahNum: 1,
        correctCount: 5,
        totalWords: 7,
        ayahs: [1, 2, 3],
      );

      // Add another session older
      final olderTime = DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch;
      await historyBox.add({
        'surahNum': 2,
        'correctCount': 10,
        'totalWords': 12,
        'ayahs': [1],
        'timestampMs': olderTime,
      });

      final history = HiveStorage.getSessionHistory();
      expect(history.length, 2);
      expect(history[0]['surahNum'], 1); // latest first
      expect(history[1]['surahNum'], 2); // older second
    });

    test('getTotalXp calculates correctCount * 5 across all sessions', () async {
      await HiveStorage.saveSession(surahNum: 1, correctCount: 5, totalWords: 10, ayahs: [1]);
      await HiveStorage.saveSession(surahNum: 1, correctCount: 3, totalWords: 10, ayahs: [2]);

      expect(HiveStorage.getTotalXp(), 40); // (5 + 3) * 5 = 40 XP
    });

    test('getStreak handles same-day deduplication correctly (Rule 1)', () async {
      final now = DateTime.now();
      // Save 3 sessions today
      for (int i = 0; i < 3; i++) {
        await historyBox.add({
          'surahNum': 1,
          'correctCount': 5,
          'totalWords': 10,
          'ayahs': [1],
          'timestampMs': now.millisecondsSinceEpoch,
        });
      }

      expect(HiveStorage.getStreak(getLongest: false), 1);
      expect(HiveStorage.getStreak(getLongest: true), 1);
    });

    test('getStreak grace period - active today (Rule 2)', () async {
      final now = DateTime.now();
      // Practice today and yesterday
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.millisecondsSinceEpoch,
      });
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      });

      expect(HiveStorage.getStreak(getLongest: false), 2);
    });

    test('getStreak grace period - active yesterday, not practiced today yet (Rule 2)', () async {
      final now = DateTime.now();
      // Practice yesterday and the day before, but not today
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      });
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      });

      expect(HiveStorage.getStreak(getLongest: false), 2);
    });

    test('getStreak grace period - resets to 0 after 2+ days gap (Rule 2)', () async {
      final now = DateTime.now();
      // Last practice was 2 days ago
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      });
      await historyBox.add({
        'surahNum': 1,
        'correctCount': 5,
        'totalWords': 10,
        'ayahs': [1],
        'timestampMs': now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      });

      expect(HiveStorage.getStreak(getLongest: false), 0);
    });

    test('getStreak longest run is preserved correctly when current resets (Rule 3)', () async {
      final now = DateTime.now();
      
      // Streak of 4 days: 10, 9, 8, 7 days ago
      for (int i = 7; i <= 10; i++) {
        await historyBox.add({
          'surahNum': 1,
          'correctCount': 5,
          'totalWords': 10,
          'ayahs': [1],
          'timestampMs': now.subtract(Duration(days: i)).millisecondsSinceEpoch,
        });
      }

      // Streak of 2 days: yesterday and 2 days ago
      for (int i = 1; i <= 2; i++) {
        await historyBox.add({
          'surahNum': 1,
          'correctCount': 5,
          'totalWords': 10,
          'ayahs': [1],
          'timestampMs': now.subtract(Duration(days: i)).millisecondsSinceEpoch,
        });
      }

      // Current streak: practiced yesterday, so active (length 2)
      expect(HiveStorage.getStreak(getLongest: false), 2);
      // Longest streak: 4 days run is preserved
      expect(HiveStorage.getStreak(getLongest: true), 4);
    });
   group('HiveStorage Timezone Consistency (Rule 4)', () {
      test('Midnight boundaries and local timezone conversion consistency', () async {
        // Create timestamps exactly on either side of local midnight to verify truncation logic
        final localNow = DateTime.now();
        
        final localTodayMidnight = DateTime(localNow.year, localNow.month, localNow.day);
        final localYesterdayMidnight = localTodayMidnight.subtract(const Duration(days: 1));
        
        // Add one session 1 minute before yesterday midnight
        await historyBox.add({
          'surahNum': 1,
          'correctCount': 5,
          'totalWords': 10,
          'ayahs': [1],
          'timestampMs': localYesterdayMidnight.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        });
        
        // Add one session 1 minute after yesterday midnight
        await historyBox.add({
          'surahNum': 1,
          'correctCount': 5,
          'totalWords': 10,
          'ayahs': [1],
          'timestampMs': localYesterdayMidnight.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        });

        // The two sessions are on different local calendar days (one is "the day before yesterday", one is "yesterday")
        // So the streak should recognize them as two separate days
        expect(HiveStorage.getStreak(getLongest: false), 2);
      });
    });
  });
}
