import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/opds_models.dart';
import '../services/opds_service.dart';

class AuthorState extends Equatable {
  final bool loading;
  final String? error;
  final String authorName;
  final NavEntry? bio; // «Об авторе»
  final List<NavEntry> sections; // по сериям / вне серий / по алфавиту / по дате

  const AuthorState({
    this.loading = true,
    this.error,
    this.authorName = '',
    this.bio,
    this.sections = const [],
  });

  AuthorState copyWith({
    bool? loading,
    String? Function()? error,
    String? authorName,
    NavEntry? Function()? bio,
    List<NavEntry>? sections,
  }) =>
      AuthorState(
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
        authorName: authorName ?? this.authorName,
        bio: bio != null ? bio() : this.bio,
        sections: sections ?? this.sections,
      );

  @override
  List<Object?> get props => [loading, error, authorName, bio, sections];
}

class AuthorCubit extends Cubit<AuthorState> {
  final OpdsService _opds;

  AuthorCubit(this._opds) : super(const AuthorState());

  Future<void> load(String authorId, {String fallbackName = ''}) async {
    emit(AuthorState(authorName: fallbackName));
    try {
      final feed = await _opds.authorPage(authorId);
      NavEntry? bio;
      final sections = <NavEntry>[];
      for (final nav in feed.navs) {
        if (nav.title == 'Об авторе' || nav.contentHtml != null) {
          bio ??= nav;
        } else {
          sections.add(nav);
        }
      }
      // заголовок ленты — «Книги автора X»
      var name = feed.title.replaceFirst('Книги автора ', '').trim();
      if (name.isEmpty) name = fallbackName;
      emit(AuthorState(
          loading: false, authorName: name, bio: bio, sections: sections));
    } catch (e) {
      emit(AuthorState(
          loading: false, error: e.toString(), authorName: fallbackName));
    }
  }
}
