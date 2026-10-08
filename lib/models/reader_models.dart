import 'dart:typed_data';

/// Инлайн-фрагмент текста с форматированием.
class ReaderSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool sup;
  final String? linkHref;

  const ReaderSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.sup = false,
    this.linkHref,
  });
}

enum BlockType { h1, h2, h3, paragraph, epigraph, image, spacer }

class ReaderBlock {
  final BlockType type;
  final List<ReaderSpan> spans;
  final Uint8List? imageBytes;

  const ReaderBlock(this.type, [this.spans = const [], this.imageBytes]);

  String get plainText => spans.map((s) => s.text).join();

  bool get isEmpty => type != BlockType.image && plainText.trim().isEmpty;
}

class ReaderChapter {
  final String title;
  final String href; // имя файла в epub / '' для fb2
  final List<ReaderBlock> blocks;

  const ReaderChapter({
    required this.title,
    required this.href,
    required this.blocks,
  });

  String get firstParagraphText {
    for (final b in blocks) {
      if (b.type == BlockType.paragraph || b.type == BlockType.epigraph) {
        final t = b.plainText.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }
}

class ReaderBook {
  final String title;
  final String authors;
  final List<ReaderChapter> chapters;
  final Map<String, String> footnotes; // id -> текст сноски

  const ReaderBook({
    required this.title,
    required this.authors,
    required this.chapters,
    this.footnotes = const {},
  });
}
