import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/quran_data_service.dart';
import '../../widgets/common/app_header.dart';

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});
  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  List<SurahInfo> _filtered = QuranDataService.surahs;
  String _query = '';

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _filtered = QuranDataService.surahs;
      } else {
        _filtered = QuranDataService.surahs.where((s) =>
          s.nameEnglish.toLowerCase().contains(q) ||
          s.nameArabic.contains(query.trim()) ||
          s.number.toString() == q,
        ).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Holy Quran',
                      style: AppText.heading2(color: Colors.white)),
                  Text('114 Surahs • Complete Reading Platform',
                      style: AppText.caption(color: AppColors.textLight.withOpacity(0.5))),
                  const SizedBox(height: 16),

                  // Search box
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      onChanged: _onSearch,
                      style: AppText.body(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search surah...',
                        hintStyle: AppText.body(color: AppColors.textLight.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AppColors.textLight.withOpacity(0.3), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Surah list ─────────────────────────────────────
          _filtered.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No surah found for "$_query"',
                      style: AppText.body(),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _SurahTile(surah: _filtered[i]),
                      childCount: _filtered.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SurahTile extends StatelessWidget {
  final SurahInfo surah;
  const _SurahTile({required this.surah});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/quran/${surah.number}'),
      child: Container(
        margin:     const EdgeInsets.only(bottom: 12),
        padding:    const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(Dims.radius),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color:        AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                '${surah.number}',
                style: AppText.heading3(color: AppColors.gold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surah.nameEnglish,
                    style: AppText.heading3(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(surah.revelationType,
                          style: AppText.caption(color: AppColors.gold)),
                      const SizedBox(width: 6),
                      Container(
                        width: 3, height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${surah.verses} verses',
                          style: AppText.caption(color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              surah.nameArabic,
              style: AppText.arabicMedium.copyWith(
                color:    AppColors.gold,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.mic_rounded, color: AppColors.gold),
              onPressed: () => context.go('/recitation?surahNum=${surah.number}'),
            ),
          ],
        ),
      ),
    );
  }
}
