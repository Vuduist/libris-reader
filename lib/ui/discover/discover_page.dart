import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/discover_cubit.dart';
import '../../cubits/search_cubit.dart';
import '../../cubits/settings_cubit.dart';
import '../../models/opds_models.dart';
import '../../services/livelib_service.dart';
import '../../services/opds_service.dart';
import '../author/author_page.dart';
import '../book/book_detail_page.dart';
import '../opds/opds_list_page.dart';
import '../widgets/book_widgets.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(BuildContext context, String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) context.read<SearchCubit>().search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
            create: (ctx) => DiscoverCubit(
                ctx.read<OpdsService>(), ctx.read<LiveLibService>())
              ..load()),
        BlocProvider(create: (ctx) => SearchCubit(ctx.read<OpdsService>())),
      ],
      child: BlocListener<SettingsCubit, SettingsState>(
        listenWhen: (prev, next) => prev.opdsBaseUrl != next.opdsBaseUrl,
        listener: (context, _) => context.read<DiscoverCubit>().load(),
        child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('Discover',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (q) => _onQueryChanged(context, q),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (q) =>
                        context.read<SearchCubit>().search(q),
                    decoration: InputDecoration(
                      hintText: 'Search books, authors...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                context.read<SearchCubit>().search('');
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<SearchCubit, SearchState>(
                    builder: (context, search) {
                      if (search.query.isEmpty) {
                        return const _DiscoverHome();
                      }
                      return const _SearchResults();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        }),
      ),
    );
  }
}

/// Домашний вид: новинки + бестселлеры.
class _DiscoverHome extends StatelessWidget {
  const _DiscoverHome();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      builder: (context, state) {
        if (state.loading && state.newReleases.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: () => context.read<DiscoverCubit>().load(),
          child: ListView(
            children: [
              if (state.error != null && state.newReleases.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Не удалось загрузить каталог: ${state.error}'),
                ),
              _Section(
                title: 'Новые релизы',
                child: SizedBox(
                  height: 235,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.newReleases.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final b = state.newReleases[i];
                      return BookCardSmall(
                        title: b.title,
                        author: b.authorsText,
                        coverUrl: b.coverUrl,
                        onTap: () => _openBook(context, b),
                      );
                    },
                  ),
                ),
              ),
              if (state.bestsellers.isNotEmpty)
                _Section(
                  title: 'Бестселлеры',
                  child: SizedBox(
                    height: 235,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: state.bestsellers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final b = state.bestsellers[i];
                        return BookCardSmall(
                          title: b.title,
                          author: b.author,
                          coverUrl: b.coverUrl,
                          badge: b.rating,
                          onTap: () => _openBestseller(context, b.title),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openBook(BuildContext context, BookEntry book) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailPage(book: book)));
  }

  Future<void> _openBestseller(BuildContext context, String title) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false, // защита от системного back во время поиска
        child: Center(child: CircularProgressIndicator()),
      ),
    ).then((_) => dialogOpen = false);
    void closeDialog() {
      if (dialogOpen) navigator.pop();
    }
    try {
      final feed = await context.read<OpdsService>().searchBooks(title);
      closeDialog();
      if (feed.books.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Книга не найдена на Флибусте')));
        return;
      }
      navigator.push(MaterialPageRoute(
          builder: (_) => BookDetailPage(book: feed.books.first)));
    } catch (e) {
      closeDialog();
      messenger.showSnackBar(SnackBar(content: Text('Ошибка поиска: $e')));
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        child,
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Результаты поиска с сегмент-переключателем.
class _SearchResults extends StatelessWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _segment(context, state, SearchTab.books, 'Книги'),
                const SizedBox(width: 8),
                _segment(context, state, SearchTab.authors, 'Авторы'),
                const SizedBox(width: 8),
                _segment(context, state, SearchTab.sequences, 'Серии'),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(child: _results(context, state)),
          ],
        );
      },
    );
  }

  Widget _segment(
      BuildContext context, SearchState state, SearchTab tab, String label) {
    final selected = state.tab == tab;
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.read<SearchCubit>().setTab(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : theme.cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check, size: 16, color: Colors.white),
                ),
              Text(label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context, SearchState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(child: Text('Ошибка: ${state.error}'));
    }
    if (!state.hasResults) {
      return const Center(child: Text('Ничего не найдено'));
    }

    if (state.tab == SearchTab.books) {
      return ListView.builder(
        itemCount: state.books.length + (state.nextUrl != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.books.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: state.loadingMore
                    ? const CircularProgressIndicator()
                    : FilledButton.tonal(
                        onPressed: () =>
                            context.read<SearchCubit>().loadMore(),
                        child: const Text('Ещё'),
                      ),
              ),
            );
          }
          final book = state.books[i];
          return BookListTile(
            book: book,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookDetailPage(book: book))),
          );
        },
      );
    }

    // авторы / серии — nav-строки
    return ListView.builder(
      itemCount: state.navs.length + (state.nextUrl != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= state.navs.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: state.loadingMore
                  ? const CircularProgressIndicator()
                  : FilledButton.tonal(
                      onPressed: () => context.read<SearchCubit>().loadMore(),
                      child: const Text('Ещё'),
                    ),
            ),
          );
        }
        final nav = state.navs[i];
        final isAuthor = state.tab == SearchTab.authors;
        return ListTile(
          leading: isAuthor ? const Icon(Icons.person_outline) : const Icon(Icons.collections_bookmark_outlined),
          title: Text(nav.title),
          subtitle: nav.note != null
              ? Text(nav.note!)
              : (isAuthor ? const Text('Автор') : null),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            if (isAuthor) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      AuthorPage(authorId: _authorId(nav.href), name: nav.title)));
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      OpdsListPage(url: nav.href, title: nav.title)));
            }
          },
        );
      },
    );
  }

  String _authorId(String href) {
    final m = RegExp(r'/author/(\d+)').firstMatch(href);
    return m?.group(1) ?? href.split('/').last;
  }
}
