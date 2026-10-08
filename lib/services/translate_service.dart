import 'dart:convert';

import 'package:http/http.dart' as http;

/// Перевод через неофициальный endpoint Google Translate (gtx).
class TranslateService {
  final http.Client _client;

  TranslateService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> translate(String text) async {
    final hasCyrillic = RegExp(r'[а-яА-ЯёЁ]').hasMatch(text);
    final target = hasCyrillic ? 'en' : 'ru';
    final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$target&dt=t&q=${Uri.encodeComponent(text)}');
    final resp = await _client.get(url).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Ошибка перевода: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    final buffer = StringBuffer();
    for (final segment in data[0] as List<dynamic>) {
      final part = (segment as List<dynamic>)[0];
      if (part is String) buffer.write(part);
    }
    return buffer.toString();
  }
}
