import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class TtsVoice {
  final String name;
  final String locale;

  const TtsVoice(this.name, this.locale);

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  @override
  String toString() => '$name ($locale)';
}

/// Обёртка над flutter_tts: инициализация, язык, скорость, голоса.
class TtsService {
  FlutterTts? _tts;
  bool _initialized = false;
  double _rate = 0.8;
  final _errorController = StreamController<String>.broadcast();

  /// Ошибки синтеза (setErrorHandler) — speak() завершается ими тоже.
  Stream<String> get errors => _errorController.stream;

  /// Максимальная длина одного utterance (Android TTS падает на длинных).
  static const maxUtteranceLength = 3000;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    final tts = FlutterTts();
    tts.setErrorHandler((msg) {
      _errorController.add(msg?.toString() ?? 'unknown TTS error');
    });
    await tts.awaitSpeakCompletion(true);
    await tts.setVolume(1.0);
    _tts = tts;
    _initialized = true;
  }

  Future<void> dispose() async {
    try {
      await _tts?.stop();
    } catch (_) {}
    _initialized = false;
    _tts = null;
  }

  Future<void> setLanguage(String language) async {
    await _ensureInit();
    try {
      await _tts!.setLanguage(language);
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    await _ensureInit();
    try {
      await _tts!.setSpeechRate(rate);
    } catch (_) {}
  }

  Future<void> setVoice(TtsVoice voice) async {
    await _ensureInit();
    try {
      await _tts!.setVoice(voice.toMap());
    } catch (_) {}
  }

  /// true, если есть хотя бы один TTS-движок.
  Future<bool> engineAvailable() async {
    await _ensureInit();
    try {
      final engines = await _tts!.getEngines;
      return engines is List && engines.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Голоса: сначала русские, если их нет — все доступные.
  Future<List<TtsVoice>> voices() async {
    await _ensureInit();
    final out = <TtsVoice>[];
    try {
      final raw = await _tts!.getVoices;
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = v['name']?.toString() ?? '';
            final locale = v['locale']?.toString() ?? '';
            if (name.isNotEmpty) out.add(TtsVoice(name, locale));
          }
        }
      }
    } catch (_) {}
    final ru = out
        .where((v) => v.locale.toLowerCase().startsWith('ru'))
        .toList();
    return ru.isNotEmpty ? ru : out;
  }

  Future<bool> languageAvailable(String language) async {
    await _ensureInit();
    try {
      final res = await _tts!.isLanguageAvailable(language);
      return res == 1 || res == true;
    } catch (_) {
      return false;
    }
  }

  /// Озвучить текст; future завершается по окончании utterance.
  /// При ошибке синтеза бросает [TtsException]; сторожевой таймаут —
  /// на случай, если движок завис и не прислал ни completion, ни error.
  Future<void> speak(String text) async {
    await _ensureInit();
    // Движки Android читают speechRate в момент speak() — задаём каждый раз.
    try {
      await _tts!.setSpeechRate(_rate);
    } catch (_) {}
    final timeout = Duration(
        seconds: 20 + (text.length / 10).ceil().clamp(0, 120));
    await Future.any([
      _tts!.speak(text),
      _errorController.stream.first
          .then((msg) => throw TtsException(msg)),
    ]).timeout(timeout, onTimeout: () {
      throw TtsException('TTS не отвечает (таймаут)');
    });
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _tts!.stop();
    } catch (_) {}
  }

  /// Делит длинный абзац на куски по предложениям (≤ [maxUtteranceLength]).
  static List<String> splitForTts(String text) {
    final t = text.trim();
    if (t.length <= maxUtteranceLength) return [t];
    final parts = <String>[];
    final sentenceEnd = RegExp(r'(?<=[.!?…])\s+');
    final sentences = t.split(sentenceEnd);
    final buf = StringBuffer();
    void flush() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) parts.add(s);
      buf.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxUtteranceLength) {
        flush();
        // режем принудительно по пробелам
        var rest = sentence;
        while (rest.length > maxUtteranceLength) {
          var cut = rest.lastIndexOf(' ', maxUtteranceLength);
          if (cut < maxUtteranceLength ~/ 2) cut = maxUtteranceLength;
          parts.add(rest.substring(0, cut).trim());
          rest = rest.substring(cut).trimLeft();
        }
        if (rest.isNotEmpty) buf.write(rest);
        continue;
      }
      if (buf.length + sentence.length + 1 > maxUtteranceLength) flush();
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(sentence);
    }
    flush();
    return parts;
  }
}

class TtsException implements Exception {
  final String message;
  TtsException(this.message);
  @override
  String toString() => message;
}
