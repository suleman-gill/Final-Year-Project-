import 'package:flutter/material.dart';
import '../../config/theme.dart';

class AppHeader extends StatelessWidget {
  final Widget child;
  final double bottomPadding;

  const AppHeader({
    super.key,
    required this.child,
    this.bottomPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.luxuryDark,
        borderRadius: const BorderRadius.only(
          bottomLeft:  Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: const [
          BoxShadow(
            color:       Color(0x1F000000), // Constant compile-time shadow
            blurRadius:  20,
            offset:      Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top:    MediaQuery.of(context).padding.top + 16,
        left:   20,
        right:  20,
        bottom: bottomPadding,
      ),
      child: child,
    );
  }
}
