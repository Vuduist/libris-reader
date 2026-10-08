import 'package:xml/xml.dart';

/// Ссылка на скачивание книги из OPDS-записи.
class DownloadLink {
  final String format; // epub, fb2, html, txt, rtf, mobi...
  final String url;

  const DownloadLink(this.format, this.url);
}

/// Автор из OPDS-записи.
class OpdsAuthor {
  final String name;
  final String? uri; // /a/{id}

  const OpdsAuthor(this.name, this.uri);

  String? get id {
    final u = uri;
    if (u == null) return null;
    final m = RegExp(r'/a/(\d+)').firstMatch(u);
    return m?.group(1);
  }
}

/// Книга из Atom-ленты OPDS.
class BookEntry {
  final String id; // flibusta id из /b/{id}/
  final String title;
  final List<OpdsAuthor> authors;
  final List<String> genres;
  final String? language;
  final String? format;
  final String? issued;
  final String annotation; // HTML-аннотация (уже декодированная)
  final String? coverUrl;
  final List<DownloadLink> downloads;

  const BookEntry({
    required this.id,
    required this.title,
    this.authors = const [],
    this.genres = const [],
    this.language,
    this.format,
    this.issued,
    this.annotation = '',
    this.coverUrl,
    this.downloads = const [],
  });

  String get authorsText => authors.map((a) => a.name).join(', ');
}

/// Навигационный элемент ленты (автор, серия, раздел страницы автора).
class NavEntry {
  final String title;
  final String href;
  final String? note; // например «889 книг»
  final String? imageUrl;
  final String? contentHtml; // для «Об авторе»

  const NavEntry({
    required this.title,
    required this.href,
    this.note,
    this.imageUrl,
    this.contentHtml,
  });
}

/// Результат разбора Atom-ленты.
class OpdsFeed {
  final String title;
  final List<BookEntry> books;
  final List<NavEntry> navs;
  final String? nextUrl;

  const OpdsFeed({
    this.title = '',
    this.books = const [],
    this.navs = const [],
    this.nextUrl,
  });
}

// ---- XML helpers ----

Iterable<XmlElement> childEls(XmlElement el, String local) =>
    el.childElements.where((e) => e.name.local == local);

XmlElement? childEl(XmlElement el, String local) {
  for (final e in el.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

String childText(XmlElement el, String local) =>
    childEl(el, local)?.innerText.trim() ?? '';
