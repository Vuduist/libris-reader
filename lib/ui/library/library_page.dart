import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../cubits/library_cubit.dart';
import '../../models/library_models.dart';
import '../reader/open_book.dart';
import '../widgets/book_widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _searchOpen = false;
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _filterController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Фильтр по названию или автору',
                    border: InputBorder.none,
                    filled: false),
                onChanged: (v) => context.read<LibraryCubit>().setFilter(v),
              )
            : const Text('Мои книги'),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searchOpen = !_searchOpen);
              if (!_searchOpen) {
                _filterController.clear();
                context.read<LibraryCubit>().setFilter('');
              }
            },
          ),
        ],
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final books = state.visible;
          if (books.isEmpty) {
            return Center(
              child: Text(
                state.filter.isEmpty
                    ? 'Библиотека пуста.\nСкачайте книги из раздела Discover.'
                    : 'Ничего не найдено',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: books.length,
            itemBuilder: (context, i) => _bookCard(context, books[i]),
          );
        },
      ),
    );
  }

  Widget _bookCard(BuildContext context, LibraryBook book) {
    final theme = Theme.of(context);
    final date = DateFormat('dd.MM.yyyy').format(book.addedAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, book),
        onLongPress: () => _showActions(context, book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(
                      coverPath: book.coverPath,
                      coverUrl: book.coverUrl,
                      radius: 0),
                  if (book.pinned)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.push_pin,
                          size: 20, color: Colors.white, shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4)
                          ]),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(book.authorsText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(book.format.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Text(date, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, LibraryBook book) async {
    await openLibraryBook(context, book);
  }

  void _showActions(BuildContext context, LibraryBook book) {
    final cubit = context.read<LibraryCubit>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  book.pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(book.pinned ? 'Открепить' : 'Закрепить'),
              onTap: () {
                Navigator.pop(ctx);
                cubit.togglePin(book.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Удалить книгу?'),
                    content: Text(
                        '«${book.title}» будет удалена вместе с файлом и обложкой.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true) cubit.delete(book.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
