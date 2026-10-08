import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/opds_models.dart';
import 'opds_parser.dart';

/// Клиент OPDS-каталога Флибусты.
class OpdsService {
  final http.Client _client;
  final String Function() _baseUrl;

  OpdsService({http.Client? client, required String Function() baseUrl})
      : _client = client ?? http.Client(),
        // ignore: prefer_initializing_formals
        _baseUrl = baseUrl;

  String get base => _baseUrl();

  Future<OpdsFeed> fetchFeed(String pathOrUrl) async {
    final parser = OpdsParser(base);
    final url = pathOrUrl.startsWith('http') ? pathOrUrl : parser.resolve(pathOrUrl);
    final resp = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw OpdsException('HTTP ${resp.statusCode} для $url');
    }
    return parser.parseFeed(utf8.decode(resp.bodyBytes));
  }

  Future<OpdsFeed> newReleases() => fetchFeed('/opds/new/0/new');

  Future<OpdsFeed> searchBooks(String query) => fetchFeed(
      '/opds/opensearch?searchType=books&searchTerm=${Uri.encodeComponent(query)}');

  Future<OpdsFeed> searchAuthors(String query) => fetchFeed(
      '/opds/search?searchType=authors&searchTerm=${Uri.encodeComponent(query)}');

  Future<OpdsFeed> searchSequences(String query) => fetchFeed(
      '/opds/search?searchType=sequences&searchTerm=${Uri.encodeComponent(query)}');

  Future<OpdsFeed> authorPage(String authorId) =>
      fetchFeed('/opds/author/$authorId');

  /// Потоковое скачивание файла книги с колбэком прогресса
  /// (null — размер неизвестен, индикатор indeterminate).
  Future<List<int>> downloadFile(
    String url, {
    void Function(double? progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw OpdsException('HTTP ${response.statusCode} при скачивании');
    }
    final total = response.contentLength ?? 0;
    final chunks = <int>[];
    var received = 0;
    await for (final chunk
        in response.stream.timeout(const Duration(minutes: 2))) {
      chunks.addAll(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call((received / total).clamp(0.0, 1.0));
      } else {
        onProgress?.call(null);
      }
    }
    return chunks;
  }
}

class OpdsException implements Exception {
  final String message;
  OpdsException(this.message);
  @override
  String toString() => message;
}
