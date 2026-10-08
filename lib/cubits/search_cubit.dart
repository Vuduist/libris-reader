import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/opds_models.dart';
import '../services/opds_service.dart';

enum SearchTab { books, authors, sequences }

class SearchState extends Equatable {
  final String query;
  final SearchTab tab;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final List<BookEntry> books;
  final List<NavEntry> navs;
  final String? nextUrl;

  const SearchState({
    this.query = '',
    this.tab = SearchTab.books,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.books = const [],
    this.navs = const [],
    this.nextUrl,
  });

  bool get hasResults => books.isNotEmpty || navs.isNotEmpty;

  SearchState copyWith({
    String? query,
    SearchTab? tab,
    bool? loading,
    bool? loadingMore,
    String? Function()? error,
    List<BookEntry>? books,
    List<NavEntry>? navs,
    String? Function()? nextUrl,
  }) =>
      SearchState(
        query: query ?? this.query,
        tab: tab ?? this.tab,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error != null ? error() : this.error,
        books: books ?? this.books,
        navs: navs ?? this.navs,
        nextUrl: nextUrl != null ? nextUrl() : this.nextUrl,
      );

  @override
  List<Object?> get props =>
      [query, tab, loading, loadingMore, error, books, navs, nextUrl];
}

class SearchCubit extends Cubit<SearchState> {
  final OpdsService _opds;

  SearchCubit(this._opds) : super(const SearchState());

  int _requestId = 0;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      _requestId++; // инвалидируем летящие search/loadMore
      emit(const SearchState());
      return;
    }
    final id = ++_requestId;
    emit(state.copyWith(
        query: q, loading: true, error: () => null, books: [], navs: []));
    try {
      final feed = await _fetch(q, state.tab);
      if (id != _requestId) return;
      emit(state.copyWith(
        loading: false,
        books: feed.books,
        navs: feed.navs,
        nextUrl: () => feed.nextUrl,
      ));
    } catch (e) {
      if (id != _requestId) return;
      emit(state.copyWith(loading: false, error: () => e.toString()));
    }
  }

  Future<void> setTab(SearchTab tab) async {
    if (tab == state.tab) return;
    emit(state.copyWith(tab: tab));
    if (state.query.isNotEmpty) {
      await search(state.query);
    }
  }

  Future<void> loadMore() async {
    final next = state.nextUrl;
    if (next == null || state.loading || state.loadingMore) return;
    final id = _requestId;
    emit(state.copyWith(loadingMore: true));
    try {
      final feed = await _opds.fetchFeed(next);
      // за время полёта мог начаться новый поиск — результат игнорируем
      if (id != _requestId) return;
      emit(state.copyWith(
        loadingMore: false,
        books: [...state.books, ...feed.books],
        navs: [...state.navs, ...feed.navs],
        nextUrl: () => feed.nextUrl,
      ));
    } catch (_) {
      if (id != _requestId) return;
      emit(state.copyWith(loadingMore: false));
    }
  }

  Future<OpdsFeed> _fetch(String q, SearchTab tab) {
    switch (tab) {
      case SearchTab.books:
        return _opds.searchBooks(q);
      case SearchTab.authors:
        return _opds.searchAuthors(q);
      case SearchTab.sequences:
        return _opds.searchSequences(q);
    }
  }
}
