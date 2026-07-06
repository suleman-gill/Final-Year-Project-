import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import '../../config/theme.dart';
import '../../services/quran_data_service.dart';
import '../../features/recitation/recitation_engine.dart';
import '../../widgets/quran/tajweed_text.dart';

// ── Result model ──────────────────────────────────────────────────────
class WordResult {
  final String arabic;
  final String spokenText; // Reconstructed spoken word
  final bool isCorrect;
  final String? errorType;
  final String? tajweedTip;
  final double confidence;
  final List<String> rules;
  final int ayahNumber; // 1-based ayah number

  const WordResult({
    required this.arabic,
    required this.spokenText,
    required this.isCorrect,
    this.errorType,
    this.tajweedTip,
    required this.confidence,
    required this.rules,
    required this.ayahNumber,
  });
}

// ── Screen ────────────────────────────────────────────────────────────
class RecitationResultsScreen extends StatefulWidget {
  final int surahNum;
  
  // New structured parameters
  final Map<int, VerseInferenceResult>? resultsByVerse;
  final Map<int, String>? audioPathsByVerse;
  final List<Map<String, dynamic>>? versesData;
  final List<AyahWord>? allWords;

  // Fallbacks for backward compatibility
  final int ayahNum;
  final List<WordResult> wordResults;
  final int correctCount;
  final int wrongCount;
  final int totalWords;
  final String? audioPath;
  final List<String>? rulesInAyah;
  final String? userTranscription;

  const RecitationResultsScreen({
    super.key,
    required this.surahNum,
    this.resultsByVerse,
    this.audioPathsByVerse,
    this.versesData,
    this.allWords,
    required this.ayahNum,
    required this.wordResults,
    required this.correctCount,
    required this.wrongCount,
    required this.totalWords,
    this.audioPath,
    this.rulesInAyah,
    this.userTranscription,
  });

  @override
  State<RecitationResultsScreen> createState() => _RecitationResultsScreenState();
}

class _RecitationResultsScreenState extends State<RecitationResultsScreen> {
  // Compute overall stats
  double get accuracy {
    if (widget.resultsByVerse != null && widget.resultsByVerse!.isNotEmpty) {
      int totalSpoken = 0;
      int correctSpoken = 0;
      for (final res in widget.resultsByVerse!.values) {
        totalSpoken += res.wordResults.length;
        correctSpoken += res.wordResults.where((w) => w.isCorrect).length;
      }
      return totalSpoken > 0 ? (correctSpoken / totalSpoken) * 100 : 0;
    }
    return widget.totalWords > 0 ? (widget.correctCount / widget.totalWords) * 100 : 0;
  }

  int get correctCount {
    if (widget.resultsByVerse != null && widget.resultsByVerse!.isNotEmpty) {
      int correctSpoken = 0;
      for (final res in widget.resultsByVerse!.values) {
        correctSpoken += res.wordResults.where((w) => w.isCorrect).length;
      }
      return correctSpoken;
    }
    return widget.correctCount;
  }

  int get wrongCount {
    if (widget.resultsByVerse != null && widget.resultsByVerse!.isNotEmpty) {
      int wrongSpoken = 0;
      for (final res in widget.resultsByVerse!.values) {
        wrongSpoken += res.wordResults.where((w) => !w.isCorrect).length;
      }
      return wrongSpoken;
    }
    return widget.wrongCount;
  }

  int get totalWords {
    if (widget.resultsByVerse != null && widget.resultsByVerse!.isNotEmpty) {
      int totalSpoken = 0;
      for (final res in widget.resultsByVerse!.values) {
        totalSpoken += res.wordResults.length;
      }
      return totalSpoken;
    }
    return widget.totalWords;
  }

  Color get _accuracyColor {
    if (accuracy >= 80) return AppColors.correct;
    if (accuracy >= 60) return AppColors.gold;
    return AppColors.incorrect;
  }

  String get _feedbackMessage {
    if (accuracy >= 90) {
      return "Mashallah! Your recitation is exceptionally accurate.";
    } else if (accuracy >= 75) {
      return "Very good! A few minor corrections needed.";
    } else if (accuracy >= 50) {
      return "Good effort. Pay attention to the highlighted rules.";
    } else {
      return "Keep practicing! Listen to the reference Qari and try again.";
    }
  }

  List<Widget> _buildWordWidgetsForVerse(int verseIdx, List<int> wordIndices) {
    final List<Widget> widgets = [];
    final result = widget.resultsByVerse?[verseIdx];
    final allWords = widget.allWords;

    if (allWords == null) return [];

    for (int i = 0; i < wordIndices.length; i++) {
      final flatWordIdx = wordIndices[i];
      if (flatWordIdx >= allWords.length) continue;
      final word = allWords[flatWordIdx];
      
      bool? isWordCorrect;
      if (result != null && i < result.wordResults.length) {
        isWordCorrect = result.wordResults[i].isCorrect;
      }

      Color? bgColor;
      Border? border;

      if (isWordCorrect == true) {
        bgColor = AppColors.correct.withOpacity(0.12);
        border = Border.all(color: AppColors.correct.withOpacity(0.3), width: 1);
      } else if (isWordCorrect == false) {
        bgColor = AppColors.incorrect.withOpacity(0.12);
        border = Border.all(color: AppColors.incorrect.withOpacity(0.4), width: 1.5);
      }

      final rules = TajweedText.getRulesForWord(word.arabic);
      final textColor = TajweedText.getTajweedColor(rules, defaultColor: AppColors.textLight);

      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: border,
          ),
          child: Text(
            word.arabic,
            style: AppText.arabicLarge.copyWith(
              color: textColor,
              fontSize: 22,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  String _toArabicNumerals(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final val = int.tryParse(char);
      return val != null ? arabicDigits[val] : char;
    }).join('');
  }

  @override
  Widget build(BuildContext context) {
    final surah = QuranDataService.surahMap[widget.surahNum] ??
        QuranDataService.surahs.first;

    // Check if we are using the new multi-verse format
    final isMultiVerse = widget.resultsByVerse != null && widget.resultsByVerse!.isNotEmpty && widget.versesData != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.textLight),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Correction Analysis',
          style: AppText.heading2(color: AppColors.textLight),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Overall Stats Summary ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _accuracyColor.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Average Accuracy',
                  style: AppText.caption(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  '${accuracy.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: _accuracyColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _feedbackMessage,
                  style: AppText.body(color: AppColors.textLight.withOpacity(0.85)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatBadge(
                      label: 'Correct',
                      value: '$correctCount',
                      color: AppColors.correct,
                    ),
                    _StatBadge(
                      label: 'Incorrect',
                      value: '$wrongCount',
                      color: AppColors.incorrect,
                    ),
                    _StatBadge(
                      label: 'Total Words',
                      value: '$totalWords',
                      color: AppColors.gold,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Verses Section Title ───────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ayah Breakdown',
                style: AppText.heading2(color: AppColors.textLight),
              ),
              Text(
                surah.nameEnglish,
                style: AppText.heading3(color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Card List ──────────────────────────────────────────────
          if (isMultiVerse)
            ...widget.versesData!.asMap().entries.map((entry) {
              final verseIdx = entry.key;
              final data = entry.value;
              final int ayahNum = data['ayahNumber'] ?? 1;
              final List<int> wordIndices = List<int>.from(data['wordIndices'] ?? []);
              final result = widget.resultsByVerse?[verseIdx];
              final audioPath = widget.audioPathsByVerse?[verseIdx];

              if (result == null) {
                // Return fallback or empty state if this verse has not been recited/analyzed yet
                return const SizedBox.shrink();
              }

              final verseResult = result;
              final s = widget.surahNum.toString().padLeft(3, '0');
              final a = ayahNum.toString().padLeft(3, '0');
              final referenceUrl = 'https://everyayah.com/data/Alafasy_128kbps/$s$a.mp3';

              // Filter errors for this specific verse
              final List<WordInferenceResult> verseErrors = verseResult.wordResults.where((w) => !w.isCorrect).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 20),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.gold.withOpacity(0.12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.gold.withOpacity(0.15),
                                child: Text(
                                  _toArabicNumerals(ayahNum),
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ayah $ayahNum',
                                style: AppText.heading3(color: AppColors.textLight),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _accuracyColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${result.accuracy.toStringAsFixed(0)}% Accuracy',
                              style: TextStyle(
                                color: result.accuracy >= 80 ? AppColors.correct : AppColors.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Rich Arabic Text
                      Wrap(
                        textDirection: TextDirection.rtl,
                        alignment: WrapAlignment.start,
                        spacing: 4,
                        runSpacing: 8,
                        children: _buildWordWidgetsForVerse(verseIdx, wordIndices),
                      ),
                      const SizedBox(height: 20),

                      // Dual Audio Player Container
                      AyahDualAudioPlayer(
                        referenceUrl: referenceUrl,
                        userAudioPath: audioPath,
                      ),

                      // Tajweed details for errors
                      if (verseErrors.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 8),
                        Text(
                          'Mistakes & Tajweed Rules:',
                          style: AppText.heading3(color: AppColors.textLight).copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        ...verseErrors.map((w) {
                          // Find index of this word
                          final wordIndexInAyah = verseResult.wordResults.indexOf(w);
                          String arabicWord = '';
                          if (wordIndexInAyah < wordIndices.length) {
                            final flatIdx = wordIndices[wordIndexInAyah];
                            if (flatIdx < widget.allWords!.length) {
                              arabicWord = widget.allWords![flatIdx].arabic;
                            }
                          }
                          if (arabicWord.isEmpty) arabicWord = w.correctedArabic ?? w.spokenText;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.background.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  arabicWord,
                                  style: AppText.arabicMedium.copyWith(color: AppColors.incorrect, fontSize: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (w.errorType != null && w.errorType!.isNotEmpty)
                                        Text(
                                          w.errorType!,
                                          style: AppText.caption(color: AppColors.gold).copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      if (w.tajweedTip != null && w.tajweedTip!.isNotEmpty)
                                        Text(
                                          w.tajweedTip!,
                                          style: AppText.body(color: AppColors.textMuted).copyWith(fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              );
            }).toList()
          else ...[
            // Single ayah fallback card
            Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.gold.withOpacity(0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Ayah ${widget.ayahNum}',
                          style: AppText.heading3(color: AppColors.textLight),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _accuracyColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${accuracy.toStringAsFixed(0)}% Accuracy',
                            style: TextStyle(
                              color: _accuracyColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 10,
                          children: widget.wordResults.map((word) {
                            final rules = TajweedText.getRulesForWord(word.arabic);
                            final textColor = TajweedText.getTajweedColor(rules, defaultColor: AppColors.textLight);
                            final wordColor = word.isCorrect ? AppColors.correct : AppColors.incorrect;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: word.isCorrect ? AppColors.correct.withOpacity(0.1) : AppColors.incorrect.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: word.isCorrect ? Colors.transparent : AppColors.incorrect.withOpacity(0.4)),
                              ),
                              child: Text(
                                word.arabic,
                                style: AppText.arabicLarge.copyWith(color: textColor, fontSize: 20),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (widget.audioPath != null)
                      AyahDualAudioPlayer(
                        referenceUrl: 'https://everyayah.com/data/Alafasy_128kbps/${widget.surahNum.toString().padLeft(3, '0')}${widget.ayahNum.toString().padLeft(3, '0')}.mp3',
                        userAudioPath: widget.audioPath,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppText.caption(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Scoped Stateful Dual Audio Player ─────────────────────────────────
class AyahDualAudioPlayer extends StatefulWidget {
  final String referenceUrl;
  final String? userAudioPath;

  const AyahDualAudioPlayer({
    super.key,
    required this.referenceUrl,
    this.userAudioPath,
  });

  @override
  State<AyahDualAudioPlayer> createState() => _AyahDualAudioPlayerState();
}

class _AyahDualAudioPlayerState extends State<AyahDualAudioPlayer> {
  late final AudioPlayer _userPlayer;
  late final AudioPlayer _qariPlayer;
  bool _isUserPlaying = false;
  bool _isQariPlaying = false;
  Duration _userDuration = Duration.zero;
  Duration _userPosition = Duration.zero;
  Duration _qariDuration = Duration.zero;
  Duration _qariPosition = Duration.zero;
  bool _userHasAudio = false;

  @override
  void initState() {
    super.initState();
    _userPlayer = AudioPlayer();
    _qariPlayer = AudioPlayer();
    _userHasAudio = widget.userAudioPath != null && widget.userAudioPath!.isNotEmpty;

    _userPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isUserPlaying = state.playing);
      }
    });
    _userPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _userDuration = d);
    });
    _userPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _userPosition = p);
    });

    _qariPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isQariPlaying = state.playing);
      }
    });
    _qariPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _qariDuration = d);
    });
    _qariPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _qariPosition = p);
    });

    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _qariPlayer.setUrl(widget.referenceUrl);
    } catch (e) {
      debugPrint('Error setting Qari audio URL: $e');
    }

    if (_userHasAudio) {
      try {
        final path = widget.userAudioPath!;
        if (path.startsWith('blob:') || path.startsWith('http')) {
          await _userPlayer.setUrl(path);
        } else {
          await _userPlayer.setFilePath(path);
        }
      } catch (e) {
        debugPrint('Error setting user audio file: $e');
        if (mounted) {
          setState(() => _userHasAudio = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _userPlayer.dispose();
    _qariPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleUserPlay() async {
    if (_isUserPlaying) {
      await _userPlayer.pause();
    } else {
      if (_isQariPlaying) {
        await _qariPlayer.pause();
      }
      await _userPlayer.play();
    }
  }

  Future<void> _toggleQariPlay() async {
    if (_isQariPlaying) {
      await _qariPlayer.pause();
    } else {
      if (_isUserPlaying) {
        await _userPlayer.pause();
      }
      await _qariPlayer.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          // Qari Player
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isQariPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  color: AppColors.gold,
                  size: 32,
                ),
                onPressed: _toggleQariPlay,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reference (Sheikh Al-Alafasy)', style: AppText.caption(color: AppColors.gold)),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: AppColors.gold,
                        inactiveTrackColor: AppColors.gold.withOpacity(0.2),
                        thumbColor: AppColors.gold,
                      ),
                      child: Slider(
                        value: _qariPosition.inMilliseconds.toDouble(),
                        max: _qariDuration.inMilliseconds.toDouble().clamp(0.0, double.infinity),
                        onChanged: (val) {
                          _qariPlayer.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_userHasAudio) ...[
            const Divider(color: Colors.white10, height: 16),
            // User Voice Player
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isUserPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: AppColors.emerald,
                    size: 32,
                  ),
                  onPressed: _toggleUserPlay,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Recitation Recording', style: AppText.caption(color: AppColors.emerald)),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.emerald,
                          inactiveTrackColor: AppColors.emerald.withOpacity(0.2),
                          thumbColor: AppColors.emerald,
                        ),
                        child: Slider(
                          value: _userPosition.inMilliseconds.toDouble(),
                          max: _userDuration.inMilliseconds.toDouble().clamp(0.0, double.infinity),
                          onChanged: (val) {
                            _userPlayer.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
