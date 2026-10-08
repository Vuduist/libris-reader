import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../models/reader_models.dart';

/// Диапазон символов блока на странице (start,end = -1 для изображений).
class PageSlice {
  final int blockIndex;
  final int start;
  final int end;

  const PageSlice(this.blockIndex, this.start, this.end);

  bool get isImage => start < 0;

  /// Продолжение блока с предыдущей страницы (без отступа сверху).
  bool get isContinuation => start > 0;
}

class ReaderPageData {
  final List<PageSlice> slices;

  const ReaderPageData(this.slices);
}

TextStyle blockTextStyle(ReaderBlock block, double fontSize) {
  switch (block.type) {
    case BlockType.h1:
      return TextStyle(
          fontSize: fontSize + 8, fontWeight: FontWeight.bold, height: 1.3);
    case BlockType.h2:
      return TextStyle(
          fontSize: fontSize + 5, fontWeight: FontWeight.bold, height: 1.3);
    case BlockType.h3:
      return TextStyle(
          fontSize: fontSize + 2, fontWeight: FontWeight.bold, height: 1.3);
    case BlockType.epigraph:
      return TextStyle(
          fontSize: fontSize, fontStyle: FontStyle.italic, height: 1.45);
    case BlockType.paragraph:
    case BlockType.image:
    case BlockType.spacer:
      return TextStyle(fontSize: fontSize, height: 1.45);
  }
}

double blockSpacingBefore(ReaderBlock block) {
  switch (block.type) {
    case BlockType.h1:
    case BlockType.h2:
      return 16;
    case BlockType.h3:
      return 12;
    case BlockType.spacer:
      return 10;
    case BlockType.image:
      return 8;
    case BlockType.paragraph:
    case BlockType.epigraph:
      return 6;
  }
}

double blockWidth(ReaderBlock block, double width) =>
    block.type == BlockType.epigraph ? width - 32 : width;

/// Единая формула высоты картинки — используется и пагинатором, и рендером.
double imageBlockHeight(double viewportHeight) =>
    math.min(380.0, viewportHeight * 0.45) + 16;

/// Пагинация главы через TextPainter: жадно набирает блоки на страницу,
/// длинный абзац делит бинарным поиском по символам.
class Paginator {
  final List<ReaderBlock> blocks;
  final double width;
  final double height;
  final double fontSize;
  final TextScaler textScaler;

  Paginator({
    required this.blocks,
    required this.width,
    required this.height,
    required this.fontSize,
    this.textScaler = TextScaler.noScaling,
  });

  List<ReaderPageData> paginate() {
    final pages = <ReaderPageData>[];
    var current = <PageSlice>[];
    var used = 0.0;

    void flush() {
      if (current.isNotEmpty) {
        pages.add(ReaderPageData(current));
        current = [];
        used = 0;
      }
    }

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.isEmpty && block.type != BlockType.spacer) continue;

      if (block.type == BlockType.image) {
        final h = imageBlockHeight(height);
        if (used + h > height && current.isNotEmpty) flush();
        current.add(PageSlice(i, -1, -1));
        used += h;
        continue;
      }
      if (block.type == BlockType.spacer) {
        if (used + blockSpacingBefore(block) <= height && current.isNotEmpty) {
          used += blockSpacingBefore(block);
        }
        continue;
      }

      final text = block.plainText;
      final w = blockWidth(block, width);
      var pos = 0;
      var firstChunk = true;

      while (pos < text.length) {
        final spacing = firstChunk ? blockSpacingBefore(block) : 0.0;
        final available = height - used - spacing;
        final lineHeight = _lineHeight(block, w);
        if (available < lineHeight) {
          if (current.isNotEmpty) {
            flush();
            continue;
          }
          // защита от бесконечного цикла: страница ниже строки —
          // форсируем один символ
          current.add(PageSlice(i, pos, pos + 1));
          pos += 1;
          firstChunk = false;
          flush();
          continue;
        }
        final chunk = _fitText(block, pos, w, available);
        if (chunk <= pos) {
          if (current.isNotEmpty) {
            flush();
            continue;
          }
          current.add(PageSlice(i, pos, pos + 1));
          pos += 1;
          firstChunk = false;
          flush();
          continue;
        }
        current.add(PageSlice(i, pos, chunk));
        used += spacing;
        used += _measure(block, pos, chunk, w);
        pos = chunk;
        firstChunk = false;
        if (pos < text.length && used >= height - lineHeight * 0.5) {
          flush();
        }
      }
    }
    flush();
    if (pages.isEmpty) pages.add(const ReaderPageData([]));
    return pages;
  }

  /// Стилизованный TextSpan для диапазона [start, end) plain-текста блока.
  TextSpan _styledSlice(ReaderBlock block, int start, int end) {
    final base = blockTextStyle(block, fontSize);
    final children = <TextSpan>[];
    var pos = 0;
    for (final s in block.spans) {
      final spanStart = pos;
      final spanEnd = pos + s.text.length;
      pos = spanEnd;
      if (spanEnd <= start || spanStart >= end) continue;
      final cutStart = start > spanStart ? start - spanStart : 0;
      final cutEnd = end < spanEnd ? end - spanStart : s.text.length;
      var style = base;
      if (s.bold) style = style.copyWith(fontWeight: FontWeight.bold);
      if (s.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (s.sup) style = style.copyWith(fontSize: base.fontSize! * 0.72);
      children.add(
          TextSpan(text: s.text.substring(cutStart, cutEnd), style: style));
    }
    return TextSpan(
        style: base,
        children: children.isEmpty
            ? [TextSpan(text: block.plainText.substring(start, end))]
            : children);
  }

  double _lineHeight(ReaderBlock block, double w) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ё', style: blockTextStyle(block, fontSize)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: w);
    return painter.height;
  }

  double _measure(ReaderBlock block, int start, int end, double w) {
    final painter = TextPainter(
      text: _styledSlice(block, start, end),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: w);
    return painter.height;
  }

  /// Бинарный поиск максимального префикса text[pos:end], помещающегося
  /// в maxHeight при ширине w.
  int _fitText(ReaderBlock block, int pos, double w, double maxHeight) {
    final length = block.plainText.length;
    // быстрая проверка: весь остаток помещается?
    if (_measure(block, pos, length, w) <= maxHeight) {
      return length;
    }
    var lo = pos + 1;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_measure(block, pos, mid, w) <= maxHeight) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final text = block.plainText;
    // не резать посередине слова, если возможно
    if (lo < text.length) {
      var end = lo;
      while (end > pos + 1 && !_isBreakChar(text[end - 1])) {
        end--;
      }
      if (end > pos + 20) lo = end;
    }
    return lo;
  }

  bool _isBreakChar(String ch) =>
      ch == ' ' || ch == '\n' || ch == '-' || ch == '—' || ch == '«';
}
