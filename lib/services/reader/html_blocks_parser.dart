import 'dart:typed_data';

import 'package:html/dom.dart' as dom;

import '../../models/reader_models.dart';

typedef ImageResolver = Uint8List? Function(String src);

/// Парсер HTML/XHTML в список ReaderBlock (для EPUB).
class HtmlBlocksParser {
  final ImageResolver? imageResolver;

  HtmlBlocksParser({this.imageResolver});

  List<ReaderBlock> parse(dom.Element root) {
    final blocks = <ReaderBlock>[];
    _walkBlock(root, blocks, insideEpigraph: false);
    return blocks;
  }

  void _walkBlock(dom.Element el, List<ReaderBlock> out,
      {required bool insideEpigraph}) {
    for (final node in el.nodes) {
      if (node is dom.Text) {
        final t = _collapse(node.text);
        if (t.trim().isNotEmpty) {
          out.add(ReaderBlock(
              insideEpigraph ? BlockType.epigraph : BlockType.paragraph,
              [ReaderSpan(t)]));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';

      if (tag == 'img') {
        _addImage(node, out);
        continue;
      }
      if (tag == 'svg') continue; // svg пропускаем

      switch (tag) {
        case 'h1':
          _addTextBlock(node, BlockType.h1, out);
          break;
        case 'h2':
          _addTextBlock(node, BlockType.h2, out);
          break;
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          _addTextBlock(node, BlockType.h3, out);
          break;
        case 'p':
          _addTextBlock(
              node, insideEpigraph ? BlockType.epigraph : BlockType.paragraph,
              out);
          break;
        case 'blockquote':
          _walkBlock(node, out, insideEpigraph: true);
          break;
        case 'br':
        case 'hr':
          break;
        case 'script':
        case 'style':
        case 'head':
          break;
        case 'div':
        case 'section':
        case 'body':
        case 'article':
        case 'aside':
        case 'main':
          final cls = node.attributes['class'] ?? '';
          final isEpigraph = insideEpigraph ||
              cls.toLowerCase().contains('epigraph') ||
              cls.toLowerCase().contains('epigraph');
          _walkBlock(node, out, insideEpigraph: isEpigraph);
          break;
        case 'ul':
        case 'ol':
          for (final li in node.children) {
            if (li.localName == 'li') {
              _addTextBlock(
                  li,
                  insideEpigraph ? BlockType.epigraph : BlockType.paragraph,
                  out,
                  prefix: '• ');
            }
          }
          break;
        default:
          if (_hasBlockChildren(node)) {
            _walkBlock(node, out, insideEpigraph: insideEpigraph);
          } else {
            _addTextBlock(node,
                insideEpigraph ? BlockType.epigraph : BlockType.paragraph,
                out);
          }
      }
    }
  }

  static const _blockTags = {
    'p', 'div', 'section', 'article', 'aside', 'main', 'blockquote',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'table', 'hr', 'pre',
    'img', 'figure', 'figcaption',
  };

  bool _hasBlockChildren(dom.Element el) {
    for (final c in el.children) {
      if (_blockTags.contains(c.localName) || _hasBlockChildren(c)) {
        return true;
      }
    }
    return false;
  }

  void _addImage(dom.Element img, List<ReaderBlock> out) {
    final src = img.attributes['src'] ?? img.attributes['xlink:href'] ?? '';
    if (src.isEmpty) return;
    final bytes = imageResolver?.call(src);
    if (bytes != null && bytes.isNotEmpty) {
      out.add(ReaderBlock(BlockType.image, const [], bytes));
    }
  }

  void _addTextBlock(dom.Element el, BlockType type, List<ReaderBlock> out,
      {String? prefix}) {
    final spans = <ReaderSpan>[];
    if (prefix != null) spans.add(ReaderSpan(prefix));
    _walkInline(el, spans, const _InlineStyle());
    final cleaned = _trimSpans(spans);
    if (cleaned.isNotEmpty) out.add(ReaderBlock(type, cleaned));
  }

  void _walkInline(dom.Node node, List<ReaderSpan> out, _InlineStyle style) {
    if (node is dom.Text) {
      final t = _collapse(node.text);
      if (t.isNotEmpty) {
        out.add(ReaderSpan(t,
            bold: style.bold,
            italic: style.italic,
            sup: style.sup,
            linkHref: style.link));
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    var s = style;
    switch (tag) {
      case 'b':
      case 'strong':
        s = s.copyWith(bold: true);
        break;
      case 'i':
      case 'em':
        s = s.copyWith(italic: true);
        break;
      case 'sup':
      case 'sub':
        s = s.copyWith(sup: true);
        break;
      case 'a':
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) s = s.copyWith(link: href);
        break;
      case 'script':
      case 'style':
        return;
      case 'img':
        // inline-картинки игнорируем в тексте
        return;
      case 'br':
        out.add(ReaderSpan('\n',
            bold: style.bold, italic: style.italic, linkHref: style.link));
        return;
    }
    for (final child in node.nodes) {
      _walkInline(child, out, s);
    }
  }

  List<ReaderSpan> _trimSpans(List<ReaderSpan> spans) {
    // убираем пустые и подрезаем края
    final list = spans.where((s) => s.text.isNotEmpty).toList();
    if (list.isEmpty) return list;
    final first = list.first;
    final firstText = first.text.trimLeft();
    list[0] = ReaderSpan(firstText,
        bold: first.bold,
        italic: first.italic,
        sup: first.sup,
        linkHref: first.linkHref);
    final last = list.last;
    final lastText = last.text.trimRight();
    list[list.length - 1] = ReaderSpan(lastText,
        bold: last.bold,
        italic: last.italic,
        sup: last.sup,
        linkHref: last.linkHref);
    return list.where((s) => s.text.isNotEmpty).toList();
  }

  static String _collapse(String s) =>
      s.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'[ \t]+'), ' ');
}

class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool sup;
  final String? link;

  const _InlineStyle(
      {this.bold = false, this.italic = false, this.sup = false, this.link});

  _InlineStyle copyWith({bool? bold, bool? italic, bool? sup, String? link}) =>
      _InlineStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        sup: sup ?? this.sup,
        link: link ?? this.link,
      );
}
