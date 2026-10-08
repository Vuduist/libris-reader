import 'dart:io';

import '../../models/library_models.dart';
import '../../models/reader_models.dart';
import 'epub_loader.dart';
import 'fb2_loader.dart';

/// Определяет формат файла и загружает книгу для читалки.
class BookLoader {
  final _epub = EpubLoader();
  final _fb2 = Fb2Loader();

  Future<ReaderBook> load(LibraryBook book) async {
    final bytes = await File(book.filePath).readAsBytes();
    if (book.format == 'fb2') {
      return _fb2.load(bytes);
    }
    if (book.format == 'epub') {
      return _epub.load(bytes);
    }
    // автоопределение
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return _epub.load(bytes);
    }
    return _fb2.load(bytes);
  }
}
