import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════
class PrayerTime {
  final String name;
  final String arabic;
  final String time; // "H:MM AM/PM"
  final Color color;
  final bool isNext;
  final bool isPast;

  const PrayerTime({
    required this.name,
    required this.arabic,
    required this.time,
    required this.color,
    this.isNext = false,
    this.isPast = false,
  });

  /// Computes duration until this prayer time.
  /// Splits the time string only when the countdown needs refreshing,
  /// not on every build frame.
  Duration get timeUntil {
    final now   = DateTime.now();
    final parts = time.split(' ');       // ["5:12", "AM"]
    final hm    = parts[0].split(':');   // ["5",    "12"]
    int hour    = int.parse(hm[0]);
    final min   = int.parse(hm[1]);
    final isPm  = parts[1] == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    var diff = DateTime(now.year, now.month, now.day, hour, min)
        .difference(now);
    if (diff.isNegative) diff += const Duration(days: 1);
    return diff;
  }
}

// ═══════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════
class PrayerService {
  // DEMO: Static times — replace with a real prayer API (e.g. Aladhan)
  // for production. Computed once per initState call, not every second.
  static List<PrayerTime> getTodayPrayers() {
    final h = DateTime.now().hour;

    final fajrPast    = h >= 5;
    final dhuhrPast   = h >= 12;
    final asrPast     = h >= 15;
    final maghribPast = h >= 18;

    final String next;
    if (!fajrPast) {
      next = 'Fajr';
    } else if (!dhuhrPast) {
      next = 'Dhuhr';
    } else if (!asrPast) {
      next = 'Asr';
    } else if (!maghribPast) {
      next = 'Maghrib';
    } else {
      next = 'Isha';
    }

    return [
      PrayerTime(name: 'Fajr',    arabic: 'الفجر',  time: '5:12 AM',  color: const Color(0xFF5B6FA6), isPast: fajrPast,    isNext: next == 'Fajr'),
      PrayerTime(name: 'Sunrise', arabic: 'الشروق', time: '6:34 AM',  color: const Color(0xFFE8A838), isPast: h >= 6,      isNext: false),
      PrayerTime(name: 'Dhuhr',   arabic: 'الظهر',  time: '12:18 PM', color: const Color(0xFF3D7A55), isPast: dhuhrPast,   isNext: next == 'Dhuhr'),
      PrayerTime(name: 'Asr',     arabic: 'العصر',  time: '3:45 PM',  color: const Color(0xFFB8860B), isPast: asrPast,     isNext: next == 'Asr'),
      PrayerTime(name: 'Maghrib', arabic: 'المغرب', time: '6:22 PM',  color: const Color(0xFFB85C38), isPast: maghribPast, isNext: next == 'Maghrib'),
      PrayerTime(name: 'Isha',    arabic: 'العشاء', time: '7:52 PM',  color: const Color(0xFF3D4F7A), isPast: false,       isNext: next == 'Isha'),
    ];
  }

  /// Returns the next prayer from the list, or null if none found.
  static PrayerTime? getNextPrayer(List<PrayerTime> prayers) =>
      prayers.cast<PrayerTime?>().firstWhere(
        (p) => p!.isNext,
        orElse: () => null,
      );
}
