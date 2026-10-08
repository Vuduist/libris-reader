import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/reader_cubit.dart';
import '../../cubits/settings_cubit.dart';
import '../../cubits/tts_cubit.dart';
import '../../models/library_models.dart';
import '../../services/dictionary_service.dart';
import '../../services/library_storage.dart';
import '../../services/translate_service.dart';
import '../../services/tts_service.dart';
import 'paginator.dart';
import 'reader_block_view.dart';
import 'reader_sheets.dart';
import 'tts_player_panel.dart';

class ReaderPage extends StatelessWidget {
  final LibraryBook libraryBook;

  const ReaderPage({super.key, required this.libraryBook});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
            create: (ctx) => ReaderCubit(ctx.read<LibraryStorage>(),
                ctx.read<SettingsCubit>(), libraryBook)
              ..open()),
        BlocProvider(
            create: (ctx) => TtsCubit(TtsService(),
                ctx.read<SettingsCubit>(), ctx.read<ReaderCubit>())),
      ],
      child: const _ReaderView(),
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView();

  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      context.read<ReaderCubit>().saveProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReaderCubit>();
    return MultiBlocListener(
      listeners: [
        BlocListener<ReaderCubit, ReaderState>(
          listenWhen: (p, n) => p.chapterIndex != n.chapterIndex,
          listener: (context, s) =>
              context.read<TtsCubit>().followUserChapter(s.chapterIndex),
        ),
        BlocListener<TtsCubit, TtsState>(
          listenWhen: (p, n) => p.error != n.error && n.error != null,
          listener: (context, s) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(s.error!)));
            context.read<TtsCubit>().clearError();
          },
        ),
      ],
      child: BlocBuilder<ReaderCubit, ReaderState>(
      builder: (context, state) {
        final chapter = state.currentChapter;
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      state.chapterIndex > 0 ? cubit.prevChapter : null,
                ),
                Expanded(
                  child: Text(
                    chapter?.title ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: state.book != null &&
                          state.chapterIndex < state.book!.chapters.length - 1
                      ? cubit.nextChapter
                      : null,
                ),
              ],
            ),
            actions: [
              BlocBuilder<TtsCubit, TtsState>(
                builder: (context, tts) => IconButton(
                  icon: Icon(tts.active
                      ? Icons.headset
                      : Icons.headset_outlined),
                  tooltip: 'Слушать',
                  color:
                      tts.active ? Theme.of(context).colorScheme.primary : null,
                  onPressed: chapter == null
                      ? null
                      : () => context.read<TtsCubit>().start(),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onMenu(context, cubit, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'bookmarks',
                      child: ListTile(
                          leading: Icon(Icons.bookmark_outline),
                          title: Text('Закладки'),
                          contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(
                      value: 'fontUp',
                      child: ListTile(
                          leading: Icon(Icons.text_increase),
                          title: Text('Увеличить текст'),
                          contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(
                      value: 'fontDown',
                      child: ListTile(
                          leading: Icon(Icons.text_decrease),
                          title: Text('Уменьшить текст'),
                          contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(
                      value: 'close',
                      child: ListTile(
                          leading: Icon(Icons.close),
                          title: Text('Закрыть книгу'),
                          contentPadding: EdgeInsets.zero)),
                ],
              ),
            ],
          ),
          drawer: _tocDrawer(context, cubit, state),
          body: _body(context, cubit, state),
          bottomNavigationBar: const TtsPlayerPanel(),
        );
      }),
    );
  }

  Widget _body(BuildContext context, ReaderCubit cubit, ReaderState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(state.error!, textAlign: TextAlign.center),
      ));
    }
    final chapter = state.currentChapter;
    if (chapter == null) {
      return const Center(child: Text('Нет содержимого'));
    }
    if (state.mode == ReadingMode.paged) {
      return _PagedChapter(
          key: ValueKey(
              'p${cubit.navigationEpoch}-${state.chapterIndex}-${state.fontSize}'));
    }
    return _ScrollChapter(
        key: ValueKey('s${cubit.navigationEpoch}-${state.chapterIndex}'));
  }

  Widget _tocDrawer(
      BuildContext context, ReaderCubit cubit, ReaderState state) {
    final book = state.book;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(book?.title ?? 'Содержание',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: book == null
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      itemCount: book.chapters.length,
                      itemBuilder: (ctx, i) {
                        final ch = book.chapters[i];
                        final current = i == state.chapterIndex;
                        return ListTile(
                          dense: true,
                          title: Text(ch.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: current
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          onTap: () {
                            Navigator.pop(ctx);
                            cubit.goToChapter(i);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenu(BuildContext context, ReaderCubit cubit, String value) {
    final storage = context.read<LibraryStorage>();
    final bookId = cubit.libraryBook.id;
    switch (value) {
      case 'bookmarks':
        showBookmarksSheet(context, cubit, storage, bookId);
        break;
      case 'fontUp':
        cubit.setFontSize(cubit.state.fontSize + 2);
        break;
      case 'fontDown':
        cubit.setFontSize(cubit.state.fontSize - 2);
        break;
      case 'close':
        Navigator.of(context).pop();
        break;
    }
  }
}

/// Общие колбэки выделения/ссылок для блоков.
void openReaderLink(BuildContext context, ReaderCubit cubit, String href) {
  final book = cubit.state.book;
  if (book == null) return;
  if (href.startsWith('http://') || href.startsWith('https://')) {
    launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    return;
  }
  if (href.contains('#')) {
    final frag = href.split('#').last;
    final note = book.footnotes[frag];
    if (note != null) {
      showFootnoteSheet(context, note);
      return;
    }
  }
  final file = href.split('#').first;
  if (file.isNotEmpty) {
    final idx = cubit.chapterIndexForHref(file);
    if (idx >= 0 && idx != cubit.state.chapterIndex) {
      cubit.goToChapter(idx);
    }
  }
}

void _onNote(BuildContext context, String text) => showNotesSheet(context,
    context.read<LibraryStorage>(), context.read<ReaderCubit>().libraryBook.id, text);

void _onSearch(BuildContext context, String text) =>
    showDictionarySheet(context, context.read<DictionaryService>(), text);

void _onTranslate(BuildContext context, String text) =>
    showTranslateSheet(context, context.read<TranslateService>(), text);

/// Вертикальный скролл главы.
class _ScrollChapter extends StatefulWidget {
  const _ScrollChapter({super.key});

  @override
  State<_ScrollChapter> createState() => _ScrollChapterState();
}

class _ScrollChapterState extends State<_ScrollChapter> {
  late final ScrollController _controller;
  final Map<int, GlobalKey> _blockKeys = {};
  int _lastTtsBlock = -2;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(() {
      if (mounted) {
        context.read<ReaderCubit>().setScrollOffset(_controller.offset);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      // во время TTS позицию восстанавливает follow-подсветка
      if (context.read<TtsCubit>().state.active) return;
      final saved = context.read<ReaderCubit>().state.scrollOffset;
      if (saved > 0) {
        final max = _controller.position.maxScrollExtent;
        _controller.jumpTo(saved.clamp(0.0, max));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _followTts(TtsState tts, int readerChapter) {
    if (!tts.active || tts.blockIndex < 0 || tts.chapterIndex != readerChapter) {
      return;
    }
    if (tts.blockIndex == _lastTtsBlock) return;
    _lastTtsBlock = tts.blockIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _blockKeys[tts.blockIndex]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.2, duration: const Duration(milliseconds: 300));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<ReaderCubit>().state;
    final tts = context.watch<TtsCubit>().state;
    final chapter = state.currentChapter!;
    _followTts(tts, state.chapterIndex);
    final highlightBlock =
        tts.active && tts.chapterIndex == state.chapterIndex
            ? tts.blockIndex
            : -1;
    return SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < chapter.blocks.length; i++)
            ReaderBlockView(
              key: _blockKeys.putIfAbsent(i, () => GlobalKey()),
              block: chapter.blocks[i],
              fontSize: state.fontSize,
              highlighted: i == highlightBlock,
              onLink: (href) =>
                  openReaderLink(context, context.read<ReaderCubit>(), href),
              onNote: (t) => _onNote(context, t),
              onSearch: (t) => _onSearch(context, t),
              onTranslate: (t) => _onTranslate(context, t),
            ),
        ],
      ),
    );
  }
}

/// Горизонтальная пагинация главы через TextPainter.
class _PagedChapter extends StatefulWidget {
  const _PagedChapter({super.key});

  @override
  State<_PagedChapter> createState() => _PagedChapterState();
}

class _PagedChapterState extends State<_PagedChapter> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    final state = context.read<ReaderCubit>().state;
    _currentPage = state.pageIndex;
    _pageController = PageController(initialPage: state.pageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // кэш пагинации: пересчёт только при смене главы/шрифта/размеров/скейлера
  List<ReaderPageData>? _pages;
  double _cacheW = -1;
  double _cacheH = -1;
  TextScaler? _cacheScaler;
  int _lastTtsBlock = -2;

  /// Страница, на которой начинается блок (или впервые встречается).
  int _pageForBlock(List<ReaderPageData> pages, int blockIndex) {
    var fallback = -1;
    for (var p = 0; p < pages.length; p++) {
      for (final s in pages[p].slices) {
        if (s.blockIndex == blockIndex) {
          if (s.start <= 0) return p;
          fallback = p;
        }
      }
    }
    return fallback;
  }

  void _followTts(TtsState tts, ReaderState state, List<ReaderPageData> pages) {
    if (!tts.active ||
        tts.blockIndex < 0 ||
        tts.chapterIndex != state.chapterIndex) {
      return;
    }
    if (tts.blockIndex == _lastTtsBlock) return;
    _lastTtsBlock = tts.blockIndex;
    final page = _pageForBlock(pages, tts.blockIndex);
    if (page < 0 || page == _currentPage) return;
    _currentPage = page;
    final cubit = context.read<ReaderCubit>();
    cubit.setPageIndex(page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(page);
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReaderCubit>();
    final state = cubit.state;
    final tts = context.watch<TtsCubit>().state;
    final chapter = state.currentChapter!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth - 40;
        final h = constraints.maxHeight - 44; // индикатор страницы
        final scaler = MediaQuery.textScalerOf(context);
        if (_pages == null ||
            _cacheW != w ||
            _cacheH != h ||
            _cacheScaler != scaler) {
          final paginator = Paginator(
              blocks: chapter.blocks,
              width: w,
              height: h,
              fontSize: state.fontSize,
              textScaler: scaler);
          _pages = paginator.paginate();
          _cacheW = w;
          _cacheH = h;
          _cacheScaler = scaler;
        }
        final pages = _pages!;
        cubit.currentPages = pages;
        _followTts(tts, state, pages);
        final highlightBlock =
            tts.active && tts.chapterIndex == state.chapterIndex
                ? tts.blockIndex
                : -1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) cubit.setPagesInChapter(pages.length);
        });
        if (_currentPage >= pages.length) {
          _currentPage = pages.length - 1;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(_currentPage);
            }
          });
        }
        final imageMaxH = imageBlockHeight(h) - 16;
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (i) {
                  _currentPage = i;
                  cubit.setPageIndex(i);
                  setState(() {});
                },
                itemBuilder: (ctx, pageIdx) {
                  final page = pages[pageIdx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        for (final slice in page.slices)
                          ReaderBlockView(
                            block: chapter.blocks[slice.blockIndex],
                            fontSize: state.fontSize,
                            start: slice.start,
                            end: slice.end,
                            imageMaxHeight: imageMaxH,
                            highlighted: slice.blockIndex == highlightBlock,
                            onLink: (href) =>
                                openReaderLink(context, cubit, href),
                            onNote: (t) => _onNote(context, t),
                            onSearch: (t) => _onSearch(context, t),
                            onTranslate: (t) => _onTranslate(context, t),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  'стр. ${_currentPage + 1} из ${pages.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
