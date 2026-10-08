import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/library_models.dart';

/// Хранилище библиотеки: Hive-боксы books/notes/bookmarks + файлы книг и обложек.
class LibraryStorage {
  late Box _books;
  late Box _notes;
  late Box _bookmarks;

  final http.Client _client;

  LibraryStorage({http.Client? client}) : _client = client ?? http.Client();

  Future<void> init() async {
    await Hive.initFlutter();
    _books = await Hive.openBox('books');
    _notes = await Hive.openBox('notes');
    _bookmarks = await Hive.openBox('bookmarks');
  }

  Future<Directory> _dir(String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Libris/$name');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> booksDir() => _dir('Books');
  Future<Directory> coversDir() => _dir('Covers');

  // ---- Книги ----

  List<LibraryBook> listBooks() {
    final books = _books.values
        .map((m) => LibraryBook.fromMap(m as Map))
        .toList();
    books.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final at = a.lastOpenedAt ?? a.addedAt;
      final bt = b.lastOpenedAt ?? b.addedAt;
      return bt.compareTo(at);
    });
    return books;
  }

  LibraryBook? getBook(String id) {
    final m = _books.get(id);
    return m == null ? null : LibraryBook.fromMap(m as Map);
  }

  Future<void> putBook(LibraryBook book) =>
      _books.put(book.id, book.toMap());

  Future<void> updateBook(LibraryBook book) => putBook(book);

  Future<void> deleteBook(String id) async {
    final book = getBook(id);
    await _books.delete(id);
    if (book != null) {
      try {
        final f = File(book.filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      final cover = book.coverPath;
      if (cover != null) {
        try {
          final f = File(cover);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    // связанные заметки и закладки
    final noteKeys = _notes.keys
        .where((k) => ((_notes.get(k) as Map)['bookId']) == id)
        .toList();
    for (final k in noteKeys) {
      await _notes.delete(k);
    }
    final bmKeys = _bookmarks.keys
        .where((k) => ((_bookmarks.get(k) as Map)['bookId']) == id)
        .toList();
    for (final k in bmKeys) {
      await _bookmarks.delete(k);
    }
  }

  Future<void> touchOpened(String id) async {
    final book = getBook(id);
    if (book == null) return;
    await putBook(book.copyWith(lastOpenedAt: DateTime.now()));
  }

  Future<void> togglePin(String id) async {
    final book = getBook(id);
    if (book == null) return;
    await putBook(book.copyWith(pinned: !book.pinned));
  }

  Future<void> saveProgress(String id,
      {required int chapter, required double offset, required int page}) async {
    final book = getBook(id);
    if (book == null) return;
    await putBook(book.copyWith(
        progressChapter: chapter, progressOffset: offset, progressPage: page));
  }

  /// Скачивает обложку и сохраняет в файл. Возвращает путь или null.
  Future<String?> saveCover(String bookId, String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) return null;
    try {
      final resp = await _client
          .get(Uri.parse(coverUrl))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      final dir = await coversDir();
      final file = File('${dir.path}/$bookId.jpg');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> saveBookFile(
      String bookId, String format, List<int> bytes) async {
    final dir = await booksDir();
    final file = File('${dir.path}/$bookId.$format');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ---- Заметки ----

  List<BookNote> notesFor(String bookId) {
    final out = <BookNote>[];
    for (final k in _notes.keys) {
      final m = _notes.get(k) as Map;
      if (m['bookId'] == bookId) out.add(BookNote.fromMap(k.toString(), m));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> addNote(
      {required String bookId, required String quote, required String text}) {
    final key = DateTime.now().microsecondsSinceEpoch.toString();
    return _notes.put(
        key,
        BookNote(
                key: key,
                bookId: bookId,
                quote: quote,
                text: text,
                createdAt: DateTime.now())
            .toMap());
  }

  Future<void> deleteNote(String key) => _notes.delete(key);

  // ---- Закладки ----

  List<BookBookmark> bookmarksFor(String bookId) {
    final out = <BookBookmark>[];
    for (final k in _bookmarks.keys) {
      final m = _bookmarks.get(k) as Map;
      if (m['bookId'] == bookId) out.add(BookBookmark.fromMap(k.toString(), m));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> addBookmark({
    required String bookId,
    required int chapter,
    required double offset,
    required int page,
    required String snippet,
  }) {
    final key = DateTime.now().microsecondsSinceEpoch.toString();
    return _bookmarks.put(
        key,
        BookBookmark(
                key: key,
                bookId: bookId,
                chapter: chapter,
                offset: offset,
                page: page,
                snippet: snippet,
                createdAt: DateTime.now())
            .toMap());
  }

  Future<void> deleteBookmark(String key) => _bookmarks.delete(key);
}
