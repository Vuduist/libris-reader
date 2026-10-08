import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/library_models.dart';
import '../models/opds_models.dart';
import '../services/library_storage.dart';
import '../services/opds_service.dart';

class BookDetailState extends Equatable {
  final BookEntry book;
  final LibraryBook? libraryBook; // null — нет в библиотеке
  final bool downloading;
  final double? progress; // 0..1, null — размер неизвестен (indeterminate)
  final String? error;

  const BookDetailState({
    required this.book,
    this.libraryBook,
    this.downloading = false,
    this.progress = 0,
    this.error,
  });

  BookDetailState copyWith({
    LibraryBook? Function()? libraryBook,
    bool? downloading,
    double? Function()? progress,
    String? Function()? error,
  }) =>
      BookDetailState(
        book: book,
        libraryBook: libraryBook != null ? libraryBook() : this.libraryBook,
        downloading: downloading ?? this.downloading,
        progress: progress != null ? progress() : this.progress,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props => [book, libraryBook, downloading, progress, error];
}

class BookDetailCubit extends Cubit<BookDetailState> {
  final OpdsService _opds;
  final LibraryStorage _storage;

  BookDetailCubit(this._opds, this._storage, BookEntry book)
      : super(BookDetailState(
            book: book, libraryBook: _storage.getBook(book.id)));

  void _safeEmit(BookDetailState next) {
    if (!isClosed) emit(next);
  }

  Future<void> download(String format) async {
    if (state.downloading) return;
    final link = state.book.downloads
        .where((d) => d.format == format)
        .firstOrNull;
    if (link == null) return;
    _safeEmit(state.copyWith(
        downloading: true, progress: () => 0, error: () => null));
    try {
      final bytes = await _opds.downloadFile(link.url,
          onProgress: (p) => _safeEmit(state.copyWith(progress: () => p)));
      final path =
          await _storage.saveBookFile(state.book.id, format, bytes);
      // обложку сохраняем в файл обязательно
      final coverPath = await _storage.saveCover(state.book.id, state.book.coverUrl);
      final libraryBook = LibraryBook(
        id: state.book.id,
        title: state.book.title,
        authors: state.book.authors.map((a) => a.name).toList(),
        format: format,
        filePath: path,
        coverPath: coverPath,
        coverUrl: state.book.coverUrl,
        addedAt: DateTime.now(),
      );
      await _storage.putBook(libraryBook);
      _safeEmit(state.copyWith(
          downloading: false, libraryBook: () => libraryBook));
    } catch (e) {
      _safeEmit(state.copyWith(downloading: false, error: () => e.toString()));
    }
  }

  Future<void> removeFromLibrary() async {
    await _storage.deleteBook(state.book.id);
    _safeEmit(state.copyWith(libraryBook: () => null));
  }

  void refreshLibraryStatus() {
    _safeEmit(state.copyWith(libraryBook: () => _storage.getBook(state.book.id)));
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
