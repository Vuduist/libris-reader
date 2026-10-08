import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/book_detail_cubit.dart';
import '../../cubits/library_cubit.dart';
import '../../models/library_models.dart';
import '../../models/opds_models.dart';
import '../../services/library_storage.dart';
import '../../services/opds_service.dart';
import '../../utils/html_utils.dart';
import '../author/author_page.dart';
import '../reader/open_book.dart';
import '../widgets/book_widgets.dart';

class BookDetailPage extends StatelessWidget {
  final BookEntry book;

  const BookDetailPage({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => BookDetailCubit(
          ctx.read<OpdsService>(), ctx.read<LibraryStorage>(), book),
      child: const _BookDetailView(),
    );
  }
}

class _BookDetailView extends StatelessWidget {
  const _BookDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BookDetailCubit, BookDetailState>(
      listenWhen: (prev, curr) =>
          prev.libraryBook != curr.libraryBook || prev.error != curr.error,
      listener: (context, state) {
        // статус «в библиотеке» изменился (скачивание/удаление) — обновляем полку
        context.read<LibraryCubit>().reload();
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка: ${state.error}')));
        }
      },
      builder: (context, state) {
        final theme = Theme.of(context);
        final book = state.book;
        return Scaffold(
          appBar: AppBar(title: const Text('О книге')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                  child: BookCover(
                      coverUrl: book.coverUrl, width: 160, height: 230)),
              const SizedBox(height: 16),
              Text(book.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: book.authors
                    .map((a) => ActionChip(
                          label: Text(a.name),
                          onPressed: a.id == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => AuthorPage(
                                          authorId: a.id!, name: a.name))),
                        ))
                    .toList(),
              ),
              if (book.genres.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: book.genres
                      .map((g) => Chip(
                          label: Text(g, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact))
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (book.issued != null) Text('Год: ${book.issued}'),
                  if (book.issued != null && book.language != null)
                    const Text('  •  '),
                  if (book.language != null)
                    Text('Язык: ${book.language}'),
                  if (book.format != null) ...[
                    const Text('  •  '),
                    Text(book.format!),
                  ],
                ],
              ),
              if (book.annotation.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(stripHtml(book.annotation),
                    style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),
              _actions(context, state),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, BookDetailState state) {
    final libBook = state.libraryBook;
    if (state.downloading) {
      final progress = state.progress;
      return Column(
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(progress == null
              ? 'Скачивание…'
              : 'Скачивание… ${(progress * 100).toStringAsFixed(0)}%'),
        ],
      );
    }
    if (libBook != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _openReader(context, libBook),
            icon: const Icon(Icons.menu_book),
            label: const Text('Читать'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить'),
          ),
        ],
      );
    }
    final formats = <String>[];
    for (final f in ['epub', 'fb2', 'pdf', 'djvu']) {
      if (state.book.downloads.any((d) => d.format == f)) {
        formats.add(f);
      }
    }
    if (formats.isEmpty) {
      return const Text('Нет доступных форматов для скачивания',
          textAlign: TextAlign.center);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: formats
          .map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: () =>
                      context.read<BookDetailCubit>().download(f),
                  icon: const Icon(Icons.download),
                  label: Text('Скачать ${f.toUpperCase()}'),
                ),
              ))
          .toList(),
    );
  }

  Future<void> _openReader(BuildContext context, LibraryBook book) async {
    await openLibraryBook(context, book);
    if (context.mounted) {
      context.read<BookDetailCubit>().refreshLibraryStatus();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final cubit = context.read<BookDetailCubit>();
    final libraryCubit = context.read<LibraryCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить книгу?'),
        content: const Text('Файл книги и обложка будут удалены с устройства.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await cubit.removeFromLibrary();
      libraryCubit.reload();
    }
  }
}
