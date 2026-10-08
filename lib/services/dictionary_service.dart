import 'dart:convert';

import 'package:http/http.dart' as http;

class DictResult {
  final String source; // 'Wikipedia (ru)' | 'Wiktionary'
  final String title;
  final String text;
  final String? imageUrl;
  final String? pageUrl;

  const DictResult({
    required this.source,
    required this.title,
    required this.text,
    this.imageUrl,
    this.pageUrl,
  });
}

/// Словарь: Wikipedia (ru) → Wiktionary → «ничего не найдено».
/// Все запросы параллельно и с таймаутом 8 с; rest_v1 имеет фолбэк на action API.
class DictionaryService {
  final http.Client _client;

  DictionaryService({http.Client? client}) : _client = client ?? http.Client();

  static const _punct = ' \t\n\r,.!?;:\'"()[]{}«»„“”‘’—–-…·*/';

  /// Убирает пунктуацию/пробелы по краям выделения («слово,» → «слово»).
  static String cleanTerm(String term) {
    var s = term;
    while (s.isNotEmpty && _punct.contains(s[0])) {
      s = s.substring(1);
    }
    while (s.isNotEmpty && _punct.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<DictResult?> lookup(String rawTerm) {
    final term = cleanTerm(rawTerm);
    if (term.isEmpty) return Future.value(null);
    // Параллельно: Wikipedia и Wiktionary; приоритет у Wikipedia.
    return Future.wait([_wikipedia(term), _wiktionary(term)])
        .then((r) => r[0] ?? r[1]);
  }

  Future<DictResult?> _wikipedia(String term) async =>
      await _wikipediaRest(term) ?? await _wikipediaAction(term);

  Future<DictResult?> _wikipediaRest(String term) async {
    try {
      final url = Uri.parse(
          'https://ru.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(term)}');
      final resp =
          await _client.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final extract = (json['extract'] as String?)?.trim() ?? '';
      if (extract.isEmpty) return null;
      return DictResult(
        source: 'Wikipedia (ru)',
        title: (json['title'] as String?) ?? term,
        text: extract,
        imageUrl: (json['thumbnail'] as Map<String, dynamic>?)?['source']
            as String?,
        pageUrl: (json['content_urls'] as Map<String, dynamic>?)?['desktop']
            ?['page'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Фолбэк, если rest_v1 недоступна: классический action API.
  Future<DictResult?> _wikipediaAction(String term) async {
    try {
      final url = Uri.parse(
          'https://ru.wikipedia.org/w/api.php?action=query&prop=extracts|info&explaintext=1&exintro=1&inprop=url&format=json&titles=${Uri.encodeComponent(term)}');
      final resp =
          await _client.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final pages =
          (json['query'] as Map<String, dynamic>?)?['pages'] as Map<String, dynamic>?;
      if (pages == null) return null;
      for (final page in pages.values) {
        final p = page as Map<String, dynamic>;
        if (p.containsKey('missing')) continue;
        final extract = (p['extract'] as String?)?.trim() ?? '';
        if (extract.isEmpty) continue;
        return DictResult(
          source: 'Wikipedia (ru)',
          title: (p['title'] as String?) ?? term,
          text: extract,
          pageUrl: p['fullurl'] as String?,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<DictResult?> _wiktionary(String term) async {
    try {
      final url = Uri.parse(
          'https://ru.wiktionary.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&titles=${Uri.encodeComponent(term)}');
      final resp =
          await _client.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final pages =
          (json['query'] as Map<String, dynamic>?)?['pages'] as Map<String, dynamic>?;
      if (pages == null) return null;
      for (final page in pages.values) {
        final p = page as Map<String, dynamic>;
        if (p.containsKey('missing')) continue;
        final extract = (p['extract'] as String?)?.trim() ?? '';
        if (extract.isEmpty) continue;
        final trimmed = extract.length > 3000
            ? '${extract.substring(0, 3000)}…'
            : extract;
        return DictResult(
          source: 'Wiktionary',
          title: (p['title'] as String?) ?? term,
          text: trimmed,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
