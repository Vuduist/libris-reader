import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/reader_models.dart';
import '../services/tts_service.dart';
import 'reader_cubit.dart';
import 'settings_cubit.dart';

enum TtsStatus { off, playing, paused }

class TtsState extends Equatable {
  final TtsStatus status;
  final int chapterIndex; // глава озвучки
  final int blockIndex; // подсвечиваемый блок (-1 = нет)
  final int itemIndex; // позиция в очереди главы (0-based)
  final int itemCount; // длина очереди главы
  final double speed;
  final String? voiceName;
  final int sleepMinutes; // 0 = выкл
  final String? error;

  const TtsState({
    this.status = TtsStatus.off,
    this.chapterIndex = 0,
    this.blockIndex = -1,
    this.itemIndex = 0,
    this.itemCount = 0,
    this.speed = 1.0,
    this.voiceName,
    this.sleepMinutes = 0,
    this.error,
  });

  bool get active => status != TtsStatus.off;

  TtsState copyWith({
    TtsStatus? status,
    int? chapterIndex,
    int? blockIndex,
    int? itemIndex,
    int? itemCount,
    double? speed,
    String? Function()? voiceName,
    int? sleepMinutes,
    String? Function()? error,
  }) =>
      TtsState(
        status: status ?? this.status,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        blockIndex: blockIndex ?? this.blockIndex,
        itemIndex: itemIndex ?? this.itemIndex,
        itemCount: itemCount ?? this.itemCount,
        speed: speed ?? this.speed,
        voiceName: voiceName != null ? voiceName() : this.voiceName,
        sleepMinutes: sleepMinutes ?? this.sleepMinutes,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props => [
        status,
        chapterIndex,
        blockIndex,
        itemIndex,
        itemCount,
        speed,
        voiceName,
        sleepMinutes,
        error,
      ];
}

class _TtsItem {
  final int blockIndex;
  final String text;

  const _TtsItem(this.blockIndex, this.text);
}

class TtsCubit extends Cubit<TtsState> {
  final TtsService _tts;
  final SettingsCubit _settings;
  final ReaderCubit _reader;

  List<TtsVoice> availableVoices = const [];

  List<_TtsItem> _queue = const [];
  int _generation = 0;
  int _consecutiveErrors = 0;
  Timer? _sleepTimer;

  TtsCubit(this._tts, this._settings, this._reader)
      : super(TtsState(
          speed: _settings.state.ttsSpeed,
          voiceName: _settings.state.ttsVoice,
        ));

  // ---- построение очереди ----

  List<_TtsItem> _buildQueue(ReaderChapter chapter) {
    final out = <_TtsItem>[];
    for (var i = 0; i < chapter.blocks.length; i++) {
      final block = chapter.blocks[i];
      switch (block.type) {
        case BlockType.h1:
        case BlockType.h2:
        case BlockType.h3:
        case BlockType.paragraph:
        case BlockType.epigraph:
          final text = block.plainText.trim();
          if (text.isEmpty) continue;
          for (final part in TtsService.splitForTts(text)) {
            out.add(_TtsItem(i, part));
          }
          break;
        case BlockType.image:
        case BlockType.spacer:
          break;
      }
    }
    return out;
  }

  String _languageFor(ReaderChapter chapter) {
    final buf = StringBuffer();
    for (final b in chapter.blocks) {
      buf.write(b.plainText);
      if (buf.length > 2000) break;
    }
    return RegExp(r'[а-яА-ЯёЁ]').hasMatch(buf.toString())
        ? 'ru-RU'
        : 'en-US';
  }

  // ---- управление режимом ----

  Future<void> start() async {
    if (state.status != TtsStatus.off) return;
    final chapter = _reader.state.currentChapter;
    if (chapter == null) return;
    emit(state.copyWith(error: () => null));
    if (!await _tts.engineAvailable()) {
      emit(state.copyWith(
          error: () =>
              'Синтез речи недоступен: на устройстве нет TTS-движка'));
      return;
    }
    // голоса
    availableVoices = await _tts.voices();
    var voiceName = _settings.state.ttsVoice;
    if (voiceName == null && availableVoices.isNotEmpty) {
      voiceName = availableVoices.first.name;
    }
    final voice = availableVoices.where((v) => v.name == voiceName).firstOrNull;
    if (voice != null) await _tts.setVoice(voice);
    await _tts.setRate(state.speed);
    _startSleepTimerIfNeeded();
    _prepareChapter(_reader.state.chapterIndex, voiceName: voiceName);
    _playFrom(0);
  }

  void _prepareChapter(int chapterIndex, {String? voiceName}) {
    final book = _reader.state.book;
    if (book == null || chapterIndex >= book.chapters.length) return;
    final chapter = book.chapters[chapterIndex];
    _queue = _buildQueue(chapter);
    _tts.setLanguage(_languageFor(chapter));
    emit(state.copyWith(
      status: TtsStatus.playing,
      chapterIndex: chapterIndex,
      blockIndex: -1,
      itemIndex: 0,
      itemCount: _queue.length,
      voiceName: () => voiceName ?? state.voiceName,
    ));
  }

  void _playFrom(int itemIndex) {
    final generation = ++_generation;
    emit(state.copyWith(status: TtsStatus.playing));
    _loop(generation, itemIndex);
  }

  Future<void> _loop(int generation, int startIndex) async {
    var i = startIndex;
    while (generation == _generation && state.status == TtsStatus.playing) {
      if (i >= _queue.length) {
        // конец главы → следующая, если есть
        final book = _reader.state.book;
        final next = state.chapterIndex + 1;
        if (book == null || next >= book.chapters.length) {
          await stop();
          return;
        }
        _reader.goToChapter(next);
        _prepareChapter(next);
        i = 0;
        continue;
      }
      final item = _queue[i];
      emit(state.copyWith(itemIndex: i, blockIndex: item.blockIndex));
      try {
        await _tts.speak(item.text);
        _consecutiveErrors = 0;
      } catch (e) {
        if (generation != _generation) return;
        _consecutiveErrors++;
        if (_consecutiveErrors >= 3) {
          emit(state.copyWith(
              error: () =>
                  'Синтез речи не удался: $e. Проверьте голосовые данные TTS на устройстве.'));
          await stop();
          return;
        }
        emit(state.copyWith(error: () => 'Ошибка синтеза речи: $e'));
      }
      if (generation != _generation || state.status != TtsStatus.playing) {
        return;
      }
      i++;
    }
  }

  Future<void> pause() async {
    if (state.status != TtsStatus.playing) return;
    _generation++; // останавливаем цикл после текущего await
    await _tts.stop();
    emit(state.copyWith(status: TtsStatus.paused));
  }

  Future<void> resume() async {
    if (state.status != TtsStatus.paused) return;
    _playFrom(state.itemIndex);
  }

  Future<void> togglePlay() async =>
      state.status == TtsStatus.playing ? pause() : resume();

  /// Полный выход из режима озвучки.
  Future<void> stop() async {
    if (state.status == TtsStatus.off) return;
    _generation++;
    _sleepTimer?.cancel();
    await _tts.stop();
    emit(state.copyWith(status: TtsStatus.off, blockIndex: -1));
    // фиксируем позицию чтения на месте, которое дослушали
    await _reader.saveProgress();
  }

  Future<void> nextParagraph() => _skip(1);
  Future<void> prevParagraph() => _skip(-1);

  Future<void> _skip(int delta) async {
    if (!state.active) return;
    var index = state.itemIndex + delta;
    if (index < 0) index = 0;
    if (index >= _queue.length) index = _queue.length - 1;
    await _tts.stop();
    _playFrom(index);
  }

  /// Пользователь сам сменил главу (стрелки/содержание) во время озвучки.
  void followUserChapter(int readerChapterIndex) {
    if (!state.active) return;
    if (readerChapterIndex == state.chapterIndex) return;
    _generation++;
    _tts.stop();
    _prepareChapter(readerChapterIndex);
    _playFrom(0);
  }

  // ---- настройки ----

  Future<void> setSpeed(double speed) async {
    _settings.setTtsSpeed(speed);
    final s = _settings.state.ttsSpeed;
    await _tts.setRate(s);
    emit(state.copyWith(speed: s));
    // во время воспроизведения — перечитать текущий абзац с новой скоростью
    if (state.status == TtsStatus.playing) {
      await _tts.stop();
      _playFrom(state.itemIndex);
    }
  }

  Future<void> setVoice(TtsVoice? voice) async {
    _settings.setTtsVoice(voice?.name);
    if (voice != null) await _tts.setVoice(voice);
    emit(state.copyWith(voiceName: () => voice?.name));
  }

  void setSleepTimer(int minutes) {
    emit(state.copyWith(sleepMinutes: minutes));
    _startSleepTimerIfNeeded();
  }

  void _startSleepTimerIfNeeded() {
    _sleepTimer?.cancel();
    final minutes = state.sleepMinutes;
    if (minutes > 0 && state.active) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        stop();
      });
    }
  }

  void clearError() => emit(state.copyWith(error: () => null));

  @override
  Future<void> close() async {
    _generation++;
    _sleepTimer?.cancel();
    await _tts.dispose();
    return super.close();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
