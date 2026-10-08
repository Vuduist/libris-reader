import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/opds_models.dart';
import '../../services/opds_service.dart';
import '../book/book_detail_page.dart';
import '../widgets/book_widgets.dart';

/// Generic OPDS-страница: загружает href и показывает книги карточками,
/// NAV-элементы строками (рекурсивно), с пагинацией rel=next.
class OpdsListPage extends StatefulWidget {
  final String url;
  final String title;

  const OpdsListPage({super.key, required this.url, required this.title});

  @override
  State<OpdsListPage> createState() => _OpdsListPageState();
}

class _OpdsListPageState extends State<OpdsListPage> {
  final _books = <BookEntry>[];
  final _navs = <NavEntry>[];
  String? _nextUrl;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _load(widget.url);
  }

  Future<void> _load(String url, {bool append = false}) async {
    try {
      final feed = await context.read<OpdsService>().fetchFeed(url);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _books
            ..clear()
            ..addAll(feed.books);
          _navs
            ..clear()
            ..addAll(feed.navs);
          if (feed.title.isNotEmpty) _title = feed.title;
        } else {
          _books.addAll(feed.books);
          _navs.addAll(feed.navs);
        }
        _nextUrl = feed.nextUrl;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _books.isEmpty && _navs.isEmpty) {
      return Center(child: Text('Ошибка: $_error'));
    }
    final count = _navs.length + _books.length + (_nextUrl != null ? 1 : 0);
    if (count == 0) return const Center(child: Text('Пусто'));
    return ListView.builder(
      itemCount: count,
      itemBuilder: (context, i) {
        if (i < _navs.length) {
          final nav = _navs[i];
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(nav.title),
            subtitle: nav.note != null ? Text(nav.note!) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    OpdsListPage(url: nav.href, title: nav.title))),
          );
        }
        final bi = i - _navs.length;
        if (bi < _books.length) {
          final book = _books[bi];
          return BookListTile(
            book: book,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookDetailPage(book: book))),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator()
                : FilledButton.tonal(
                    onPressed: () {
                      setState(() => _loadingMore = true);
                      _load(_nextUrl!, append: true);
                    },
                    child: const Text('Ещё'),
                  ),
          ),
        );
      },
    );
  }
}
