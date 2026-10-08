import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../cubits/library_cubit.dart';
import '../../models/library_models.dart';
import '../../services/library_storage.dart';
import 'pdf_page.dart';
import 'reader_page.dart';

/// Единая точка открытия книги из библиотеки/страницы книги.
Future<void> openLibraryBook(BuildContext context, LibraryBook book) async {
  if (book.format == 'pdf') {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            PdfReaderPage(book: book, storage: context.read<LibraryStorage>())));
  } else if (book.format == 'epub' || book.format == 'fb2') {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReaderPage(libraryBook: book)));
  } else if (book.isDjvu) {
    await _showDjvuDialog(context, book);
    return;
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Формат не поддерживается')));
    return;
  }
  if (context.mounted) context.read<LibraryCubit>().reload();
}

Future<void> _showDjvuDialog(BuildContext context, LibraryBook book) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('DjVu'),
      content: const Text(
          'Чтение DjVu не поддерживается встроенной читалкой.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть в другом приложении')),
      ],
    ),
  );
  if (open == true) {
    await SharePlus.instance.share(
        ShareParams(files: [XFile(book.filePath)], text: book.title));
  }
}
