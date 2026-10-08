import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/library_models.dart';
import '../services/library_storage.dart';

class LibraryState extends Equatable {
  final List<LibraryBook> books;
  final String filter;

  const LibraryState({this.books = const [], this.filter = ''});

  List<LibraryBook> get visible {
    if (filter.isEmpty) return books;
    final f = filter.toLowerCase();
    return books
        .where((b) =>
            b.title.toLowerCase().contains(f) ||
            b.authorsText.toLowerCase().contains(f))
        .toList();
  }

  LibraryState copyWith({List<LibraryBook>? books, String? filter}) =>
      LibraryState(books: books ?? this.books, filter: filter ?? this.filter);

  @override
  List<Object?> get props => [books, filter];
}

class LibraryCubit extends Cubit<LibraryState> {
  final LibraryStorage _storage;

  LibraryCubit(this._storage) : super(const LibraryState());

  void reload() => emit(state.copyWith(books: _storage.listBooks()));

  void setFilter(String filter) => emit(state.copyWith(filter: filter));

  Future<void> togglePin(String id) async {
    await _storage.togglePin(id);
    reload();
  }

  Future<void> delete(String id) async {
    await _storage.deleteBook(id);
    reload();
  }
}
