import 'package:flutter/material.dart';
import '../../config/theme.dart';

class TajweedText extends StatelessWidget {
  final String text;
  final double fontSize;
  final bool showTajweedHighlights;
  final bool isPlaying;
  final Color? defaultColor;
  final TextAlign textAlign;

  const TajweedText({
    super.key,
    required this.text,
    this.fontSize = 20,
    this.showTajweedHighlights = true,
    this.isPlaying = false,
    this.defaultColor,
    this.textAlign = TextAlign.right,
  });

  static List<String> getRulesForWord(String word) {
    List<String> rules = [];
    if (word.contains('\u0653') || word.contains('\u06E4') || word.contains('آ') || word.contains('\u0670')) {
      rules.add('Madd');
    }
    if (word.contains('\u0646\u0651') || word.contains('\u0645\u0651') || 
        word.contains('\u064B') || word.contains('\u064C') || word.contains('\u064D')) {
      rules.add('Ghunna/Ikhfa/Idgham');
    }
    if (word.contains('\u0642\u0652') || word.contains('\u0637\u0652') || 
        word.contains('\u0628\u0652') || word.contains('\u062C\u0652') || 
        word.contains('\u062F\u0652') || 
        word.endsWith('ق') || word.endsWith('ط') || word.endsWith('ب') || word.endsWith('ج') || word.endsWith('د')) {
      rules.add('Qalqalah');
    }
    if (word.contains('خ') || word.contains('ص') || word.contains('ض') || 
        word.contains('ط') || word.contains('ظ') || word.contains('غ') || word.contains('ق')) {
      rules.add('Tafkheem');
    }
    return rules;
  }

  static Color getTajweedColor(List<String> rules, {Color? defaultColor, bool isPlaying = false}) {
    if (isPlaying) return AppColors.gold;
    if (rules.isEmpty) return defaultColor ?? AppColors.textLight;
    
    if (rules.any((r) => r.toLowerCase().contains('madd'))) {
      return const Color(0xFFE040FB); // vibrant purple/magenta
    }
    if (rules.any((r) => r.toLowerCase().contains('ghunna') || 
                         r.toLowerCase().contains('ikhfa') || 
                         r.toLowerCase().contains('idgham') || 
                         r.toLowerCase().contains('iqlab'))) {
      return const Color(0xFF18FFFF); // vibrant cyan
    }
    if (rules.any((r) => r.toLowerCase().contains('qalqalah') || r.toLowerCase().contains('qalqala'))) {
      return const Color(0xFF40C4FF); // vibrant blue
    }
    if (rules.any((r) => r.toLowerCase().contains('tafkheem'))) {
      return const Color(0xFFFFAB40); // vibrant orange
    }
    return const Color(0xFFB388FF); // light lavender
  }

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(RegExp(r'\s+'));
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RichText(
        textAlign: textAlign,
        text: TextSpan(
          children: words.map((word) {
            final rules = getRulesForWord(word);
            final wordColor = showTajweedHighlights 
                ? getTajweedColor(rules, defaultColor: defaultColor, isPlaying: isPlaying)
                : (isPlaying ? AppColors.gold : (defaultColor ?? AppColors.textLight));
            
            return TextSpan(
              text: "$word ",
              style: AppText.arabicLarge.copyWith(
                color: wordColor,
                fontSize: fontSize,
                height: 1.8,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
