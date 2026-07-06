import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../config/theme_provider.dart';
import '../../features/auth/auth_notifier.dart';
import '../../core/storage/hive_storage.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.firebaseUser;

    final userName = authState.displayName;
    final avatarUrl = authState.photoUrl.isNotEmpty ? authState.photoUrl : null;

    return ValueListenableBuilder(
      valueListenable: HiveStorage.getHistoryListenable(),
      builder: (context, box, child) {
        final totalXp = HiveStorage.getTotalXp();
        final userStreak = HiveStorage.getStreak(getLongest: false);
        final userLevel = (totalXp / 100).floor() + 1;
        final userXp = totalXp % 100;

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: _buildDrawer(context, ref, userName, userLevel, userXp, avatarUrl),
          body: CustomScrollView(
            slivers: [
          // ── Header / Top Profile Bar ──────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.background,
            automaticallyImplyLeading: false,
            leading: Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AppColors.gold, size: 26),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                );
              },
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.nights_stay_rounded, // Gold moon logo placeholder
                  color: AppColors.gold,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  "Tilawah AI",
                  style: AppText.heading2(color: AppColors.textLight).copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.luxuryDark,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 85, 20, 16),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 2),
                          image: DecorationImage(
                            image: NetworkImage(
                              avatarUrl ?? "https://api.dicebear.com/7.x/bottts/svg?seed=ahmad",
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      
                      // Name & Level details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Salam,",
                              style: AppText.caption(color: AppColors.textLight.withOpacity(0.6)),
                            ),
                            Text(
                              userName,
                              style: AppText.heading2(color: AppColors.textLight).copyWith(fontSize: 18),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // XP Progress Bar
                            Row(
                              children: [
                                Text(
                                  "Lvl $userLevel",
                                  style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: (userXp % 100) / 100,
                                      minHeight: 4,
                                      backgroundColor: AppColors.textLight.withOpacity(0.1),
                                      color: AppColors.emerald,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "${userXp % 100}/100 XP",
                                  style: AppText.caption(color: AppColors.textLight.withOpacity(0.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [

              // Settings/Log out
              IconButton(
                icon: Icon(Icons.logout_rounded, color: AppColors.textLight.withOpacity(0.7)),
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ── Scrollable Body ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Streak and Daily Goal Row ─────────────────────
                Row(
                  children: [
                    // Streak card
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(Dims.radius),
                          border: Border.all(color: AppColors.gold.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "🔥 Streak",
                              style: TextStyle(color: AppColors.textLight.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "$userStreak Days",
                              style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Keep going daily!",
                              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    
                    // Daily Challenge progress
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(Dims.radius),
                          border: Border.all(color: AppColors.emerald.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "🎯 Daily Goal",
                              style: TextStyle(color: AppColors.textLight.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: 0.7,
                                minHeight: 6,
                                backgroundColor: AppColors.textLight.withOpacity(0.1),
                                color: AppColors.emerald,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "70% Completed",
                              style: TextStyle(color: AppColors.emerald, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Continue Reading Section ───────────────────────
                GestureDetector(
                  onTap: () => context.go('/quran/1'),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Dims.radius),
                      border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                      boxShadow: const [AppShadows.glass],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  "CONTINUE READING",
                                  style: TextStyle(color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Surah Al-Fatiha",
                                style: AppText.heading2(color: AppColors.textLight),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Ayah 1 • The Opening",
                                style: TextStyle(color: AppColors.textLight.withOpacity(0.6), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Calligraphy / Stylized Quran Icon
                        const Icon(
                          Icons.menu_book_rounded,
                          color: AppColors.gold,
                          size: 48,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Quick Action Tiles ────────────────────────────
                Text("Quick Actions", style: AppText.heading3()),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuickActionBtn(
                      icon: Icons.mic_rounded,
                      label: "AI Recite",
                      color: AppColors.emerald,
                      onTap: () => context.go('/recitation'),
                    ),
                    _QuickActionBtn(
                      icon: Icons.alarm_rounded,
                      label: "Prayers",
                      color: const Color(0xFF5B6FA6),
                      onTap: () => context.go('/prayer'),
                    ),
                    _QuickActionBtn(
                      icon: Icons.explore_rounded,
                      label: "Qibla",
                      color: AppColors.gold,
                      onTap: () => context.go('/qibla'),
                    ),
                    _QuickActionBtn(
                      icon: Icons.person_rounded,
                      label: "Profile",
                      color: Colors.purpleAccent,
                      onTap: () => context.go('/profile'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Today's Challenge Card ─────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Today's Challenge", style: AppText.heading3()),
                          const Text(
                            "+50 XP",
                            style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.circle_notifications_rounded, color: AppColors.gold, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Complete Al-Fatiha Recitation",
                                  style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  "Recite with at least 85% Tajweed accuracy",
                                  style: AppText.caption(),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => context.go('/recitation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text("Start", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Daily Quote Card ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: const Color(0x0DFFFFFF)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.format_quote_rounded, color: AppColors.gold, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        '"The best of you are those who learn the Quran and teach it."',
                        textAlign: TextAlign.center,
                        style: AppText.body(color: AppColors.textLight).copyWith(
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "— Sahih Al-Bukhari",
                        style: AppText.caption(color: AppColors.gold).copyWith(fontWeight: FontWeight.bold),
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
      },
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    WidgetRef ref,
    String userName,
    int userLevel,
    int userXp,
    String? avatarUrl,
  ) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 32,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              gradient: AppColors.luxuryDark,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(Dims.radius),
                bottomRight: Radius.circular(Dims.radius),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo & App Name
                Row(
                  children: [
                    const Icon(
                      Icons.nights_stay_rounded,
                      color: AppColors.gold,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Tilawah AI",
                      style: AppText.heading2(color: AppColors.textLight).copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // User Details
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold, width: 1.5),
                        image: DecorationImage(
                          image: NetworkImage(
                            avatarUrl ?? "https://api.dicebear.com/7.x/bottts/svg?seed=ahmad",
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: AppText.heading3(color: AppColors.textLight).copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Level $userLevel · $userXp XP",
                            style: AppText.caption(color: AppColors.gold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Drawer Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildDrawerItem(
                  icon: Icons.history_rounded,
                  label: "User History",
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/profile'); // User History resides inside profile
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.analytics_rounded,
                  label: "User Progress",
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/profile');
                  },
                ),
                const Divider(height: 24, color: Colors.white10),
                _buildDrawerItem(
                  icon: Icons.star_border_rounded,
                  label: "Free Plan (Current)",
                  trailingText: "Active",
                  trailingColor: AppColors.gold,
                  onTap: () {},
                ),
                _buildDrawerItem(
                  icon: Icons.diamond_rounded,
                  label: "Premium Plan",
                  trailingText: "Upgrade",
                  trailingColor: AppColors.emerald,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Upgrade to Premium is coming soon!"),
                        backgroundColor: AppColors.gold,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Footer
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "Version 1.0.0",
              style: AppText.caption(color: AppColors.textLight.withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    String? trailingText,
    Color? trailingColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textLight.withOpacity(0.7), size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: AppColors.textLight,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailingText != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (trailingColor ?? AppColors.gold).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (trailingColor ?? AppColors.gold).withOpacity(0.2)),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  color: trailingColor ?? AppColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: AppColors.textLight.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
