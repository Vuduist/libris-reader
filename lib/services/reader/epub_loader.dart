import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/reader_models.dart';
import 'html_blocks_parser.dart';

/// Загрузчик EPUB на пакете epubx.
class EpubLoader {
  Future<ReaderBook> load(List<int> bytes) async {
    final book = await EpubReader.readBook(bytes);

    final images = <String, Uint8List>{};
    book.Content?.Images?.forEach((name, file) {
      final content = file.Content;
      if (content != null) images[name] = Uint8List.fromList(content);
    });

    Uint8List? resolveImage(String src) {
      if (images.isEmpty) return null;
      if (images.containsKey(src)) return images[src];
      final norm = src.replaceAll('\\', '/');
      final base = norm.split('/').last.toLowerCase();
      for (final entry in images.entries) {
        final key = entry.key.replaceAll('\\', '/');
        if (key.toLowerCase().endsWith(base)) return entry.value;
        if (norm.isNotEmpty && key.endsWith(norm)) return entry.value;
      }
      return null;
    }

    final parser = HtmlBlocksParser(imageResolver: resolveImage);
    final chapters = <ReaderChapter>[];
    final footnotes = <String, String>{};

    var flat = _flatten(book.Chapters ?? const []);
    // Фолбэк: если TOC пуст, идём по spine/manifest.
    if (flat.isEmpty) {
      flat = _fromSpine(book);
    }
    // Якоря глав из TOC — это навигация, а не сноски.
    final chapterAnchors = <String>{
      for (final ch in flat)
        if ((ch.Anchor ?? '').isNotEmpty) ch.Anchor!,
    };

    for (final ch in flat) {
      final htmlContent = ch.HtmlContent;
      if (htmlContent == null || htmlContent.trim().isEmpty) continue;
      final doc = html_parser.parse(_sanitizeXhtml(htmlContent));
      final body = doc.body;
      if (body == null) continue;
      _collectFootnotes(body, footnotes, chapterAnchors);
      final blocks = parser.parse(body);
      if (blocks.isEmpty) continue;
      chapters.add(ReaderChapter(
        title: (ch.Title ?? '').trim().isEmpty
            ? 'Глава ${chapters.length + 1}'
            : ch.Title!.trim(),
        href: ch.ContentFileName ?? '',
        blocks: blocks,
      ));
    }

    // Сноски могут лежать в отдельных XHTML-файлах — сканируем всё содержимое.
    _collectAllFootnotes(book.Content?.Html ?? const {}, footnotes, chapterAnchors);

    return ReaderBook(
      title: book.Title ?? '',
      authors:
          (book.AuthorList ?? const []).whereType<String>().join(', '),
      chapters: chapters,
      footnotes: footnotes,
    );
  }

  /// HTML-парсер не понимает самозакрывающиеся raw-text теги XHTML
  /// (`<title/>` поглощает весь документ) — нормализуем их.
  static final _selfClosingRawText = RegExp(
      r'<(title|script|style|textarea|iframe|noembed|noframes|noscript|xmp|plaintext)(\s[^>]*)?/>',
      caseSensitive: false);

  String _sanitizeXhtml(String s) {
    var out = s.replaceAll(RegExp(r'<\?xml[^?]*\?>'), '');
    out = out.replaceAllMapped(
        _selfClosingRawText, (m) => '<${m[1]}${m[2] ?? ''}></${m[1]}>');
    return out;
  }

  List<EpubChapter> _flatten(List<EpubChapter> chapters) {
    final out = <EpubChapter>[];
    for (final ch in chapters) {
      out.add(ch);
      out.addAll(_flatten(ch.SubChapters ?? const []));
    }
    return out;
  }

  /// Строит список глав из spine (reading order), когда TOC пуст.
  List<EpubChapter> _fromSpine(EpubBook book) {
    final out = <EpubChapter>[];
    final manifest = <String, EpubManifestItem>{};
    for (final item in book.Schema?.Package?.Manifest?.Items ?? const []) {
      final id = item.Id;
      if (id != null) manifest[id] = item;
    }
    final htmlFiles = book.Content?.Html ?? const <String, EpubTextContentFile>{};
    var n = 0;
    for (final spineItem
        in book.Schema?.Package?.Spine?.Items ?? const []) {
      final item = manifest[spineItem.IdRef];
      final href = item?.Href;
      if (href == null) continue;
      EpubTextContentFile? file = htmlFiles[href];
      if (file == null) {
        final base = href.split('/').last.toLowerCase();
        for (final entry in htmlFiles.entries) {
          if (entry.key.toLowerCase().endsWith(base)) {
            file = entry.value;
            break;
          }
        }
      }
      final content = file?.Content;
      if (content == null || content.trim().isEmpty) continue;
      n++;
      out.add(EpubChapter()
        ..Title = 'Глава $n'
        ..ContentFileName = href
        ..HtmlContent = content
        ..SubChapters = const []);
    }
    return out;
  }

  static const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

  /// Собирает карту сносок по одному документу.
  void _collectFootnotes(
      dom.Element body, Map<String, String> out, Set<String> skip) {
    final ids = <String, dom.Element>{};
    for (final el in body.querySelectorAll('[id]')) {
      ids[el.attributes['id']!] = el;
    }
    if (ids.isEmpty) return;
    for (final a in body.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final isNoteref =
          (a.attributes['epub:type'] ?? a.attributes['type'] ?? '') ==
              'noteref';
      final frag = href.contains('#') ? href.split('#').last : '';
      if (frag.isEmpty || skip.contains(frag)) continue;
      final target = ids[frag];
      if (target == null || out.containsKey(frag)) continue;
      if (_footnoteText(target, href, isNoteref) case final text?) {
        out[frag] = text;
      }
    }
  }

  /// Решает, является ли target сноской, и возвращает её текст.
  /// Явные признаки: noteref-ссылка, epub:type=note/footnote/rearnote, aside.
  /// Эвристика для генераторов без epub:type (Флибуста): небольшой
  /// незаголовочный элемент, причём cross-file ссылки (отдельный файл сносок)
  /// считаем сносками всегда, same-file — только «листовые» элементы.
  String? _footnoteText(dom.Element target, String href, bool isNoteref) {
    if (_headingTags.contains(target.localName)) return null;
    final text = target.text.trim();
    if (text.isEmpty || text.length >= 5000) return null;
    if (isNoteref || _isNoteElement(target)) return text;
    final crossFile = !href.startsWith('#');
    if (crossFile) return text;
    if (text.length < 2000 && target.children.isEmpty) return text;
    return null;
  }

  static final _hrefFragRe =
      RegExp(r'''href="([^"]*)#([A-Za-z0-9_\-]+)"''');
  static final _noterefRe = RegExp(
      r'''<a\b[^>]*(?:epub:type="noteref"[^>]*href="[^"]*#([A-Za-z0-9_\-]+)"|href="[^"]*#([A-Za-z0-9_\-]+)"[^>]*epub:type="noteref")''');

  static bool _isNoteElement(dom.Element el) {
    final type = el.attributes['epub:type'] ?? el.attributes['type'] ?? '';
    return type == 'note' ||
        type == 'footnote' ||
        type == 'rearnote' ||
        el.localName == 'aside';
  }

  /// Сноски могут быть в других файлах книги: сначала собираем все
  /// используемые фрагменты #id (и отдельно noteref), затем вытаскиваем
  /// тексты note-элементов из всех XHTML.
  void _collectAllFootnotes(Map<String, EpubTextContentFile> htmlFiles,
      Map<String, String> out, Set<String> skip) {
    final wanted = <String, bool>{}; // id -> была ли cross-file ссылка
    final noterefIds = <String>{};
    for (final file in htmlFiles.values) {
      final content = file.Content;
      if (content == null) continue;
      for (final m in _hrefFragRe.allMatches(content)) {
        final id = m.group(2)!;
        final crossFile = (m.group(1) ?? '').isNotEmpty;
        wanted[id] = (wanted[id] ?? false) || crossFile;
      }
      for (final m in _noterefRe.allMatches(content)) {
        noterefIds.add(m.group(1) ?? m.group(2)!);
      }
    }
    wanted.removeWhere((id, _) => out.containsKey(id) || skip.contains(id));
    if (wanted.isEmpty) return;
    for (final file in htmlFiles.values) {
      if (wanted.isEmpty) break;
      final content = file.Content;
      if (content == null) continue;
      // быстрый фильтр: есть ли в файле хоть один нужный id
      final hits =
          wanted.keys.where((id) => content.contains('id="$id"')).toList();
      if (hits.isEmpty) continue;
      final doc = html_parser.parse(_sanitizeXhtml(content));
      final body = doc.body;
      if (body == null) continue;
      for (final el in body.querySelectorAll('[id]')) {
        final id = el.attributes['id']!;
        final crossFile = wanted[id];
        if (crossFile == null || out.containsKey(id)) continue;
        final text = _footnoteText(el, crossFile ? 'x#$id' : '#$id',
            noterefIds.contains(id));
        if (text != null) {
          out[id] = text;
          wanted.remove(id);
        }
      }
    }
  }
}
