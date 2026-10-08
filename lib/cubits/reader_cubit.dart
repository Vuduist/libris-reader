import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/settings_cubit.dart';
import '../models/library_models.dart';
import '../models/reader_models.dart';
import '../services/library_storage.dart';
import '../services/reader/book_loader.dart';
import '../ui/reader/paginator.dart';

class ReaderState extends Equatable {
  final bool loading;
  final String? error;
  final ReaderBook? book;
  final int chapterIndex;
  final int pageIndex; // paged-режим
  final double scrollOffset; // scroll-режим
  final ReadingMode mode;
  final double fontSize;
  final int pagesInChapter; // заполняется после пагинации

  const ReaderState({
    this.loading = true,
    this.error,
    this.book,
    this.chapterIndex = 0,
    this.pageIndex = 0,
    this.scrollOffset = 0,
    this.mode = ReadingMode.scroll,
    this.fontSize = 18,
    this.pagesInChapter = 0,
  });

  ReaderChapter? get currentChapter =>
      book == null || book!.chapters.isEmpty ? null : book!.chapters[chapterIndex];

  ReaderState copyWith({
    bool? loading,
    String? Function()? error,
    ReaderBook? book,
    int? chapterIndex,
    int? pageIndex,
    double? scrollOffset,
    ReadingMode? mode,
    double? fontSize,
    int? pagesInChapter,
  }) =>
      ReaderState(
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
        book: book ?? this.book,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        pageIndex: pageIndex ?? this.pageIndex,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        mode: mode ?? this.mode,
        fontSize: fontSize ?? this.fontSize,
        pagesInChapter: pagesInChapter ?? this.pagesInChapter,
      );

  @override
  List<Object?> get props => [
        loading,
        error,
        book,
        chapterIndex,
        pageIndex,
        scrollOffset,
        mode,
        fontSize,
        pagesInChapter
      ];
}

class ReaderCubit extends Cubit<ReaderState> {
  final LibraryStorage _storage;
  final SettingsCubit _settings;
  final BookLoader _loader;
  final LibraryBook libraryBook;

  Timer? _saveTimer;
  int _lastSavedChapter = -1;
  double _lastSavedOffset = -1;
  int _lastSavedPage = -1;

  ReaderCubit(this._storage, this._settings, this.libraryBook,
      {BookLoader? loader})
      : _loader = loader ?? BookLoader(),
        super(ReaderState(
          mode: _settings.state.readingMode,
          fontSize: _settings.state.fontSize,
        ));

  Future<void> open() async {
    try {
      final book = await _loader.load(libraryBook);
      if (book.chapters.isEmpty) {
        emit(state.copyWith(loading: false, error: () => 'Книга пуста'));
        return;
      }
      final chapter =
          libraryBook.progressChapter.clamp(0, book.chapters.length - 1);
      emit(state.copyWith(
        loading: false,
        book: book,
        chapterIndex: chapter,
        pageIndex: libraryBook.progressPage,
        scrollOffset: libraryBook.progressOffset,
      ));
      await _storage.touchOpened(libraryBook.id);
      _startTimer();
    } catch (e) {
      emit(state.copyWith(
          loading: false, error: () => 'Не удалось открыть книгу: $e'));
    }
  }

  void _startTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      saveProgress();
    });
  }

  /// Эпизод навигации: инкрементируется при каждом явном переходе
  /// (глава/TOC/закладка), чтобы UI пересоздал вьюпорт даже при той же главе.
  int navigationEpoch = 0;

  /// Страницы текущей главы в paged-режиме (заполняет вьюпорт после пагинации).
  List<ReaderPageData>? currentPages;

  /// Сниппет для закладки: текст текущей страницы (paged) или начало главы.
  String currentSnippet() {
    final ch = state.currentChapter;
    if (ch == null) return '';
    final pages = currentPages;
    if (state.mode == ReadingMode.paged &&
        pages != null &&
        state.pageIndex < pages.length) {
      final buf = StringBuffer();
      for (final s in pages[state.pageIndex].slices) {
        if (s.isImage) continue;
        final plain = ch.blocks[s.blockIndex].plainText;
        final from = s.start.clamp(0, plain.length);
        final to = s.end.clamp(0, plain.length);
        if (to > from) buf.write(plain.substring(from, to));
      }
      final text = buf.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return ch.firstParagraphText;
  }

  void goToChapter(int index, {int page = 0, double offset = 0}) {
    final book = state.book;
    if (book == null) return;
    final clamped = index.clamp(0, book.chapters.length - 1);
    saveProgress();
    navigationEpoch++;
    emit(state.copyWith(
        chapterIndex: clamped,
        pageIndex: page,
        scrollOffset: offset,
        pagesInChapter: 0));
    _pendingOffset = offset;
    saveProgress();
  }

  void nextChapter() => goToChapter(state.chapterIndex + 1);
  void prevChapter() => goToChapter(state.chapterIndex - 1);

  void setPageIndex(int page) {
    emit(state.copyWith(pageIndex: page));
  }

  void setScrollOffset(double offset) {
    // частые события скролла не эмитим, чтобы не перерисовывать UI
    _pendingOffset = offset;
  }

  double _pendingOffset = -1;

  /// Актуальная позиция скролла (state может отставать).
  double get currentOffset =>
      _pendingOffset >= 0 ? _pendingOffset : state.scrollOffset;

  void setPagesInChapter(int count) {
    if (count != state.pagesInChapter) {
      var page = state.pageIndex;
      if (page >= count) page = count - 1;
      if (page < 0) page = 0;
      emit(state.copyWith(pagesInChapter: count, pageIndex: page));
    }
  }

  void setMode(ReadingMode mode) {
    _settings.setReadingMode(mode);
    emit(state.copyWith(mode: mode, pagesInChapter: 0));
    saveProgress();
  }

  void setFontSize(double size) {
    final clamped = size.clamp(12.0, 32.0);
    _settings.setFontSize(clamped);
    emit(state.copyWith(fontSize: clamped, pagesInChapter: 0));
    saveProgress();
  }

  /// Найти главу по имени файла (для внутренних ссылок epub).
  int chapterIndexForHref(String href) {
    final book = state.book;
    if (book == null) return -1;
    final file = href.split('#').first.split('/').last.toLowerCase();
    if (file.isEmpty) return -1;
    for (var i = 0; i < book.chapters.length; i++) {
      final chHref = book.chapters[i].href.toLowerCase();
      if (chHref == file || chHref.endsWith(file)) return i;
    }
    return -1;
  }

  Future<void> saveProgress() async {
    if (state.book == null) return;
    final offset = _pendingOffset >= 0 ? _pendingOffset : state.scrollOffset;
    if (state.chapterIndex == _lastSavedChapter &&
        offset == _lastSavedOffset &&
        state.pageIndex == _lastSavedPage) {
      return;
    }
    _lastSavedChapter = state.chapterIndex;
    _lastSavedOffset = offset;
    _lastSavedPage = state.pageIndex;
    await _storage.saveProgress(libraryBook.id,
        chapter: state.chapterIndex, offset: offset, page: state.pageIndex);
  }

  Future<void> shutdown() async {
    _saveTimer?.cancel();
    await saveProgress();
  }

  @override
  Future<void> close() async {
    _saveTimer?.cancel();
    await saveProgress();
    return super.close();
  }
}
