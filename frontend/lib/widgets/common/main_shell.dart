import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    _Tab(icon: Icons.home_rounded,        label: 'Home',    path: '/home'),
    _Tab(icon: Icons.menu_book_rounded,   label: 'Quran',   path: '/quran'),
    _Tab(icon: Icons.mic_rounded,         label: 'Recite',  path: '/recite-select'),
    _Tab(icon: Icons.person_rounded,      label: 'Profile', path: '/profile'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => loc.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    
    return Scaffold(
      extendBody: true, // Allows the body to scroll behind the floating nav bar
      body: child,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.textLight.withOpacity(0.04)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000), // Compile-time constant opacity
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_tabs.length, (i) {
                final tab    = _tabs[i];
                final active = i == idx;

                return Semantics(
                  label: '${tab.label} tab',
                  selected: active,
                  button: true,
                  child: GestureDetector(
                    onTap: () => context.go(tab.path),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Icon(
                        tab.icon,
                        size: 26,
                        color: active ? AppColors.gold : AppColors.textLight.withOpacity(0.4),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final IconData icon;
  final String label, path;
  const _Tab({required this.icon, required this.label, required this.path});
}
