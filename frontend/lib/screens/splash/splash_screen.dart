import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../features/auth/auth_notifier.dart';
import '../../core/storage/hive_storage.dart';
import '../../services/quran_data_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    );

    _fade = CurvedAnimation(
      parent: _ctrl,
      curve:  const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve:  const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _slideUp = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve:  const Interval(0.3, 0.9, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();

    // Warm up the Quran database offline in isolate background
    QuranDataService.ensureInitialized();

    // Navigate based on auth state and onboarding
    Future.delayed(const Duration(milliseconds: 2500), () async {
      if (!mounted) return;
      // Wait for initialization to complete if it hasn't already
      await QuranDataService.ensureInitialized();
      if (!mounted) return;

      final authState = ref.read(authProvider);
      final hasSeenOnboarding = HiveStorage.get<bool>('has_seen_onboarding') ?? false;

      if (authState.token != null) {
        context.go('/home');
      } else if (hasSeenOnboarding) {
        context.go('/login');
      } else {
        context.go('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Crescent icon ──────────────────────────
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape:  BoxShape.circle,
                          border: Border.all(
                            color: AppColors.gold.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.nights_stay_rounded,
                          color: AppColors.gold,
                          size:  52,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── App name ───────────────────────────────
                  Transform.translate(
                    offset: Offset(0, _slideUp.value),
                    child: FadeTransition(
                      opacity: _fade,
                      child: Column(
                        children: [
                          Text(
                            'Tilawah AI',
                            style: AppText.heading1(color: AppColors.textLight)
                                .copyWith(
                              fontSize:      40,
                              fontWeight:    FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'AI-Powered Quran Learning',
                            style: AppText.caption(color: AppColors.gold)
                                .copyWith(fontSize: 12, letterSpacing: 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // ── Loading bar ────────────────────────────
                  FadeTransition(
                    opacity: _fade,
                    child: const SizedBox(
                      width: 140,
                      child: LinearProgressIndicator(
                        backgroundColor: Color(0x1AFFFFFF),
                        color:           AppColors.gold,
                        minHeight:       2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
