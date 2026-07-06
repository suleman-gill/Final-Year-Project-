import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/network/api_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// RESULT MODELS
// ═══════════════════════════════════════════════════════════════════════

class WordInferenceResult {
  final bool isCorrect;
  final String spokenText;
  final double confidence;
  final String? tajweedTip;
  final String? errorType;
  final String? correctedArabic;
  final int? wordIndex;
  final int? ayahNumber; // populated by the screen after receiving results
  final List<String> rules;

  WordInferenceResult({
    required this.isCorrect,
    required this.spokenText,
    required this.confidence,
    this.tajweedTip,
    this.errorType,
    this.correctedArabic,
    this.wordIndex,
    this.ayahNumber,
    required this.rules,
  });

  factory WordInferenceResult.fromJson(Map<String, dynamic> json) {
    return WordInferenceResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      spokenText: json['spokenText'] as String? ?? '',
      confidence: (json['confidence'] as num? ?? 0.0).toDouble(),
      tajweedTip: json['tajweedTip'] as String?,
      errorType: json['errorType'] as String?,
      correctedArabic: json['correctedArabic'] as String?,
      wordIndex: json['wordIndex'] as int?,
      ayahNumber: json['ayahNumber'] as int?,
      rules: (json['rules'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }
}

class VerseInferenceResult {
  final int verseIndex;
  final List<WordInferenceResult> wordResults;
  final String transcription;
  final double accuracy;
  final List<String> rulesInAyah;

  VerseInferenceResult({
    required this.verseIndex,
    required this.wordResults,
    required this.transcription,
    required this.accuracy,
    required this.rulesInAyah,
  });

  factory VerseInferenceResult.fromJson(Map<String, dynamic> json) {
    final wrs = (json['wordResults'] as List? ?? [])
        .map((w) => WordInferenceResult.fromJson(w as Map<String, dynamic>))
        .toList();
    final rules = (json['rulesInAyah'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return VerseInferenceResult(
      verseIndex: json['verseIndex'] as int? ?? 0,
      wordResults: wrs,
      transcription: json['transcription'] as String? ?? '',
      accuracy: (json['accuracy'] as num? ?? 0.0).toDouble(),
      rulesInAyah: rules,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONNECTION STATE MACHINE
// ═══════════════════════════════════════════════════════════════════════

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

// ═══════════════════════════════════════════════════════════════════════
// INTERFACE DEFINITION
// ═══════════════════════════════════════════════════════════════════════

abstract class RecitationInferenceEngine {
  Stream<WordInferenceResult> get wordResults;
  Stream<VerseInferenceResult> get verseResults;
  Stream<WsConnectionState> get connectionStates;

  Future<void> initialize(String token);
  Future<void> startSession(
      int surahNum, int ayahNum, List<Map<String, dynamic>> words);
  Future<WordInferenceResult> processAudio(
      String audioBase64, int wordIndex, String arabic);
  void sendAudioChunk(String audioBase64, int wordIndex);
  void sendVerseAudio(
      String audioBase64, int verseIndex, List<String> expectedWords);
  Future<Map<String, dynamic>> endSession();
  Future<void> dispose();
}

// ═══════════════════════════════════════════════════════════════════════
// WEBSOCKET IMPLEMENTATION — With Exponential Backoff Reconnect
// ═══════════════════════════════════════════════════════════════════════

class WebSocketInferenceEngine implements RecitationInferenceEngine {
  WebSocketChannel? _channel;
  String? _sessionId;
  String? _token;
  Completer<WordInferenceResult>? _resultCompleter;
  Completer<Map<String, dynamic>>? _sessionCompleter;
  Completer<void>? _startSessionCompleter;
  StreamSubscription? _channelSubscription;

  final _wordResultsController =
      StreamController<WordInferenceResult>.broadcast();
  final _verseResultsController =
      StreamController<VerseInferenceResult>.broadcast();
  final _connectionStateController =
      StreamController<WsConnectionState>.broadcast();

  // ── Reconnect state ────────────────────────────────────────────────
  static const int _maxReconnectAttempts = 3;
  int _reconnectAttempt = 0;
  bool _isDisposing = false;

  // ── Duplicate word guard ───────────────────────────────────────────
  int _lastProcessedWordIndex = -1;
  int _currentWordIndex = 0;

  // ── Session context (preserved across reconnections) ───────────────
  int? _lastSurahNum;
  int? _lastAyahNum;
  List<Map<String, dynamic>>? _lastWords;

  @override
  Stream<WordInferenceResult> get wordResults => _wordResultsController.stream;

  @override
  Stream<VerseInferenceResult> get verseResults =>
      _verseResultsController.stream;

  @override
  Stream<WsConnectionState> get connectionStates =>
      _connectionStateController.stream;

  String get _wsUrl {
    final uri = Uri.parse(backendBaseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.authority}/ws/recitation';
  }

  @override
  Future<void> initialize(String token) async {
    _token = token;
    _isDisposing = false;
    _reconnectAttempt = 0;
    await _connect();
  }

  Future<void> _connect() async {
    if (_isDisposing) return;
    if (_token == null) return;

    _connectionStateController.add(WsConnectionState.connecting);

    try {
      final wsUrl = _wsUrl;
      debugPrint('[Recitation] Connecting to WebSocket: $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for the WebSocket handshake to fully complete before doing anything
      await _channel!.ready;

      await _channelSubscription?.cancel();
      _channelSubscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Send auth as first message — backend expects this before any other message
      _channel!.sink.add(jsonEncode({
        'type': 'auth',
        'token': _token,
      }));

      _reconnectAttempt = 0;
      _connectionStateController.add(WsConnectionState.connected);
      debugPrint('[WS Client] Connected and authenticated');
    } catch (e) {
      debugPrint('[WS Client] Connection failed: $e');
      _connectionStateController.add(WsConnectionState.disconnected);
      _attemptReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'session_ready') {
        _sessionId = msg['sessionId'] as String?;
        debugPrint("[WS Client] Session ready: $_sessionId");
        if (_startSessionCompleter != null &&
            !_startSessionCompleter!.isCompleted) {
          _startSessionCompleter!.complete();
        }
      } else if (type == 'word_result') {
        final result = WordInferenceResult.fromJson(msg);
        if (result.wordIndex != null) {
          _lastProcessedWordIndex = result.wordIndex!;
        }
        _wordResultsController.add(result);
        if (_resultCompleter != null && !_resultCompleter!.isCompleted) {
          _resultCompleter!.complete(result);
        }
      } else if (type == 'verse_result') {
        final result = VerseInferenceResult.fromJson(msg);
        debugPrint(
            "[WS Client] Verse result: idx=${result.verseIndex}, "
            "accuracy=${result.accuracy}%, words=${result.wordResults.length}");
        _verseResultsController.add(result);
      } else if (type == 'session_complete') {
        if (_sessionCompleter != null && !_sessionCompleter!.isCompleted) {
          _sessionCompleter!
              .complete(msg['summary'] as Map<String, dynamic>);
        }
      } else if (type == 'error') {
        debugPrint("[WS Client] Server error: ${msg['message']}");
      }
    } catch (e) {
      debugPrint("[WS Client] Error parsing message: $e");
    }
  }

  void _onError(dynamic err) {
    debugPrint("[WS Client] Connection Error: $err");
    _connectionStateController.add(WsConnectionState.disconnected);
    _attemptReconnect();
  }

  void _onDone() {
    debugPrint("[WS Client] Connection Closed");
    if (!_isDisposing) {
      _connectionStateController.add(WsConnectionState.disconnected);
      _attemptReconnect();
    }
  }

  // ── Exponential Backoff Reconnect ──────────────────────────────────

  Future<void> _attemptReconnect() async {
    if (_isDisposing) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      debugPrint(
          "[WS Client] Max reconnect attempts reached ($_maxReconnectAttempts). Giving up.");
      _connectionStateController.add(WsConnectionState.disconnected);
      return;
    }

    _reconnectAttempt++;
    final delay = Duration(seconds: 1 << (_reconnectAttempt - 1));
    debugPrint(
        "[WS Client] Reconnect attempt $_reconnectAttempt/$_maxReconnectAttempts "
        "in ${delay.inSeconds}s...");
    _connectionStateController.add(WsConnectionState.reconnecting);

    await Future.delayed(delay);

    if (_isDisposing) return;

    await _connect();

    // Re-establish session context if we had one
    if (_sessionId != null &&
        _lastSurahNum != null &&
        _lastAyahNum != null &&
        _lastWords != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_lastWords != null) {
        final remaining = _lastWords!
            .where((w) => (w['index'] as int) >= _currentWordIndex)
            .toList();
        await startSession(_lastSurahNum!, _lastAyahNum!, remaining);
      }
    }
  }

  @override
  Future<void> startSession(
      int surahNum, int ayahNum, List<Map<String, dynamic>> words) async {
    if (_channel == null) return;

    _lastSurahNum = surahNum;
    _lastAyahNum = ayahNum;
    _lastWords = words;
    _lastProcessedWordIndex = -1;

    _startSessionCompleter = Completer<void>();

    _channel!.sink.add(jsonEncode({
      'type': 'start_session',
      'surahNum': surahNum,
      'ayahNum': ayahNum,
      'words': words,
    }));

    try {
      await _startSessionCompleter!.future
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("[WS Client] Error starting session: $e");
    }
  }

  @override
  Future<WordInferenceResult> processAudio(
      String audioBase64, int wordIndex, String arabic) async {
    if (_channel == null || _sessionId == null) {
      throw Exception("WebSocket session not started.");
    }

    _resultCompleter = Completer<WordInferenceResult>();

    _channel!.sink.add(jsonEncode({
      'type': 'audio_chunk',
      'sessionId': _sessionId,
      'wordIndex': wordIndex,
      'audioBase64': audioBase64,
    }));

    try {
      return await _resultCompleter!.future
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception("WebSocket timeout waiting for word_result");
    }
  }

  @override
  void sendAudioChunk(String audioBase64, int wordIndex) {
    _currentWordIndex = wordIndex;
    if (_channel == null || _sessionId == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'audio_chunk',
      'sessionId': _sessionId,
      'wordIndex': wordIndex,
      'audioBase64': audioBase64,
    }));
  }

  @override
  void sendVerseAudio(
      String audioBase64, int verseIndex, List<String> expectedWords) {
    if (_channel == null || _sessionId == null) {
      debugPrint("[WS Client] Cannot send verse audio: no session");
      return;
    }

    debugPrint(
        "[WS Client] Sending verse audio: idx=$verseIndex, "
        "words=${expectedWords.length}, "
        "audioLen=${audioBase64.length}");

    _channel!.sink.add(jsonEncode({
      'type': 'verse_audio',
      'sessionId': _sessionId,
      'verseIndex': verseIndex,
      'audioBase64': audioBase64,
      'expectedWords': expectedWords,
    }));
  }

  @override
  Future<Map<String, dynamic>> endSession() async {
    if (_channel == null || _sessionId == null) {
      return {'correct': 0, 'wrong': 0, 'accuracy': 0, 'durationMs': 0};
    }

    _sessionCompleter = Completer<Map<String, dynamic>>();

    _channel!.sink.add(jsonEncode({
      'type': 'end_session',
      'sessionId': _sessionId,
    }));

    try {
      return await _sessionCompleter!.future
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("[WS Client] Session complete timeout: $e");
      return {'correct': 0, 'wrong': 0, 'accuracy': 0, 'durationMs': 0};
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposing = true;
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    if (!_wordResultsController.isClosed) _wordResultsController.close();
    if (!_verseResultsController.isClosed) _verseResultsController.close();
    if (!_connectionStateController.isClosed) {
      _connectionStateController.close();
    }
    _channel = null;
    _sessionId = null;
    _lastSurahNum = null;
    _lastAyahNum = null;
    _lastWords = null;
  }
}
