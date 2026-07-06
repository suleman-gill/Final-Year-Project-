import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import '../../config/theme.dart';
import '../../services/quran_data_service.dart';
import '../../core/storage/hive_storage.dart';

import '../../widgets/quran/tajweed_text.dart';

class QuranReaderScreen extends StatefulWidget {
  final int surahNumber;
  const QuranReaderScreen({super.key, required this.surahNumber});

  @override
  State<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends State<QuranReaderScreen> {
  bool _isBookmarked = false;
  bool _isVertical = true; // true = vertical scroll, false = horizontal page-view
  bool _showTranslation = true;
  List<Ayah> _ayahs = [];
  List<List<Ayah>> _pages = [];
  bool _isLoading = true;

  bool _showTajweedHighlights = false;

  List<String> _getRulesForWord(String word) {
    return TajweedText.getRulesForWord(word);
  }

  Color _getTajweedColor(List<String> rules) {
    return TajweedText.getTajweedColor(rules);
  }

  // Audio playing state
  final AudioPlayer _qariAudioPlayer = AudioPlayer();
  bool _isPlayingQari = false;
  int? _playingVerseNum;

  @override
  void initState() {
    super.initState();
    _isBookmarked = HiveStorage.isBookmarked(widget.surahNumber);
    _loadSurahData();
  }

  @override
  void dispose() {
    _qariAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSurahData() async {
    try {
      final ayahs = await QuranDataService.fetchSurahAyahs(widget.surahNumber);
      setState(() {
        _ayahs = ayahs;
        _pages = QuranDataService.groupAyahsIntoPages(ayahs);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print("Error loading surah: $e");
    }
  }

  void _toggleBookmark() {
    HiveStorage.toggleBookmark(widget.surahNumber);
    setState(() {
      _isBookmarked = !_isBookmarked;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isBookmarked ? "Surah added to bookmarks." : "Surah removed from bookmarks."),
        backgroundColor: AppColors.emerald,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  int _getJuzForSurah(int surahNum) {
    if (surahNum >= 78) return 30;
    if (surahNum >= 67) return 29;
    if (surahNum >= 58) return 28;
    if (surahNum >= 52) return 27;
    if (surahNum >= 46) return 26;
    if (surahNum >= 42) return 25;
    if (surahNum >= 40) return 24;
    if (surahNum >= 37) return 23;
    if (surahNum >= 34) return 22;
    if (surahNum >= 30) return 21;
    if (surahNum >= 28) return 20;
    if (surahNum >= 26) return 19;
    if (surahNum >= 23) return 18;
    if (surahNum >= 21) return 17;
    if (surahNum >= 19) return 16;
    if (surahNum >= 17) return 15;
    if (surahNum >= 15) return 14;
    if (surahNum >= 13) return 13;
    if (surahNum >= 12) return 12;
    if (surahNum >= 10) return 11;
    if (surahNum >= 9) return 10;
    if (surahNum >= 8) return 9;
    if (surahNum >= 7) return 8;
    if (surahNum >= 6) return 7;
    if (surahNum >= 5) return 6;
    if (surahNum >= 4) return 4;
    if (surahNum >= 3) return 3;
    return 1;
  }

  String _toArabicNumerals(int number) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String result = number.toString();
    for (int i = 0; i < english.length; i++) {
      result = result.replaceAll(english[i], arabic[i]);
    }
    return result;
  }

  Future<void> _playProfessionalQari(int verseNum) async {
    final surahStr = widget.surahNumber.toString().padLeft(3, '0');
    final ayahStr = verseNum.toString().padLeft(3, '0');
    final url = 'https://everyayah.com/data/Alafasy_128kbps/$surahStr$ayahStr.mp3';

    try {
      if (_isPlayingQari && _playingVerseNum == verseNum) {
        await _qariAudioPlayer.stop();
        setState(() {
          _isPlayingQari = false;
          _playingVerseNum = null;
        });
        return;
      }

      await _qariAudioPlayer.stop();
      await _qariAudioPlayer.setUrl(url);
      setState(() {
        _isPlayingQari = true;
        _playingVerseNum = verseNum;
      });
      
      _qariAudioPlayer.play();
      
      _qariAudioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _isPlayingQari = false;
              _playingVerseNum = null;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to play audio: $e"),
            backgroundColor: AppColors.incorrect,
          ),
        );
      }
    }
  }

  void _showVerseOptions(Ayah ayah, int verseNum) {
    final isPlayingThis = _isPlayingQari && _playingVerseNum == verseNum;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Verse $verseNum Options",
                          style: AppText.heading2(color: AppColors.gold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.isDarkMode ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(
                              ayah.arabic,
                              style: AppText.arabicMedium.copyWith(color: AppColors.textLight),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ayah.translation,
                            style: AppText.body(color: AppColors.textLight.withOpacity(0.8)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.go('/recitation?surahNum=${widget.surahNumber}&ayahNum=$verseNum');
                      },
                      icon: const Icon(Icons.mic_rounded, color: Colors.white),
                      label: const Text("Recite this Verse", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        setModalState(() {
                          _playingVerseNum = verseNum;
                          _isPlayingQari = !isPlayingThis;
                        });
                        Navigator.pop(context);
                        await _playProfessionalQari(verseNum);
                      },
                      icon: Icon(isPlayingThis ? Icons.stop_rounded : Icons.volume_up_rounded, color: AppColors.gold),
                      label: Text(isPlayingThis ? "Stop Recitation" : "Listen to Professional Qari", style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.gold, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildVerticalListView() {
    return ListView.builder(
      itemCount: _ayahs.length,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemBuilder: (context, index) {
        final ayah = _ayahs[index];
        final verseNum = index + 1;
        final isPlaying = _isPlayingQari && _playingVerseNum == verseNum;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: isPlaying ? AppColors.gold : AppColors.gold.withOpacity(0.12),
              width: isPlaying ? 2 : 1,
            ),
          ),
          elevation: isPlaying ? 4 : 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.gold.withOpacity(0.15),
                      child: Text(
                        _toArabicNumerals(verseNum),
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, color: AppColors.gold),
                          onPressed: () => _playProfessionalQari(verseNum),
                        ),
                        IconButton(
                          icon: const Icon(Icons.mic_rounded, color: AppColors.emerald),
                          onPressed: () {
                            context.go('/recitation?surahNum=${widget.surahNumber}&ayahNum=$verseNum');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
                          onPressed: () => _showVerseOptions(ayah, verseNum),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      children: ayah.arabic.trim().split(RegExp(r'\s+')).map((word) {
                        Color wordColor = AppColors.textLight;
                        if (_showTajweedHighlights && !isPlaying) {
                          final rules = _getRulesForWord(word);
                          wordColor = _getTajweedColor(rules);
                        } else if (isPlaying) {
                          wordColor = AppColors.gold;
                        }
                        return TextSpan(
                          text: "$word ",
                          style: AppText.arabicLarge.copyWith(
                            color: wordColor,
                            height: 1.8,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _showVerseOptions(ayah, verseNum),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (_showTranslation) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 12),
                  Text(
                    ayah.translation,
                    style: AppText.body(color: AppColors.textLight.withOpacity(0.85)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalPageView() {
    if (_pages.isEmpty) {
      return const Center(child: Text("No verses found."));
    }
    return PageView.builder(
      itemCount: _pages.length,
      itemBuilder: (context, pageIndex) {
        final pageAyahs = _pages[pageIndex];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Juz ${_getJuzForSurah(widget.surahNumber)}",
                      style: AppText.caption(color: AppColors.textMuted),
                    ),
                    Text(
                      "Page ${pageIndex + 1} of ${_pages.length}",
                      style: AppText.caption(color: AppColors.gold).copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.auto_stories_rounded, color: AppColors.gold, size: 18),
                  ],
                ),
                const Divider(color: AppColors.gold, thickness: 0.5, height: 24),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: pageAyahs.expand((ayah) {
                              final verseNum = _ayahs.indexOf(ayah) + 1;
                              final isPlaying = _isPlayingQari && _playingVerseNum == verseNum;
                              
                              return [
                                ...ayah.arabic.trim().split(RegExp(r'\s+')).map((word) {
                                  Color wordColor = AppColors.textLight;
                                  if (_showTajweedHighlights && !isPlaying) {
                                    final rules = _getRulesForWord(word);
                                    wordColor = _getTajweedColor(rules);
                                  } else if (isPlaying) {
                                    wordColor = AppColors.gold;
                                  }
                                  return TextSpan(
                                    text: "$word ",
                                    style: AppText.arabicLarge.copyWith(
                                      color: wordColor,
                                      height: 2.2,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _showVerseOptions(ayah, verseNum),
                                  );
                                }),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: GestureDetector(
                                    onTap: () => _showVerseOptions(ayah, verseNum),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: isPlaying ? AppColors.gold : AppColors.gold.withOpacity(0.18),
                                        child: Text(
                                          _toArabicNumerals(verseNum),
                                          style: TextStyle(
                                            color: isPlaying ? Colors.black : AppColors.gold,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ];
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showTranslation) ...[
                  const Divider(color: AppColors.gold, thickness: 0.5, height: 24),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      itemCount: pageAyahs.length,
                      itemBuilder: (context, idx) {
                        final ayah = pageAyahs[idx];
                        final verseNum = _ayahs.indexOf(ayah) + 1;
                        final isPlaying = _isPlayingQari && _playingVerseNum == verseNum;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "[$verseNum] ",
                                style: TextStyle(
                                  color: isPlaying ? AppColors.gold : AppColors.gold.withOpacity(0.8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  ayah.translation,
                                  style: AppText.body(
                                    color: isPlaying ? AppColors.gold : AppColors.textLight.withOpacity(0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final surah = QuranDataService.surahMap[widget.surahNumber] ?? QuranDataService.surahs.first;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textLight),
          onPressed: () {
            _qariAudioPlayer.stop();
            context.go('/quran');
          },
        ),
        title: Text(surah.nameEnglish, style: AppText.heading2(color: AppColors.textLight)),
        actions: [
          IconButton(
            icon: Icon(
              _showTranslation ? Icons.g_translate_rounded : Icons.translate_rounded,
              color: _showTranslation ? AppColors.gold : AppColors.textLight.withOpacity(0.6),
            ),
            onPressed: () {
              setState(() {
                _showTranslation = !_showTranslation;
              });
            },
            tooltip: "Toggle Translation",
          ),
          IconButton(
            icon: Icon(
              _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: AppColors.gold,
            ),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : Column(
                children: [
                  // Page Header card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppColors.surface,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Juz ${_getJuzForSurah(widget.surahNumber)}',
                          style: AppText.caption(color: AppColors.textLight.withOpacity(0.7)),
                        ),
                        Text(
                          surah.nameArabic,
                          style: AppText.arabicMedium.copyWith(color: AppColors.gold, fontSize: 18),
                        ),
                        Text(
                          '${surah.revelationType} • ${surah.verses} Verses',
                          style: AppText.caption(color: AppColors.textLight.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  ),
                  // Layout selector bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.isDarkMode ? AppColors.secondary : Colors.grey.shade200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_stories_rounded, color: AppColors.gold, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Native Reader Layout',
                              style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _buildLayoutChip(true, 'Vertical'),
                            const SizedBox(width: 8),
                            _buildLayoutChip(false, 'Page View'),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showTajweedHighlights = !_showTajweedHighlights;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _showTajweedHighlights 
                                      ? const Color(0xFFFF5252).withOpacity(0.15) 
                                      : (AppColors.isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _showTajweedHighlights 
                                        ? const Color(0xFFFF5252) 
                                        : (AppColors.isDarkMode ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1)),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showTajweedHighlights ? Icons.color_lens_rounded : Icons.color_lens_outlined,
                                      color: _showTajweedHighlights ? const Color(0xFFFF5252) : (AppColors.isDarkMode ? Colors.white70 : Colors.black87),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tajweed',
                                      style: TextStyle(
                                        color: _showTajweedHighlights ? const Color(0xFFFF5252) : (AppColors.isDarkMode ? Colors.white70 : Colors.black87),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isVertical ? _buildVerticalListView() : _buildHorizontalPageView(),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _qariAudioPlayer.stop();
          context.go('/recitation?surahNum=${widget.surahNumber}');
        },
        backgroundColor: AppColors.emerald,
        icon: const Icon(Icons.mic_rounded, color: Colors.white),
        label: const Text('Recite Surah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLayoutChip(bool isVerticalVal, String label) {
    final isSelected = _isVertical == isVerticalVal;
    final isDark = AppColors.isDarkMode;
    
    Color chipBg;
    Color chipBorder;
    Color chipText;
    
    if (isSelected) {
      chipBg = AppColors.gold;
      chipBorder = AppColors.gold;
      chipText = isDark ? Colors.black : Colors.white;
    } else {
      chipBg = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);
      chipBorder = isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1);
      chipText = isDark ? Colors.white70 : Colors.black87;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _isVertical = isVerticalVal;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: chipBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: chipText,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
