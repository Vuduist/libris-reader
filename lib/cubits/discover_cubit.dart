import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/opds_models.dart';
import '../services/livelib_service.dart';
import '../services/opds_service.dart';

class DiscoverState extends Equatable {
  final bool loading;
  final String? error;
  final List<BookEntry> newReleases;
  final List<LiveLibBook> bestsellers;

  const DiscoverState({
    this.loading = false,
    this.error,
    this.newReleases = const [],
    this.bestsellers = const [],
  });

  DiscoverState copyWith({
    bool? loading,
    String? Function()? error,
    List<BookEntry>? newReleases,
    List<LiveLibBook>? bestsellers,
  }) =>
      DiscoverState(
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
        newReleases: newReleases ?? this.newReleases,
        bestsellers: bestsellers ?? this.bestsellers,
      );

  @override
  List<Object?> get props => [loading, error, newReleases, bestsellers];
}

class DiscoverCubit extends Cubit<DiscoverState> {
  final OpdsService _opds;
  final LiveLibService _livelib;

  DiscoverCubit(this._opds, this._livelib) : super(const DiscoverState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: () => null));
    String? error;
    List<BookEntry> releases = state.newReleases;
    List<LiveLibBook> top = state.bestsellers;
    try {
      releases = (await _opds.newReleases()).books;
    } catch (e) {
      error = e.toString();
    }
    try {
      top = await _livelib.fetchTop(limit: 20);
    } catch (_) {
      // при любой ошибке секция бестселлеров просто скрывается
      top = const [];
    }
    emit(state.copyWith(
      loading: false,
      error: () => error,
      newReleases: releases,
      bestsellers: top,
    ));
  }
}
