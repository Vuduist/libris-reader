/// Модель книги в локальной библиотеке (хранится как Map в Hive).
class LibraryBook {
  final String id;
  final String title;
  final List<String> authors;
  final String format; // epub / fb2 / ...
  final String filePath;
  final String? coverPath;
  final String? coverUrl;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool pinned;
  final int progressChapter;
  final double progressOffset; // scroll offset
  final int progressPage; // для paged-режима

  const LibraryBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.format,
    required this.filePath,
    this.coverPath,
    this.coverUrl,
    required this.addedAt,
    this.lastOpenedAt,
    this.pinned = false,
    this.progressChapter = 0,
    this.progressOffset = 0,
    this.progressPage = 0,
  });

  String get authorsText => authors.join(', ');

  bool get isReadable => format == 'epub' || format == 'fb2' || format == 'pdf';

  bool get isDjvu => format == 'djvu';

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'authors': authors,
        'format': format,
        'filePath': filePath,
        'coverPath': coverPath,
        'coverUrl': coverUrl,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'lastOpenedAt': lastOpenedAt?.millisecondsSinceEpoch,
        'pinned': pinned,
        'progressChapter': progressChapter,
        'progressOffset': progressOffset,
        'progressPage': progressPage,
      };

  factory LibraryBook.fromMap(Map map) => LibraryBook(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? '',
        authors: ((map['authors'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        format: (map['format'] as String?) ?? '',
        filePath: (map['filePath'] as String?) ?? '',
        coverPath: map['coverPath'] as String?,
        coverUrl: map['coverUrl'] as String?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['addedAt'] as int?) ?? 0),
        lastOpenedAt: map['lastOpenedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['lastOpenedAt'] as int),
        pinned: (map['pinned'] as bool?) ?? false,
        progressChapter: (map['progressChapter'] as int?) ?? 0,
        progressOffset: (map['progressOffset'] as num?)?.toDouble() ?? 0,
        progressPage: (map['progressPage'] as int?) ?? 0,
      );

  LibraryBook copyWith({
    DateTime? lastOpenedAt,
    bool? pinned,
    int? progressChapter,
    double? progressOffset,
    int? progressPage,
  }) =>
      LibraryBook(
        id: id,
        title: title,
        authors: authors,
        format: format,
        filePath: filePath,
        coverPath: coverPath,
        coverUrl: coverUrl,
        addedAt: addedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        pinned: pinned ?? this.pinned,
        progressChapter: progressChapter ?? this.progressChapter,
        progressOffset: progressOffset ?? this.progressOffset,
        progressPage: progressPage ?? this.progressPage,
      );
}

class BookNote {
  final String key;
  final String bookId;
  final String quote;
  final String text;
  final DateTime createdAt;

  const BookNote({
    required this.key,
    required this.bookId,
    required this.quote,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'bookId': bookId,
        'quote': quote,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory BookNote.fromMap(String key, Map map) => BookNote(
        key: key,
        bookId: (map['bookId'] as String?) ?? '',
        quote: (map['quote'] as String?) ?? '',
        text: (map['text'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as int?) ?? 0),
      );
}

class BookBookmark {
  final String key;
  final String bookId;
  final int chapter;
  final double offset;
  final int page;
  final String snippet;
  final DateTime createdAt;

  const BookBookmark({
    required this.key,
    required this.bookId,
    required this.chapter,
    required this.offset,
    required this.page,
    required this.snippet,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'bookId': bookId,
        'chapter': chapter,
        'offset': offset,
        'page': page,
        'snippet': snippet,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory BookBookmark.fromMap(String key, Map map) => BookBookmark(
        key: key,
        bookId: (map['bookId'] as String?) ?? '',
        chapter: (map['chapter'] as int?) ?? 0,
        offset: (map['offset'] as num?)?.toDouble() ?? 0,
        page: (map['page'] as int?) ?? 0,
        snippet: (map['snippet'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as int?) ?? 0),
      );
}
