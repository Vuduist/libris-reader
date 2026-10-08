import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/library_models.dart';
import '../../services/library_storage.dart';

/// Встроенный просмотрщик PDF на pdfrx (pdfium).
class PdfReaderPage extends StatefulWidget {
  final LibraryBook book;
  final LibraryStorage storage;

  const PdfReaderPage({super.key, required this.book, required this.storage});

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  late final PdfViewerController _controller;
  int _page = 1;
  int _pageCount = 0;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _page = widget.book.progressPage > 0 ? widget.book.progressPage : 1;
    widget.storage.touchOpened(widget.book.id);
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() => _page = page);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _saveProgress);
  }

  Future<void> _saveProgress() => widget.storage.saveProgress(widget.book.id,
      chapter: 0, offset: 0, page: _page);

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть книгу',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfViewer.file(
              widget.book.filePath,
              controller: _controller,
              initialPageNumber:
                  widget.book.progressPage > 0 ? widget.book.progressPage : 1,
              params: PdfViewerParams(
                onPageChanged: _onPageChanged,
                onViewerReady: (document, controller) {
                  if (mounted) {
                    setState(() => _pageCount = document.pages.length);
                  }
                },
                errorBannerBuilder: (context, error, stackTrace, ref) =>
                    Center(child: Text('Не удалось открыть PDF: $error')),
              ),
            ),
          ),
          if (_pageCount > 0)
            SizedBox(
              height: 36,
              child: Center(
                child: Text('стр. $_page из $_pageCount',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
        ],
      ),
    );
  }
}
