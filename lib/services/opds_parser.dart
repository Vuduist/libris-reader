import 'package:xml/xml.dart';

import '../models/opds_models.dart';

/// Парсер OPDS/Atom лент Флибусты.
class OpdsParser {
  final String baseUrl;

  OpdsParser(this.baseUrl);

  String resolve(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (!href.startsWith('/')) return '$base/$href';
    return '$base$href';
  }

  OpdsFeed parseFeed(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    final feed = doc.rootElement;
    final books = <BookEntry>[];
    final navs = <NavEntry>[];
    String? nextUrl;

    for (final link in childEls(feed, 'link')) {
      if (link.getAttribute('rel') == 'next') {
        final href = link.getAttribute('href');
        if (href != null) nextUrl = resolve(href);
      }
    }

    for (final entry in childEls(feed, 'entry')) {
      final isBook = childEls(entry, 'link').any((l) {
        final rel = l.getAttribute('rel') ?? '';
        return rel.contains('acquisition') &&
            (l.getAttribute('type') ?? '').startsWith('application/');
      });
      if (isBook) {
        books.add(_parseBook(entry));
      } else {
        final nav = _parseNav(entry);
        if (nav != null) navs.add(nav);
      }
    }

    return OpdsFeed(
      title: childText(feed, 'title'),
      books: books,
      navs: navs,
      nextUrl: nextUrl,
    );
  }

  BookEntry _parseBook(XmlElement entry) {
    final authors = <OpdsAuthor>[];
    for (final a in childEls(entry, 'author')) {
      authors.add(OpdsAuthor(childText(a, 'name'),
          childText(a, 'uri').isEmpty ? null : childText(a, 'uri')));
    }

    final genres = <String>[];
    for (final c in childEls(entry, 'category')) {
      final label = c.getAttribute('label') ?? c.getAttribute('term');
      if (label != null && label.isNotEmpty) genres.add(label);
    }

    String? cover;
    final downloads = <DownloadLink>[];
    String id = '';

    for (final link in childEls(entry, 'link')) {
      final rel = link.getAttribute('rel') ?? '';
      final type = link.getAttribute('type') ?? '';
      final href = link.getAttribute('href');
      if (href == null) continue;

      if (rel == 'http://opds-spec.org/image' && type.startsWith('image/')) {
        cover ??= resolve(href);
      }
      if (rel.contains('acquisition') && type.startsWith('application/')) {
        final fmt = _formatOf(type, href);
        if (fmt != null) {
          final url = resolve(href);
          downloads.add(DownloadLink(fmt, url));
          if (id.isEmpty) {
            final m = RegExp(r'/b/(\d+)/').firstMatch(href);
            if (m != null) id = m.group(1)!;
          }
        }
      }
    }
    if (id.isEmpty) {
      // fallback: из <id>tag:book:...</id> — используем хвост как id
      final raw = childText(entry, 'id');
      id = raw.contains(':') ? raw.split(':').last : raw;
    }

    return BookEntry(
      id: id,
      title: childText(entry, 'title'),
      authors: authors,
      genres: genres,
      language: childText(entry, 'language').isEmpty
          ? null
          : childText(entry, 'language'),
      format:
          childText(entry, 'format').isEmpty ? null : childText(entry, 'format'),
      issued:
          childText(entry, 'issued').isEmpty ? null : childText(entry, 'issued'),
      annotation: childText(entry, 'content'),
      coverUrl: cover,
      downloads: downloads,
    );
  }

  String? _formatOf(String type, String href) {
    switch (type) {
      case 'application/epub+zip':
        return 'epub';
      case 'application/fb2+zip':
      case 'application/fb2':
        return 'fb2';
      case 'application/html+zip':
        return 'html';
      case 'application/txt+zip':
        return 'txt';
      case 'application/rtf+zip':
        return 'rtf';
      case 'application/x-mobipocket-ebook':
        return 'mobi';
      case 'application/pdf':
        return 'pdf';
      case 'application/djvu':
      case 'application/x-djvu':
      case 'image/vnd.djvu':
      case 'image/x-djvu':
        return 'djvu';
    }
    if (href.contains('/pdf')) return 'pdf';
    if (href.contains('/djvu')) return 'djvu';
    if (href.contains('/epub')) return 'epub';
    if (href.contains('/fb2')) return 'fb2';
    return null;
  }

  NavEntry? _parseNav(XmlElement entry) {
    final title = childText(entry, 'title');
    String? href;
    String? image;
    for (final link in childEls(entry, 'link')) {
      final rel = link.getAttribute('rel') ?? '';
      final type = link.getAttribute('type') ?? '';
      final h = link.getAttribute('href');
      if (h == null) continue;
      if (rel.contains('image') && type.startsWith('image/')) {
        image ??= resolve(h);
      } else if (href == null &&
          (type.contains('atom+xml') || type.isEmpty) &&
          !rel.contains('search')) {
        href = resolve(h);
      }
    }
    if (href == null) return null;
    final content = childText(entry, 'content');
    final isHtml =
        (childEl(entry, 'content')?.getAttribute('type') ?? '') == 'text/html';
    return NavEntry(
      title: title,
      href: href,
      note: isHtml ? null : (content.isEmpty ? null : content),
      imageUrl: image,
      contentHtml: isHtml ? content : null,
    );
  }
}
