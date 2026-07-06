import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../config/theme.dart';
import '../../features/auth/auth_notifier.dart';
import '../../features/recitation/recitation_engine.dart';
import '../../services/quran_data_service.dart';
import '../../widgets/quran/mushaf_page_frame.dart';
import '../../widgets/quran/tajweed_text.dart';
import 'recitation_results_screen.dart';
import '../../core/storage/hive_storage.dart';


// ── Verse grouping helper ────────────────────────────────────────────
class _VerseInfo {
  final int ayahNumber; // 1-based within surah
  final List<int> wordIndices; // indices into flat word list (real words only)
  final int? markerIndex; // index of ﴿N﴾ in flat word list

  const _VerseInfo({
    required this.ayahNumber,
    required this.wordIndices,
    this.markerIndex,
  });
}

class RecitationScreen extends ConsumerStatefulWidget {
  final int? surahNum;
  final int? ayahNum;

  const RecitationScreen({super.key, this.surahNum, this.ayahNum});

  @override
  ConsumerState<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends ConsumerState<RecitationScreen>
    with SingleTickerProviderStateMixin {
  // ── Word & verse data ──────────────────────────────────────────────
  List<AyahWord> _allWords = [];
  late List<WordStatus> _statuses;
  List<_VerseInfo> _verses = [];
  int _currentVerseIdx = 0;

  // ── Scopes & Hafiz mode ────────────────────────────────────────────
  bool _isHafizMode = false;
  List<List<_VerseInfo>> _versesByPage = [];
  final Map<int, int> _ayahToPageIdx = {};
  late PageController _pageController;
  int _currentPageIdx = 0;

  // ── Scoring & Results collection ───────────────────────────────────
  final Map<int, VerseInferenceResult> _resultsByVerse = {};
  final Map<int, String> _audioPathsByVerse = {};
  bool _isSessionSaved = false;
  final ScrollController _scrollController = ScrollController();

  // ── Recording state ────────────────────────────────────────────────
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _sessionDone = false;
  String? _currentTajweedTip;
  String? _latestAudioPath;
  final List<String> _evaluatedRules = [];

  // ── Audio ──────────────────────────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  VerseInferenceResult? _lastVerseResult;

  // ── Engine ─────────────────────────────────────────────────────────
  late RecitationInferenceEngine _engine;
  StreamSubscription<VerseInferenceResult>? _verseResultSub;
  StreamSubscription<WsConnectionState>? _connectionSub;
  WsConnectionState _connectionState = WsConnectionState.disconnected;

  // ── Animation ──────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;

  int get currentSurah => widget.surahNum ?? 1;
  int get currentAyah => widget.ayahNum ?? 1;

  @override
  void initState() {
    super.initState();
    _cleanupTempRecordings();
    _pageController = PageController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _engine = WebSocketInferenceEngine();
    _loadWordsAndInit();
  }

  Future<void> _cleanupTempRecordings() async {
    if (kIsWeb) return;
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        final list = dir.listSync();
        for (final entity in list) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('recitation_') || name.startsWith('verse_')) {
              await entity.delete().catchError((e) => print('Delete temp file failed: $e'));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Recitation] Error cleaning up temp recordings: $e');
    }
  }

  Future<void> _loadWordsAndInit() async {
    try {
      final ayahs = await QuranDataService.fetchSurahAyahs(currentSurah);
      final pages = QuranDataService.groupAyahsIntoPages(ayahs);
      final words = await QuranDataService.fetchSurahWords(currentSurah);

      setState(() {
        _allWords = words;
        _statuses = List.filled(_allWords.length, WordStatus.pending);
        _parseVerses();
        _groupVersesIntoPages(pages, ayahs);

        final initialPage = _ayahToPageIdx[currentAyah] ?? 0;
        _currentPageIdx = initialPage;
        _pageController = PageController(initialPage: initialPage);

        int initialVerseIdx = 0;
        for (int i = 0; i < _verses.length; i++) {
          if (_verses[i].ayahNumber == currentAyah) {
            initialVerseIdx = i;
            break;
          }
        }
        _currentVerseIdx = initialVerseIdx;
      });
    } catch (e) {
      print("Error loading words and initializing recitation: $e");
    }

    // Listen for verse-level results
    _verseResultSub = _engine.verseResults.listen((result) {
      if (mounted) _handleVerseResult(result);
    });

    // Listen for connection state
    _connectionSub = _engine.connectionStates.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
        if (state == WsConnectionState.disconnected && _isRecording) {
          _cancelRecording();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Connection lost. Please try again."),
              backgroundColor: AppColors.incorrect,
            ),
          );
        }
      }
    });

    // Initialize engine with auth token
    final token =
        await ref.read(authProvider.notifier).getFreshToken() ?? '';
    await _engine.initialize(token);

    // Start session
    final wordMaps = List.generate(_allWords.length, (i) => {
      'index': i,
      'arabic': _allWords[i].arabic,
      'phonetic': _allWords[i].phonetic,
    });
    await _engine.startSession(currentSurah, currentAyah, wordMaps);
  }

  void _parseVerses() {
    _verses = [];
    if (_allWords.isEmpty) return;

    final Map<int, List<int>> grouped = {};
    for (int i = 0; i < _allWords.length; i++) {
      final word = _allWords[i];
      grouped.putIfAbsent(word.ayahNumber, () => []).add(i);
    }

    final sortedAyahNumbers = grouped.keys.toList()..sort();
    for (final num in sortedAyahNumbers) {
      _verses.add(_VerseInfo(
        ayahNumber: num,
        wordIndices: grouped[num]!,
      ));
    }
  }

  void _groupVersesIntoPages(List<List<Ayah>> pages, List<Ayah> allAyahs) {
    _ayahToPageIdx.clear();
    for (int p = 0; p < pages.length; p++) {
      for (final ayah in pages[p]) {
        final idx = allAyahs.indexOf(ayah);
        if (idx != -1) {
          _ayahToPageIdx[idx + 1] = p;
        }
      }
    }

    final Map<int, List<_VerseInfo>> grouped = {};
    for (final verse in _verses) {
      final pageIdx = _ayahToPageIdx[verse.ayahNumber] ?? 0;
      grouped.putIfAbsent(pageIdx, () => []).add(verse);
    }

    _versesByPage = List.generate(pages.length, (p) => grouped[p] ?? []);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _cancelRecording();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _verseResultSub?.cancel();
    _connectionSub?.cancel();
    _pageController.dispose();
    _engine.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // RECORDING — verse-level
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _toggleRecording() async {
    if (_isProcessing || _sessionDone) return;
    if (_isRecording) {
      await _stopAndSendVerse();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_connectionState != WsConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _connectionState == WsConnectionState.reconnecting
                ? 'Reconnecting to server...'
                : 'Connecting to server... Please wait.',
          ),
          backgroundColor: AppColors.gold,
        ),
      );
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isRecording = true;
        });

        // On Android/iOS we need a real file path; web uses blob URL (empty string)
        String? recordPath;
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          final verseNum = _verses.isNotEmpty && _currentVerseIdx < _verses.length
              ? _verses[_currentVerseIdx].ayahNumber
              : currentAyah;
          recordPath = p.join(
            dir.path,
            'recitation_${currentSurah}_${verseNum}_${DateTime.now().millisecondsSinceEpoch}.wav',
          );
        }

        // Chrome's MediaRecorder does NOT support WAV — use opus on web,
        // which it natively records as webm/opus. The backend handles decoding.
        final encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.wav;
        debugPrint('[Recitation] Starting recording with encoder: $encoder');

        await _audioRecorder.start(
          RecordConfig(
            encoder: encoder,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: recordPath ?? '',
        );
        debugPrint('[Recitation] Recording started successfully');
      } else {
        debugPrint('[Recitation] Microphone permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission required. Please allow access.'),
              backgroundColor: AppColors.incorrect,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopAndSendVerse() async {
    try {
      debugPrint('[Recitation] Stopping recording...');
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
        _latestAudioPath = path;
        if (path != null) {
          _audioPathsByVerse[_currentVerseIdx] = path;
        }
      });

      if (path == null) {
        debugPrint('[Recitation] ERROR: recorder returned null path');
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No audio recorded. Try again."),
              backgroundColor: AppColors.incorrect,
            ),
          );
        }
        return;
      }

      debugPrint('[Recitation] Recording saved to: $path');

      // Read audio bytes
      Uint8List bytes;
      if (kIsWeb) {
        final response = await Dio().get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(response.data!);
      } else {
        bytes = await File(path).readAsBytes();
      }

      debugPrint('[Recitation] Audio bytes read: ${bytes.length}');

      if (bytes.isEmpty) {
        debugPrint('[Recitation] ERROR: audio bytes are empty');
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Recorded audio is empty. Try again."),
              backgroundColor: AppColors.incorrect,
            ),
          );
        }
        return;
      }

      // Gather expected words for the current verse
      final verse = _verses[_currentVerseIdx];
      final expectedWords =
          verse.wordIndices.map((i) => _allWords[i].arabic).toList();

      final base64Audio = base64Encode(bytes);
      debugPrint(
          '[Recitation] Sending verse audio: verseIdx=$_currentVerseIdx, '
          'words=${expectedWords.length}, base64Len=${base64Audio.length}');

      // Send verse audio to backend
      _engine.sendVerseAudio(base64Audio, _currentVerseIdx, expectedWords);

      // Timeout: if no result in 30s, cancel processing
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _isProcessing) {
          debugPrint('[Recitation] Processing timed out after 30s');
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Processing timed out. Please try again."),
              backgroundColor: AppColors.incorrect,
            ),
          );
        }
      });
    } catch (e) {
      debugPrint("Error stopping record: $e");
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
    }
  }

  /// Cancel recording without sending (e.g. on disconnect)
  Future<void> _cancelRecording() async {
    try {
      await _audioRecorder.stop();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
        });
      }
    } catch (_) {}
  }


  // ═══════════════════════════════════════════════════════════════════
  // RESULT HANDLING
  // ═══════════════════════════════════════════════════════════════════

  void _handleVerseResult(VerseInferenceResult result) {
    if (_sessionDone || result.verseIndex != _currentVerseIdx) return;
    if (_currentVerseIdx >= _verses.length) return;

    final verse = _verses[_currentVerseIdx];

    setState(() {
      _isProcessing = false;
      _lastVerseResult = result;
      _resultsByVerse[_currentVerseIdx] = result;

      // 1. Reset word statuses for this verse
      for (final idx in verse.wordIndices) {
        _statuses[idx] = WordStatus.pending;
      }

      // 2. Color each word based on results
      for (int i = 0;
          i < result.wordResults.length && i < verse.wordIndices.length;
          i++) {
        final wordIdx = verse.wordIndices[i];
        final wr = result.wordResults[i];

        _statuses[wordIdx] =
            wr.isCorrect ? WordStatus.correct : WordStatus.incorrect;
      }

      // Add evaluated Tajweed rules
      for (final rule in result.rulesInAyah) {
        if (!_evaluatedRules.contains(rule)) {
          _evaluatedRules.add(rule);
        }
      }

      // Show tajweed tip for first error
      final firstError = result.wordResults
          .where((w) => !w.isCorrect && w.tajweedTip != null)
          .toList();
      _currentTajweedTip =
          firstError.isNotEmpty ? firstError.first.tajweedTip : null;
    });

    // Don't auto-advance — let user see the green/red coloring and decide
    // when to move on by tapping "Next Verse" or mic again.
  }

  void _checkAndNavigatePage() {
    if (_verses.isEmpty || _currentVerseIdx >= _verses.length) return;
    final activeVerse = _verses[_currentVerseIdx];
    final targetPageIdx = _ayahToPageIdx[activeVerse.ayahNumber] ?? 0;
    if (targetPageIdx != _currentPageIdx) {
      setState(() {
        _currentPageIdx = targetPageIdx;
      });
      _pageController.animateToPage(
        targetPageIdx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }



  /// Advance to next verse (skip or after processing)
  void _nextVerse() {
    if (_isRecording) {
      _cancelRecording();
    }
    if (_currentVerseIdx < _verses.length - 1) {
      setState(() {
        _currentVerseIdx++;
        _currentTajweedTip = null;
        _lastVerseResult = null;
      });
      _scrollToActiveVerse();
    } else {
      _endSession();
    }
  }

  void _prevVerse() {
    if (_isRecording) {
      _cancelRecording();
    }
    if (_currentVerseIdx > 0) {
      setState(() {
        _currentVerseIdx--;
        _currentTajweedTip = null;
        _lastVerseResult = null;
      });
      _scrollToActiveVerse();
    }
  }

  void _selectVerse(int index) {
    if (_isRecording) {
      _cancelRecording();
    }
    setState(() {
      _currentVerseIdx = index;
      _currentTajweedTip = null;
      _lastVerseResult = null;
    });
    _scrollToActiveVerse();
  }

  Future<void> _saveCurrentSession() async {
    if (_isSessionSaved) return;

    int correct = 0;
    int total = 0;
    final Set<int> ayahsPracticed = {};

    for (final entry in _resultsByVerse.entries) {
      final verseIdx = entry.key;
      final result = entry.value;
      final verse = _verses[verseIdx];
      ayahsPracticed.add(verse.ayahNumber);

      for (int i = 0; i < result.wordResults.length && i < verse.wordIndices.length; i++) {
        total++;
        if (result.wordResults[i].isCorrect) {
          correct++;
        }
      }
    }

    if (total == 0) return; // nothing was actually recited — don't save an empty session

    await HiveStorage.saveSession(
      surahNum: currentSurah,
      correctCount: correct,
      totalWords: total,
      ayahs: ayahsPracticed.toList()..sort(),
    );

    _isSessionSaved = true;
  }

  /// End session — mark done but DON'T navigate. User taps "Check Results".
  Future<void> _endSession() async {
    await _cancelRecording();
    setState(() => _sessionDone = true);

    try {
      await _engine.endSession();
    } catch (e) {
      debugPrint('Error ending session: $e');
    }

    await _saveCurrentSession();
  }

  /// Navigate to the results screen
  void _viewResults() {
    if (_resultsByVerse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please recite at least one verse to view correction.'),
          backgroundColor: AppColors.gold,
        ),
      );
      return;
    }

    final List<WordResult> wordResults = [];
    int correct = 0;
    int wrong = 0;

    for (final entry in _resultsByVerse.entries) {
      final verseIdx = entry.key;
      final result = entry.value;
      final verse = _verses[verseIdx];

      for (int i = 0; i < result.wordResults.length && i < verse.wordIndices.length; i++) {
        final wordIdx = verse.wordIndices[i];
        final wr = result.wordResults[i];
        wordResults.add(WordResult(
          arabic: _allWords[wordIdx].arabic,
          spokenText: wr.spokenText,
          isCorrect: wr.isCorrect,
          errorType: wr.errorType,
          tajweedTip: wr.tajweedTip,
          confidence: wr.confidence,
          rules: wr.rules,
          ayahNumber: verse.ayahNumber,
        ));
        if (wr.isCorrect) {
          correct++;
        } else {
          wrong++;
        }
      }
    }

    final List<Map<String, dynamic>> versesData = _verses.map((v) => {
      'ayahNumber': v.ayahNumber,
      'wordIndices': v.wordIndices,
    }).toList();

    context.push(
      '/recitation/results',
      extra: {
        'surahNum': currentSurah,
        'resultsByVerse': Map<int, VerseInferenceResult>.from(_resultsByVerse),
        'audioPathsByVerse': Map<int, String>.from(_audioPathsByVerse),
        'versesData': versesData,
        'allWords': List<AyahWord>.from(_allWords),
        // Fallbacks for backward compatibility
        'ayahNum': currentAyah,
        'wordResults': wordResults,
        'correctCount': correct,
        'wrongCount': wrong,
        'totalWords': wordResults.length,
        'audioPath': _latestAudioPath,
        'rulesInAyah': List<String>.from(_evaluatedRules),
        'userTranscription': _lastVerseResult?.transcription,
      },
    );
  }

  void _reset() async {
    await _cancelRecording();
    setState(() {
      _statuses = List.filled(_allWords.length, WordStatus.pending);
      _currentVerseIdx = 0;
      _currentPageIdx = 0;
      _sessionDone = false;
      _currentTajweedTip = null;
      _lastVerseResult = null;
      _isProcessing = false;
      _evaluatedRules.clear();
      _resultsByVerse.clear();
      _audioPathsByVerse.clear();
      _isSessionSaved = false;
      _latestAudioPath = null;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    final token =
        await ref.read(authProvider.notifier).getFreshToken() ?? '';
    await _engine.dispose();
    _engine = WebSocketInferenceEngine();

    _verseResultSub?.cancel();
    _connectionSub?.cancel();
    _verseResultSub = _engine.verseResults.listen((result) {
      if (mounted) _handleVerseResult(result);
    });
    _connectionSub = _engine.connectionStates.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });

    await _engine.initialize(token);
    final wordMaps = List.generate(_allWords.length, (i) => {
      'index': i,
      'arabic': _allWords[i].arabic,
      'phonetic': _allWords[i].phonetic,
    });
    await _engine.startSession(currentSurah, currentAyah, wordMaps);
  }

  // ═══════════════════════════════════════════════════════════════════
  // REFERENCE AUDIO — plays current verse
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _playReferenceAudio({int? verseIdx}) async {
    try {
      final idx = verseIdx ?? _currentVerseIdx;
      int verseNum = 1;
      if (idx < _verses.length) {
        verseNum = _verses[idx].ayahNumber;
      }
      String sNum = currentSurah.toString().padLeft(3, '0');
      String aNum = verseNum.toString().padLeft(3, '0');
      String url =
          "https://everyayah.com/data/Alafasy_128kbps/$sNum$aNum.mp3";
      await _audioPlayer.setUrl(url);
      _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not play audio: $e")),
        );
      }
    }
  }

  void _toggleRecordingForVerse(int index) {
    if (_sessionDone || _isProcessing) return;
    if (_currentVerseIdx != index) {
      _selectVerse(index);
    }
    _toggleRecording();
  }

  void _playReferenceAudioForVerse(int index) {
    _playReferenceAudio(verseIdx: index);
  }

  void _scrollToActiveVerse() {
    if (!_scrollController.hasClients) return;
    final double targetOffset = _currentVerseIdx * 150.0;
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double clampedOffset = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }


  List<Widget> _buildWordWidgetsForVerse(_VerseInfo verse) {
    final verseIdx = _verses.indexOf(verse);
    final isCurrentVerse = verseIdx == _currentVerseIdx && !_sessionDone;

    final isHidden = _isHafizMode &&
        (verseIdx > _currentVerseIdx || (verseIdx == _currentVerseIdx && _resultsByVerse[verseIdx] == null));

    final List<Widget> widgets = [];

    if (isHidden) {
      for (int i = 0; i < verse.wordIndices.length; i++) {
        final isRecordingThis = isCurrentVerse && _isRecording;
        widgets.add(
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                width: 50,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isRecordingThis
                        ? AppColors.gold.withOpacity(0.3 + 0.4 * _pulseCtrl.value)
                        : AppColors.textLight.withOpacity(0.06),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (isRecordingThis)
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.05 * _pulseCtrl.value),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                  ],
                ),
                child: const Center(
                  child: Text(
                    '•••',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }
    } else {
      for (int i = 0; i < verse.wordIndices.length; i++) {
        final flatWordIdx = verse.wordIndices[i];
        final word = _allWords[flatWordIdx];
        final status = _statuses[flatWordIdx];

        Color? bgColor;
        Border? border;

        if (status == WordStatus.correct) {
          bgColor = AppColors.correct.withOpacity(0.12);
          border = Border.all(color: AppColors.correct.withOpacity(0.3), width: 1);
        } else if (status == WordStatus.incorrect) {
          bgColor = AppColors.incorrect.withOpacity(0.12);
          border = Border.all(color: AppColors.incorrect.withOpacity(0.4), width: 1.5);
        } else if (isCurrentVerse) {
          bgColor = Colors.transparent;
          border = Border.all(color: AppColors.gold.withOpacity(0.2), width: 1);
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
    final surah = QuranDataService.surahMap[currentSurah] ??
        QuranDataService.surahs.first;

    String verseLabel = '';
    if (_verses.isNotEmpty && _currentVerseIdx < _verses.length) {
      verseLabel =
          'Verse ${_verses[_currentVerseIdx].ayahNumber} of ${_verses.length}';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textLight),
          onPressed: () => context.go('/quran/$currentSurah'),
        ),
        title: Text(surah.nameEnglish,
            style: AppText.heading2(color: AppColors.textLight)),
        actions: [
          if (_connectionState != WsConnectionState.connected)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_connectionState == WsConnectionState.reconnecting)
                    Text('Reconnecting...',
                        style: AppText.caption(color: AppColors.gold)),
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: AppColors.gold, strokeWidth: 2),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: Icon(
              _isHafizMode ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: _isHafizMode ? AppColors.gold : AppColors.textLight,
            ),
            tooltip: 'Hafiz Mode Toggle',
            onPressed: () {
              setState(() {
                _isHafizMode = !_isHafizMode;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppColors.textLight),
            onPressed: _reset,
          ),
          TextButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text('End Recitation?', style: TextStyle(color: AppColors.textLight)),
                  content: Text('Do you want to save your progress and finish this recitation session?', style: TextStyle(color: AppColors.textMuted)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('End & Save', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _endSession();
                if (context.mounted) {
                  context.go('/home');
                }
              }
            },
            icon: Icon(Icons.check_circle_outline_rounded, color: AppColors.emerald, size: 18),
            label: Text('Finish', style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(verseLabel,
                      style: AppText.caption(color: AppColors.textLight.withOpacity(0.7))),
                  Text(surah.nameArabic,
                      style: AppText.arabicMedium.copyWith(color: AppColors.gold, fontSize: 18)),
                  Text('${surah.revelationType} • ${surah.verses} Verses',
                      style: AppText.caption(color: AppColors.textLight.withOpacity(0.7))),
                ],
              ),
            ),
            Expanded(
              child: _allWords.isEmpty || _verses.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _verses.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemBuilder: (context, index) {
                        final verse = _verses[index];
                        final isCurrent = index == _currentVerseIdx;
                        final result = _resultsByVerse[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: isCurrent ? AppColors.gold : AppColors.gold.withOpacity(0.12),
                              width: isCurrent ? 2 : 1,
                            ),
                          ),
                          elevation: isCurrent ? 4 : 2,
                          child: InkWell(
                            onTap: () => _selectVerse(index),
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isCurrent ? AppColors.gold : AppColors.gold.withOpacity(0.15),
                                        child: Text(
                                          _toArabicNumerals(verse.ayahNumber),
                                          style: TextStyle(
                                            color: isCurrent ? Colors.black : AppColors.gold,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (result != null)
                                            Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: (result.accuracy >= 80 ? AppColors.correct : AppColors.gold).withOpacity(0.12),
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
                                          IconButton(
                                            icon: Icon(
                                              isCurrent && _isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                                              color: isCurrent && _isRecording ? AppColors.incorrect : (isCurrent ? AppColors.gold : AppColors.textMuted),
                                            ),
                                            onPressed: () => _toggleRecordingForVerse(index),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.volume_up_rounded, color: AppColors.gold),
                                            onPressed: () => _playReferenceAudioForVerse(index),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    textDirection: TextDirection.rtl,
                                    alignment: WrapAlignment.start,
                                    spacing: 4,
                                    runSpacing: 8,
                                    children: _buildWordWidgetsForVerse(verse),
                                  ),
                                  if (_isProcessing && isCurrent) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: AppColors.gold.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              color: AppColors.gold,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Analyzing recitation...',
                                            style: AppText.body(color: AppColors.gold).copyWith(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.textLight.withOpacity(0.1))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_sessionDone) ...[
              Text(
                _isProcessing
                    ? 'Processing...'
                    : _isRecording
                        ? 'Recording verse — tap stop when done'
                        : 'Tap mic on a verse card & recite',
                style: AppText.caption(
                    color: _isRecording
                        ? AppColors.incorrect
                        : _isProcessing
                            ? AppColors.gold
                            : AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundBtn(
                    icon: Icons.skip_previous_rounded,
                    color: AppColors.textMuted,
                    onTap: _prevVerse,
                  ),
                  _RoundBtn(
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.emerald,
                    onTap: () => _playReferenceAudio(verseIdx: _currentVerseIdx),
                  ),
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => GestureDetector(
                      onTap: (_sessionDone || _isProcessing) ? null : _toggleRecording,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isProcessing
                              ? AppColors.textMuted
                              : _isRecording
                                  ? AppColors.incorrect
                                  : AppColors.gold,
                          boxShadow: [
                            if (!_isProcessing)
                              BoxShadow(
                                color: (_isRecording ? AppColors.incorrect : AppColors.gold)
                                    .withOpacity(0.35 + _pulseCtrl.value * 0.15),
                                blurRadius: 20 + _pulseCtrl.value * 8,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: _isProcessing
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: AppColors.textLight,
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                                color: AppColors.primary,
                                size: 32,
                              ),
                      ),
                    ),
                  ),
                  _RoundBtn(
                    icon: Icons.skip_next_rounded,
                    color: AppColors.textMuted,
                    onTap: _nextVerse,
                  ),
                  ElevatedButton.icon(
                    onPressed: _viewResults,
                    icon: const Icon(Icons.assessment_rounded),
                    label: const Text('Correction'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.correct.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(Dims.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: AppColors.correct, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Perfect recitation! All words were pronounced correctly.',
                        style: AppText.body(color: AppColors.textLight),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.caption(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppText.heading1(color: color).copyWith(fontSize: 22),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      );
}
