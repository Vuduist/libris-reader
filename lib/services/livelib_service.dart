import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LiveLibBook {
  final String title;
  final String author;
  final String rating;
  final String? coverUrl;
  final String bookUrl;

  const LiveLibBook({
    required this.title,
    required this.author,
    required this.rating,
    this.coverUrl,
    required this.bookUrl,
  });
}

/// Парсер всероссийского рейтинга LiveLib (замена «Бестселлеров»).
class LiveLibService {
  static const topUrl = 'https://www.livelib.ru/books/top';

  final http.Client _client;

  LiveLibService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<LiveLibBook>> fetchTop({int limit = 20}) async {
    final resp = await _client.get(Uri.parse(topUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('LiveLib HTTP ${resp.statusCode}');
    }
    return parse(resp.body, limit: limit);
  }

  List<LiveLibBook> parse(String htmlText, {int limit = 20}) {
    final doc = html_parser.parse(htmlText);
    final result = <LiveLibBook>[];

    for (final titleLink in doc.querySelectorAll('a.book-item__title')) {
      if (result.length >= limit) break;
      final title = titleLink.text.trim();
      if (title.isEmpty) continue;
      final href = titleLink.attributes['href'] ?? '';
      final titleAttr = titleLink.attributes['title'] ?? '';

      final container = _findContainer(titleLink);

      String author = '';
      final authorEl = container?.querySelector('a.book-item__author');
      if (authorEl != null) {
        author = authorEl.text.trim();
      } else if (titleAttr.contains(' - ')) {
        author = titleAttr.split(' - ').first.trim();
      }

      String rating = '';
      final ratingEl = container?.querySelector('div.book-item__rating');
      if (ratingEl != null) rating = ratingEl.text.trim();

      String? cover;
      final img = container?.querySelector('img[data-pagespeed-lazy-src]');
      if (img != null) {
        cover = img.attributes['data-pagespeed-lazy-src'];
      }
      if (cover != null && cover.startsWith('/')) {
        cover = 'https://www.livelib.ru$cover';
      }

      result.add(LiveLibBook(
        title: title,
        author: author,
        rating: rating,
        coverUrl: cover,
        bookUrl: href.startsWith('http') ? href : 'https://www.livelib.ru$href',
      ));
    }
    return result;
  }

  /// Поднимается от ссылки-названия до блока карточки,
  /// содержащего рейтинг / обложку.
  dom.Element? _findContainer(dom.Element titleLink) {
    dom.Element? el = titleLink.parent;
    for (var i = 0; i < 8 && el != null; i++) {
      if (el.querySelector('div.book-item__rating') != null ||
          el.querySelector('img[data-pagespeed-lazy-src]') != null) {
        return el;
      }
      el = el.parent;
    }
    return null;
  }
}
