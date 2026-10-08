import 'package:html/parser.dart' as html_parser;

final _blockEndRe =
    RegExp(r'<br\s*/?>|</p>|</div>|</li>|</h[1-6]>', caseSensitive: false);

/// Убирает HTML-разметку, оставляя читаемый текст.
/// Блочные границы (<br>, </p>, </div>, </li>) превращаются в переводы строк.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  try {
    final prepared = html.replaceAll(_blockEndRe, '\n');
    final doc = html_parser.parse(prepared);
    final text = doc.body?.text ?? '';
    return text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
  } catch (_) {
    return html
        .replaceAll(_blockEndRe, '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }
}
