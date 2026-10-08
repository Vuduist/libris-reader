import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import 'cp1251.dart';

import '../../models/reader_models.dart';

/// Загрузчик FB2 (в том числе упакованного в zip).
class Fb2Loader {
  Future<ReaderBook> load(List<int> bytes) async {
    var data = bytes;
    // fb2+zip: распаковать и найти .fb2
    if (data.length >= 2 && data[0] == 0x50 && data[1] == 0x4B) {
      final archive = ZipDecoder().decodeBytes(data);
      ArchiveFile? fb2File;
      for (final f in archive.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.fb2')) {
          fb2File = f;
          break;
        }
      }
      fb2File ??= archive.files.firstWhere((f) => f.isFile);
      data = fb2File.content as List<int>;
    }

    final text = _decode(data);
    final doc = _parseLenient(text);
    final root = doc.rootElement;

    // обложки и картинки
    final binaries = <String, Uint8List>{};
    for (final bin in root.childElements.where((e) => e.name.local == 'binary')) {
      final id = bin.getAttribute('id');
      if (id == null) continue;
      try {
        binaries[id] = Uint8List.fromList(base64Decode(bin.innerText.trim()));
      } catch (_) {}
    }

    String title = '';
    final authors = <String>[];
    final description = root.childElements
        .where((e) => e.name.local == 'description')
        .firstOrNull;
    if (description != null) {
      final titleInfo = description.childElements
          .where((e) => e.name.local == 'title-info')
          .firstOrNull;
      if (titleInfo != null) {
        title = _firstText(titleInfo, 'book-title');
        for (final a
            in titleInfo.childElements.where((e) => e.name.local == 'author')) {
          final last = _firstText(a, 'last-name');
          final first = _firstText(a, 'first-name');
          final middle = _firstText(a, 'middle-name');
          final name = [last, first, middle]
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          if (name.isNotEmpty) authors.add(name);
        }
      }
    }

    final bodies =
        root.childElements.where((e) => e.name.local == 'body').toList();
    XmlElement? mainBody;
    final footnotes = <String, String>{};
    for (final body in bodies) {
      final name = body.getAttribute('name') ?? '';
      if (name.isEmpty && mainBody == null) {
        mainBody = body;
      } else if (name == 'notes' || name == 'comments') {
        for (final section
            in body.childElements.where((e) => e.name.local == 'section')) {
          final id = section.getAttribute('id');
          if (id == null) continue;
          final blocks = <ReaderBlock>[];
          _parseSection(section, blocks, binaries, depth: 1);
          final text = blocks
              .map((b) => b.plainText.trim())
              .where((t) => t.isNotEmpty)
              .join('\n');
          if (text.isNotEmpty) footnotes[id] = text;
        }
      }
    }

    final blocks = <ReaderBlock>[];
    if (mainBody != null) {
      for (final child in mainBody.childElements) {
        if (child.name.local == 'section') {
          _parseSection(child, blocks, binaries, depth: 1);
        } else if (child.name.local == 'title') {
          // заголовок книги в body пропускаем
        }
      }
    }

    // Режем плоский список блоков на главы по заголовкам верхнего уровня.
    final chapters = _splitChapters(blocks);

    return ReaderBook(
      title: title,
      authors: authors.join(', '),
      chapters: chapters,
      footnotes: footnotes,
    );
  }

  List<ReaderChapter> _splitChapters(List<ReaderBlock> blocks) {
    final chapters = <ReaderChapter>[];
    var current = <ReaderBlock>[];
    var currentTitle = '';
    void flush() {
      if (current.isEmpty) return;
      chapters.add(ReaderChapter(
        title: currentTitle.isEmpty
            ? 'Глава ${chapters.length + 1}'
            : currentTitle,
        href: '',
        blocks: current,
      ));
      current = [];
    }

    for (final block in blocks) {
      final isHeading =
          block.type == BlockType.h2 || block.type == BlockType.h3;
      if (isHeading) {
        if (current.isNotEmpty) flush();
        currentTitle = block.plainText.trim();
        continue;
      }
      current.add(block);
    }
    flush();
    if (chapters.isEmpty && blocks.isNotEmpty) {
      chapters.add(ReaderChapter(title: 'Текст', href: '', blocks: blocks));
    }
    return chapters;
  }

  void _parseSection(XmlElement section, List<ReaderBlock> out,
      Map<String, Uint8List> binaries,
      {required int depth}) {
    for (final el in section.childElements) {
      switch (el.name.local) {
        case 'title':
          final parts = <String>[];
          final ps =
              el.childElements.where((e) => e.name.local == 'p').toList();
          if (ps.isEmpty) {
            final spans = _parseInline(el);
            if (spans.isNotEmpty) {
              out.add(ReaderBlock(
                  depth <= 1 ? BlockType.h2 : BlockType.h3, spans));
            }
          } else {
            for (final p in ps) {
              final t =
                  _parseInline(p).map((s) => s.text).join().trim();
              if (t.isNotEmpty) parts.add(t);
            }
            if (parts.isNotEmpty) {
              out.add(ReaderBlock(depth <= 1 ? BlockType.h2 : BlockType.h3,
                  [ReaderSpan(parts.join(' '))]));
            }
          }
          break;
        case 'epigraph':
          _parseFlow(el, out, binaries, BlockType.epigraph, depth);
          break;
        case 'section':
          _parseSection(el, out, binaries, depth: depth + 1);
          break;
        case 'image':
          _addImage(el, out, binaries);
          break;
        case 'empty-line':
          out.add(const ReaderBlock(BlockType.spacer));
          break;
        case 'p':
        case 'v':
        case 'subtitle':
        case 'text-author':
          final spans = _parseInline(el);
          if (spans.isNotEmpty) out.add(ReaderBlock(BlockType.paragraph, spans));
          break;
        case 'poem':
        case 'cite':
          _parseFlow(el, out, binaries, BlockType.paragraph, depth);
          break;
        default:
          _parseFlow(el, out, binaries, BlockType.paragraph, depth);
      }
    }
  }

  void _parseFlow(XmlElement el, List<ReaderBlock> out,
      Map<String, Uint8List> binaries, BlockType type, int depth) {
    for (final child in el.childElements) {
      switch (child.name.local) {
        case 'p':
          final spans = _parseInline(child);
          if (spans.isNotEmpty) out.add(ReaderBlock(type, spans));
          break;
        case 'poem':
          _parseFlow(child, out, binaries, type, depth);
          break;
        case 'stanza':
          _parseFlow(child, out, binaries, type, depth);
          out.add(const ReaderBlock(BlockType.spacer));
          break;
        case 'v':
        case 'subtitle':
          final spans = _parseInline(child);
          if (spans.isNotEmpty) out.add(ReaderBlock(type, spans));
          break;
        case 'empty-line':
          out.add(const ReaderBlock(BlockType.spacer));
          break;
        case 'image':
          _addImage(child, out, binaries);
          break;
        case 'cite':
          _parseFlow(child, out, binaries, BlockType.epigraph, depth);
          break;
        case 'section':
          _parseSection(child, out, binaries, depth: depth + 1);
          break;
      }
    }
  }

  void _addImage(XmlElement el, List<ReaderBlock> out,
      Map<String, Uint8List> binaries) {
    final href = _lHref(el);
    if (href == null) return;
    final id = href.startsWith('#') ? href.substring(1) : href;
    final bytes = binaries[id];
    if (bytes != null && bytes.isNotEmpty) {
      out.add(ReaderBlock(BlockType.image, const [], bytes));
    }
  }

  String? _lHref(XmlElement el) {
    for (final attr in el.attributes) {
      if (attr.name.local == 'href') return attr.value;
    }
    return null;
  }

  List<ReaderSpan> _parseInline(XmlElement el) {
    final spans = <ReaderSpan>[];
    void walk(XmlNode node,
        {bool bold = false, bool italic = false, bool sup = false, String? link}) {
      if (node is XmlText || node is XmlCDATA) {
        var t = (node.value ?? '').replaceAll('\u00A0', ' ');
        if (t.isEmpty) return;
        // whitespace-ноду не выкидываем (иначе склейка слов) — схлопываем в пробел
        if (t.trim().isEmpty) t = ' ';
        spans.add(ReaderSpan(t,
            bold: bold, italic: italic, sup: sup, linkHref: link));
        return;
      }
      if (node is! XmlElement) return;
      var b = bold, i = italic, s = sup;
      var l = link;
      switch (node.name.local) {
        case 'strong':
          b = true;
          break;
        case 'emphasis':
          i = true;
          break;
        case 'sup':
        case 'sub':
          s = true;
          break;
        case 'a':
          final href = _lHref(node);
          if (href != null) l = href;
          break;
        case 'strikethrough':
        case 'code':
          break;
      }
      for (final child in node.children) {
        walk(child, bold: b, italic: i, sup: s, link: l);
      }
    }

    for (final child in el.children) {
      walk(child);
    }
    if (spans.isEmpty) return spans;
    // trim краёв
    final first = spans.first;
    spans[0] = ReaderSpan(first.text.trimLeft(),
        bold: first.bold,
        italic: first.italic,
        sup: first.sup,
        linkHref: first.linkHref);
    final last = spans.last;
    spans[spans.length - 1] = ReaderSpan(last.text.trimRight(),
        bold: last.bold,
        italic: last.italic,
        sup: last.sup,
        linkHref: last.linkHref);
    return spans.where((s) => s.text.isNotEmpty).toList();
  }

  static final _voidTagRe =
      RegExp(r'<(hr|br|base|link|meta)\b[^>]*?/?>', caseSensitive: false);

  /// Строгий XML-парсинг с фолбэком: FB2 иногда содержит HTML-изоморфные
  /// незакрытые теги (<hr>, <br>) и HTML-сущности (&nbsp;).
  XmlDocument _parseLenient(String text) {
    try {
      return XmlDocument.parse(text);
    } catch (_) {
      final fixed = text
          .replaceAllMapped(_voidTagRe, (m) => '<${m[1]!.toLowerCase()}/>')
          .replaceAll('&nbsp;', '&#160;')
          .replaceAll('&mdash;', '&#8212;')
          .replaceAll('&laquo;', '&#171;')
          .replaceAll('&raquo;', '&#187;');
      return XmlDocument.parse(fixed);
    }
  }

  String _firstText(XmlElement el, String local) => el.childElements
      .where((e) => e.name.local == local)
      .map((e) => e.innerText.trim())
      .firstOrNull ??
      '';

  static final _encodingRe =
      RegExp(r'''encoding\s*=\s*["']([\w\-]+)["']''', caseSensitive: false);

  String _decode(List<int> bytes) {
    // читаем encoding из XML-пролога (сам пролог ASCII-совместим)
    final headLength = bytes.length < 256 ? bytes.length : 256;
    final head = latin1.decode(bytes.sublist(0, headLength));
    final encoding = _encodingRe.firstMatch(head)?.group(1)?.toLowerCase();
    if (encoding != null &&
        (encoding.contains('1251') || encoding == 'cp1251')) {
      return decodeCp1251(bytes);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
