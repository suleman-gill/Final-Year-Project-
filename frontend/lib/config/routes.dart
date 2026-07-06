import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/auth_notifier.dart';

import '../screens/splash/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';


import '../screens/home/home_screen.dart';
import '../screens/quran/surah_list_screen.dart';
import '../screens/quran/quran_reader_screen.dart';
import '../screens/recitation/surah_selection_screen.dart';
import '../screens/recitation/recitation_screen.dart';
import '../screens/recitation/recitation_results_screen.dart';
import '../services/quran_data_service.dart';
import '../features/recitation/recitation_engine.dart';
import '../screens/prayer/prayer_screen.dart';
import '../screens/qibla/qibla_screen.dart';
import '../screens/profile/profile_screen.dart';

import '../widgets/common/main_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authProvider,
      (_, __) => notifyListeners(),
    );
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authProvider);
    final isAuth = authState.isAuthenticated;
    
    final isSplash = state.uri.toString() == '/splash';
    final isLogin = state.uri.toString() == '/login';
    final isRegister = state.uri.toString() == '/register';
    final isForgotPassword = state.uri.toString() == '/forgot-password';
    final isOnboarding = state.uri.toString() == '/onboarding';

    final isAuthRoute = isLogin || isRegister || isForgotPassword || isOnboarding;

    if (isSplash) {
      return null; 
    }

    if (!isAuth && !isAuthRoute) {
      return '/login';
    }

    if (isAuth && isAuthRoute) {
      return '/home';
    }

    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // Non-shell routes
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (_, __) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),



    // Recitation screen — standalone (no shell nav bar, it has its own bottom controls)
    GoRoute(
      path: '/recitation', 
      builder: (context, state) {
        final surahNum = int.tryParse(state.uri.queryParameters['surahNum'] ?? '');
        final ayahNum = int.tryParse(state.uri.queryParameters['ayahNum'] ?? '');
        return RecitationScreen(surahNum: surahNum, ayahNum: ayahNum);
      },
    ),
    GoRoute(
      path: '/recitation/results',
      builder: (context, state) {
        final extra = state.extra;
        if (extra == null || extra is! Map<String, dynamic>) {
          // Safety fallback — navigate back if no data was passed
          return const RecitationResultsScreen(
            surahNum: 1,
            ayahNum: 1,
            wordResults: [],
            correctCount: 0,
            wrongCount: 0,
            totalWords: 0,
          );
        }
        return RecitationResultsScreen(
          surahNum: extra['surahNum'] as int? ?? 1,
          resultsByVerse: extra['resultsByVerse'] as Map<int, VerseInferenceResult>?,
          audioPathsByVerse: extra['audioPathsByVerse'] as Map<int, String>?,
          versesData: extra['versesData'] as List<Map<String, dynamic>>?,
          allWords: extra['allWords'] as List<AyahWord>?,
          ayahNum: extra['ayahNum'] as int? ?? 1,
          wordResults: extra['wordResults'] as List<WordResult>? ?? [],
          correctCount: extra['correctCount'] as int? ?? 0,
          wrongCount: extra['wrongCount'] as int? ?? 0,
          totalWords: extra['totalWords'] as int? ?? 0,
          audioPath: extra['audioPath'] as String?,
          rulesInAyah: extra['rulesInAyah'] as List<String>?,
          userTranscription: extra['userTranscription'] as String?,
        );
      },
    ),

    // Main App Tab Shell
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/home',      
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/quran',     
          builder: (_, __) => const SurahListScreen(),
        ),
        GoRoute(
          path: '/quran/:surahNum',
          builder: (context, state) {
            final num = int.tryParse(state.pathParameters['surahNum'] ?? '1') ?? 1;
            return QuranReaderScreen(surahNumber: num);
          },
        ),
        // Recite tab → Surah Selection (forces user to pick before recording)
        GoRoute(
          path: '/recite-select',
          builder: (_, __) => const SurahSelectionScreen(),
        ),
        GoRoute(
          path: '/prayer',     
          builder: (_, __) => const PrayerScreen(),
        ),
        GoRoute(
          path: '/qibla',      
          builder: (_, __) => const QiblaScreen(),
        ),
        GoRoute(
          path: '/profile',    
          builder: (_, __) => const ProfileScreen(),
        ),

      ],
    ),
  ],
);
});
