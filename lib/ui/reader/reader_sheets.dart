import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/reader_cubit.dart';
import '../../models/library_models.dart';
import '../../services/dictionary_service.dart';
import '../../services/library_storage.dart';
import '../../services/translate_service.dart';

/// Bottom sheet со сноской.
void showFootnoteSheet(BuildContext context, String text) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
          top: 4),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Сноска',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(text),
          ],
        ),
      ),
    ),
  );
}

/// Bottom sheet со списком заметок книги + добавление новой.
void showNotesSheet(BuildContext context, LibraryStorage storage,
    String bookId, String initialQuote) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _NotesSheet(
        storage: storage, bookId: bookId, initialQuote: initialQuote),
  );
}

class _NotesSheet extends StatefulWidget {
  final LibraryStorage storage;
  final String bookId;
  final String initialQuote;

  const _NotesSheet(
      {required this.storage, required this.bookId, required this.initialQuote});

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  late final TextEditingController _controller;
  late List<BookNote> _notes;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuote);
    _notes = widget.storage.notesFor(widget.bookId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Заметки',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: 'Текст заметки'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final text = _controller.text.trim();
                if (text.isEmpty) return;
                await widget.storage.addNote(
                    bookId: widget.bookId,
                    quote: widget.initialQuote,
                    text: text);
                _controller.clear();
                setState(
                    () => _notes = widget.storage.notesFor(widget.bookId));
              },
              child: const Text('Сохранить'),
            ),
          ),
          const Divider(),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.35),
            child: _notes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8), child: Text('Пока нет заметок'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _notes.length,
                    itemBuilder: (ctx, i) {
                      final n = _notes[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(n.text),
                        subtitle: n.quote.isNotEmpty && n.quote != n.text
                            ? Text(n.quote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic, fontSize: 12))
                            : Text(DateFormat('dd.MM.yyyy HH:mm')
                                .format(n.createdAt)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await widget.storage.deleteNote(n.key);
                            setState(() =>
                                _notes =
                                    widget.storage.notesFor(widget.bookId));
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet с закладками книги.
void showBookmarksSheet(
    BuildContext context, ReaderCubit cubit, LibraryStorage storage, String bookId) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _BookmarksSheet(cubit: cubit, storage: storage, bookId: bookId),
  );
}

class _BookmarksSheet extends StatefulWidget {
  final ReaderCubit cubit;
  final LibraryStorage storage;
  final String bookId;

  const _BookmarksSheet(
      {required this.cubit, required this.storage, required this.bookId});

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  late List<BookBookmark> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.storage.bookmarksFor(widget.bookId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Закладки',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final st = widget.cubit.state;
                    final snippet = widget.cubit.currentSnippet();
                    await widget.storage.addBookmark(
                      bookId: widget.bookId,
                      chapter: st.chapterIndex,
                      offset: widget.cubit.currentOffset,
                      page: st.pageIndex,
                      snippet: snippet.length > 80
                          ? '${snippet.substring(0, 80)}…'
                          : snippet,
                    );
                    setState(() =>
                        _items = widget.storage.bookmarksFor(widget.bookId));
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Добавить закладку'),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: _items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Закладок нет'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final b = _items[i];
                      final chapterTitle =
                          widget.cubit.state.book != null &&
                                  b.chapter <
                                      widget.cubit.state.book!.chapters.length
                              ? widget
                                  .cubit.state.book!.chapters[b.chapter].title
                              : 'Глава ${b.chapter + 1}';
                      return ListTile(
                        title: Text(chapterTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(b.snippet,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await widget.storage.deleteBookmark(b.key);
                            setState(() => _items =
                                widget.storage.bookmarksFor(widget.bookId));
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.cubit.goToChapter(b.chapter,
                              page: b.page, offset: b.offset);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet словаря (Wikipedia / Wiktionary / «ничего не найдено»).
void showDictionarySheet(
    BuildContext context, DictionaryService service, String term) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _DictionarySheet(service: service, term: term),
  );
}

class _DictionarySheet extends StatefulWidget {
  final DictionaryService service;
  final String term;

  const _DictionarySheet({required this.service, required this.term});

  @override
  State<_DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<_DictionarySheet> {
  late Future<DictResult?> _future = widget.service.lookup(widget.term);

  void _retry() {
    setState(() => _future = widget.service.lookup(widget.term));
  }

  Widget _notFound(BuildContext ctx, String term) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Ничего не найдено для «$term»',
            style: Theme.of(ctx).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => launchUrl(
                  Uri.parse(
                      'https://www.google.com/search?q=${Uri.encodeComponent(term)}'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Искать в Google'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: _retry, child: const Text('Повторить')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final term = widget.term;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: FutureBuilder<DictResult?>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return _notFound(ctx, term);
          }
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 160, child: Center(child: CircularProgressIndicator()));
          }
          final result = snap.data;
          if (result == null) {
            return _notFound(ctx, term);
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Источник: ${result.source}',
                    style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(result.title,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (result.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Image.network(result.imageUrl!, height: 120,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                SelectableText(result.text),
                if (result.pageUrl != null)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(result.pageUrl!),
                        mode: LaunchMode.externalApplication),
                    child: const Text('Открыть статью'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bottom sheet с переводом выделенного текста.
void showTranslateSheet(
    BuildContext context, TranslateService service, String text) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _TranslateSheet(service: service, text: text),
  );
}

class _TranslateSheet extends StatefulWidget {
  final TranslateService service;
  final String text;

  const _TranslateSheet({required this.service, required this.text});

  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  late Future<String> _future = widget.service.translate(widget.text);

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: FutureBuilder<String>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ошибка перевода: ${snap.error}'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(
                      () => _future = widget.service.translate(widget.text)),
                  child: const Text('Повторить'),
                ),
              ],
            );
          }
          if (!snap.hasData) {
            return const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()));
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.bodySmall),
              const Divider(),
              Text('Перевод',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SelectableText(snap.data!),
            ],
          );
        },
      ),
    );
  }
}
