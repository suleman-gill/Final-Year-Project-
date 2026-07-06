import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/storage/hive_storage.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPageData> _pages = [
    OnboardingPageData(
      title: "Read Quran Anywhere",
      subtitle: "Access 114 Surahs with continuous justified font, standard translation support, and complete audio recitation guides.",
      icon: Icons.menu_book_rounded,
      highlight: "Read & Listen"
    ),
    OnboardingPageData(
      title: "AI Tajweed Teacher",
      subtitle: "Recite individual verses and receive immediate word-by-word correctness feedback, confidence levels, and tips.",
      icon: Icons.mic_rounded,
      highlight: "Pronounce Accurately"
    ),
    OnboardingPageData(
      title: "Memorization Assistant",
      subtitle: "Conquer verses using custom Hide/Reveal tests, scheduled revisions, memory score logs, and spaced repetition timers.",
      icon: Icons.school_rounded,
      highlight: "Store Quran Safely"
    ),
    OnboardingPageData(
      title: "Gamified Learning",
      subtitle: "Maintain daily streaks, gain experience points, complete goals, level up, and share achievements with peers.",
      icon: Icons.local_fire_department_rounded,
      highlight: "Maintain Streaks"
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  void _finishOnboarding(BuildContext context) async {
    await HiveStorage.put('has_seen_onboarding', true);
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDarkMode;
    final titleColor = isDark ? Colors.white : AppColors.primary;
    final subtitleColor = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.luxuryDark,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar (Skip button)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_currentPage < _pages.length - 1)
                      TextButton(
                        onPressed: () => _finishOnboarding(context),
                        child: const Text(
                          "Skip",
                          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),

              // Page contents
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Giant animated icon container
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.gold.withOpacity(0.2), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withOpacity(0.08),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  )
                                ],
                              ),
                              child: Icon(
                                page.icon,
                                size: 64,
                                color: AppColors.gold,
                              ),
                            ),
                            const SizedBox(height: 36),
                            
                            // Tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.emeraldBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.emerald.withOpacity(0.2)),
                              ),
                              child: Text(
                                page.highlight.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.emerald,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Title
                            Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: AppText.heading1(color: titleColor).copyWith(fontSize: 26),
                            ),
                            const SizedBox(height: 16),
                            
                            // Subtitle
                            Text(
                              page.subtitle,
                              textAlign: TextAlign.center,
                              style: AppText.body(color: subtitleColor).copyWith(height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Bottom control panel
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Carousel Indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active ? AppColors.gold : AppColors.textMuted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 40),

                    // Next / Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentPage < _pages.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _finishOnboarding(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Dims.radius),
                          ),
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1 ? "Get Started" : "Continue",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingPageData {
  final String title;
  final String subtitle;
  final IconData icon;
  final String highlight;

  OnboardingPageData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.highlight,
  });
}
