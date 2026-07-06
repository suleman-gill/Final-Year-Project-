import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../config/theme_provider.dart';
import '../../features/auth/auth_notifier.dart';
import '../../widgets/common/app_header.dart';
import '../../core/storage/hive_storage.dart';
import '../../services/quran_data_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _autoCorrection  = true;
  bool _dailyGoalNotif  = true;

  String _formatDate(int timestampMs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final sessionDate = DateTime(date.year, date.month, date.day);

    if (sessionDate.isAtSameMomentAs(today)) {
      return 'Today';
    } else if (sessionDate.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return "${months[date.month - 1]} ${date.day}, ${date.year}";
    }
  }

  String _formatAyahs(List<int> ayahs) {
    if (ayahs.isEmpty) return 'No Verses';
    if (ayahs.length == 1) return 'Verse ${ayahs.first}';
    
    final sorted = List<int>.from(ayahs)..sort();
    
    bool isContiguous = true;
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] != sorted[i - 1] + 1) {
        isContiguous = false;
        break;
      }
    }
    
    if (isContiguous) {
      return 'Verse ${sorted.first}–${sorted.last}';
    } else {
      return 'Verses ${sorted.join(', ')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.firebaseUser;

    final userName = authState.displayName;
    final userXp = HiveStorage.getTotalXp();
    final userLevel = 1 + (userXp ~/ 100);
    final userStreak = HiveStorage.getStreak(getLongest: false);
    final longestStreak = HiveStorage.getStreak(getLongest: true);
    final recentSessions = HiveStorage.getSessionHistory();
    final avatarUrl = authState.photoUrl.isNotEmpty ? authState.photoUrl : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppHeader(
              bottomPadding: 32,
              child: Column(
                children: [
                  // Avatar
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 86, height: 86,
                        decoration: BoxDecoration(
                          shape:  BoxShape.circle,
                          color:  AppColors.textLight.withOpacity(0.15),
                          border: Border.all(
                              color: AppColors.gold, width: 2.5),
                          image: DecorationImage(
                            image: NetworkImage(
                              avatarUrl ?? "https://api.dicebear.com/7.x/bottts/svg?seed=ahmad",
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Container(
                        width: 26, height: 26,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: AppColors.primary, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(userName,
                      style: AppText.heading2(color: AppColors.textLight)),
                  Text('Member since 2026',
                      style: AppText.caption(color: AppColors.textLight.withOpacity(0.5))),
                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    children: [
                      _StatBox(
                        value: '$userStreak',
                        label: 'Days\nStreak',
                        icon:  Icons.local_fire_department_rounded,
                        color: const Color(0xFFFF6B35),
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: '$longestStreak',
                        label: 'Longest\nStreak',
                        icon:  Icons.military_tech_rounded,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: '$userXp',
                        label: 'Total\nXP Points',
                        icon:  Icons.star_rounded,
                        color: AppColors.emerald,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Recent Sessions ─────────────────────────
                Text('Recent Sessions', style: AppText.heading3(color: AppColors.textLight)),
                const SizedBox(height: 12),
                if (recentSessions.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Dims.radius),
                      border: Border.all(
                        color: AppColors.textLight.withOpacity(0.04),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 40,
                            color: AppColors.textLight.withOpacity(0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No sessions recorded yet',
                            style: AppText.body(
                              color: AppColors.textLight.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start practicing to build your streak!',
                            style: AppText.caption(
                              color: AppColors.textLight.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  ...recentSessions.map((session) {
                    final surahNum = session['surahNum'] as int? ?? 1;
                    final correctCount = session['correctCount'] as int? ?? 0;
                    final totalWords = session['totalWords'] as int? ?? 0;
                    final timestampMs = session['timestampMs'] as int? ?? 0;
                    
                    final List<int> ayahs = List<int>.from(session['ayahs'] as List? ?? []);
                    final surahName = QuranDataService.surahMap[surahNum]?.nameEnglish ?? 'Unknown Surah';
                    final verseText = _formatAyahs(ayahs);
                    final dateText = _formatDate(timestampMs);
                    final double accuracyPercent = totalWords > 0 
                      ? (correctCount / totalWords) * 100 
                      : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionTile(
                        surah: surahName,
                        verse: verseText,
                        accuracy: accuracyPercent.round(),
                        date: dateText,
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 28),

                // ── Settings ────────────────────────────────
                Text('Settings', style: AppText.heading3(color: AppColors.textLight)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color:        AppColors.surface,
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: AppColors.textLight.withOpacity(0.04)),
                  ),
                  child: Column(
                    children: [
                      _ToggleTile(
                        icon:      Icons.dark_mode_rounded,
                        label:     'Dark Mode',
                        subtitle:  'Switch to dark theme',
                        value:     ref.watch(themeModeProvider) == ThemeMode.dark,
                        color:     const Color(0xFF5B6FA6),
                        onChanged: (v) {
                          ref.read(themeModeProvider.notifier).toggleTheme(v);
                        },
                      ),
                      Divider(
                          height: 1, indent: 64, color: AppColors.textLight.withOpacity(0.1)),
                      _ToggleTile(
                        icon:      Icons.auto_fix_high_rounded,
                        label:     'Auto-correction Feedback',
                        subtitle:  'Show Tajweed tips on mistakes',
                        value:     _autoCorrection,
                        color:     AppColors.emerald,
                        onChanged: (v) =>
                            setState(() => _autoCorrection = v),
                      ),
                      Divider(
                          height: 1, indent: 64, color: AppColors.textLight.withOpacity(0.1)),
                      _ToggleTile(
                        icon:      Icons.notifications_active_rounded,
                        label:     'Daily Goal Notifications',
                        subtitle:  'Reminder to practice daily',
                        value:     _dailyGoalNotif,
                        color:     AppColors.gold,
                        onChanged: (v) =>
                            setState(() => _dailyGoalNotif = v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Navigation tiles
                Container(
                  decoration: BoxDecoration(
                    color:        AppColors.surface,
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: AppColors.textLight.withOpacity(0.04)),
                  ),
                  child: Column(
                    children: [
                      const _NavTile(
                        icon:  Icons.help_outline_rounded,
                        label: 'Help & FAQ',
                        color: Color(0xFF5B6FA6),
                      ),
                      Divider(height: 1, indent: 64, color: AppColors.textLight.withOpacity(0.1)),
                      const _NavTile(
                        icon:  Icons.privacy_tip_outlined,
                        label: 'Privacy Policy',
                        color: Colors.blueGrey,
                      ),
                      Divider(height: 1, indent: 64, color: AppColors.textLight.withOpacity(0.1)),
                      GestureDetector(
                        onTap: () async {
                          await ref.read(authProvider.notifier).logout();
                          if (mounted) context.go('/login');
                        },
                        child: const _NavTile(
                          icon:  Icons.logout_rounded,
                          label: 'Sign Out',
                          color: AppColors.incorrect,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        AppColors.textLight.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.textLight.withOpacity(0.06), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(value,
                  style: AppText.heading2(color: AppColors.textLight)
                      .copyWith(fontSize: 18)),
              Text(label,
                  style: AppText.caption(color: AppColors.textMuted),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _SessionTile extends StatelessWidget {
  final String surah, verse, date;
  final int accuracy;
  const _SessionTile({
    required this.surah,
    required this.verse,
    required this.accuracy,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final color = accuracy >= 90
        ? AppColors.correct
        : accuracy >= 75
            ? AppColors.gold
            : AppColors.incorrect;

    return Container(
      margin:     const EdgeInsets.only(bottom: 12),
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(Dims.radius),
        border: Border.all(color: AppColors.textLight.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.mic_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(surah, style: AppText.heading3(color: AppColors.textLight)),
                Text(verse, style: AppText.caption()),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$accuracy%', style: AppText.heading3(color: color)),
              Text(date, style: AppText.caption()),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: AppColors.textLight, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(subtitle, style: AppText.caption()),
              ],
            ),
          ),
          Switch.adaptive(
            value:       value,
            activeColor: AppColors.gold,
            onChanged:   onChanged,
          ),
        ]),
      );
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(color: AppColors.textLight, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ]),
      );
}
