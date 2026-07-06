import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/quran_data_service.dart';

/// Forces the user to select a Surah (1-114) and Ayah before
/// navigating to the RecitationScreen.
class SurahSelectionScreen extends ConsumerStatefulWidget {
  const SurahSelectionScreen({super.key});

  @override
  ConsumerState<SurahSelectionScreen> createState() =>
      _SurahSelectionScreenState();
}

class _SurahSelectionScreenState extends ConsumerState<SurahSelectionScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  SurahInfo? _selectedSurah;
  int _selectedAyah = 1;

  List<SurahInfo> get _filteredSurahs {
    if (_searchQuery.isEmpty) return QuranDataService.surahs;
    final q = _searchQuery.toLowerCase();
    return QuranDataService.surahs.where((s) {
      return s.nameEnglish.toLowerCase().contains(q) ||
          s.nameArabic.contains(q) ||
          s.meaning.toLowerCase().contains(q) ||
          s.number.toString() == q;
    }).toList();
  }

  void _selectSurah(SurahInfo surah) {
    setState(() {
      _selectedSurah = surah;
      _selectedAyah = 1;
    });
  }

  void _startRecitation() {
    if (_selectedSurah == null) return;
    context.go(
        '/recitation?surahNum=${_selectedSurah!.number}&ayahNum=$_selectedAyah');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: AppColors.luxuryDark,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Recitation',
                    style: AppText.heading1(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a Surah and Ayah to begin practicing',
                    style: AppText.body(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Dims.radius),
                      border: Border.all(
                          color: AppColors.textLight.withOpacity(0.06)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: AppColors.textLight),
                      decoration: InputDecoration(
                        hintText: 'Search by name, number, or meaning…',
                        hintStyle:
                            const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.gold),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onChanged: (val) =>
                          setState(() => _searchQuery = val),
                    ),
                  ),
                ],
              ),
            ),

            // ── Surah List ─────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _filteredSurahs.length,
                itemBuilder: (context, index) {
                  final surah = _filteredSurahs[index];
                  final isSelected =
                      _selectedSurah?.number == surah.number;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _selectSurah(surah),
                        borderRadius: BorderRadius.circular(Dims.radius),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.gold.withOpacity(0.08)
                                : AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(Dims.radius),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.gold.withOpacity(0.4)
                                  : AppColors.textLight.withOpacity(0.04),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Number badge
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.gold.withOpacity(0.15)
                                      : AppColors.textLight
                                          .withOpacity(0.05),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${surah.number}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.gold
                                        : AppColors.textLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Name & details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      surah.nameEnglish,
                                      style: AppText.heading3(
                                          color: isSelected
                                              ? AppColors.gold
                                              : AppColors.textLight),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${surah.meaning} • ${surah.verses} Verses • ${surah.revelationType}',
                                      style: AppText.caption(),
                                    ),
                                  ],
                                ),
                              ),

                              // Arabic name
                              Text(
                                surah.nameArabic,
                                style: AppText.arabicMedium.copyWith(
                                  fontSize: 18,
                                  color: isSelected
                                      ? AppColors.gold
                                      : AppColors.textLight
                                          .withOpacity(0.7),
                                ),
                              ),

                              if (isSelected)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.check_circle_rounded,
                                      color: AppColors.gold, size: 22),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Bottom: Ayah Picker + Start Button ─────────────────
            if (_selectedSurah != null)
              Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                      top: BorderSide(
                          color: AppColors.textLight.withOpacity(0.08))),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.background.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Surah + Ayah info
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedSurah!.nameEnglish,
                                style: AppText.heading3(
                                    color: AppColors.gold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_selectedSurah!.verses} verses available',
                                style: AppText.caption(),
                              ),
                            ],
                          ),
                        ),

                        // Ayah dropdown
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.08),
                            borderRadius:
                                BorderRadius.circular(Dims.radiusSm),
                            border: Border.all(
                                color: AppColors.gold.withOpacity(0.2)),
                          ),
                          child: DropdownButton<int>(
                            value: _selectedAyah,
                            dropdownColor: AppColors.surface,
                            underline: const SizedBox(),
                            isDense: true,
                            icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.gold,
                                size: 20),
                            style: TextStyle(
                                color: AppColors.textLight, fontSize: 14),
                            items: List.generate(
                              _selectedSurah!.verses,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('Ayah ${i + 1}'),
                              ),
                            ),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedAyah = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Start button (Practice Recitation)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _startRecitation,
                        icon: const Icon(Icons.chrome_reader_mode_rounded, size: 18),
                        label: const Text(
                          'Start Recitation',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
