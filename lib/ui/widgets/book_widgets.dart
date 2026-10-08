import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/opds_models.dart';
import '../../utils/html_utils.dart';

/// Обложка: локальный файл → сеть → placeholder.
class BookCover extends StatelessWidget {
  final String? coverPath;
  final String? coverUrl;
  final double? width;
  final double? height;
  final double radius;

  const BookCover({
    super.key,
    this.coverPath,
    this.coverUrl,
    this.width,
    this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    final path = coverPath;
    if (path != null && File(path).existsSync()) {
      child = Image.file(File(path),
          width: width, height: height, fit: BoxFit.cover);
    } else if (coverUrl != null && coverUrl!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: coverUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(context),
        errorWidget: (_, _, _) => _placeholder(context),
      );
    } else {
      child = _placeholder(context);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surface,
      child: Icon(Icons.menu_book,
          size: (width ?? 80) * 0.4,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
    );
  }
}

/// Карточка книги для горизонтальных списков Discover.
class BookCardSmall extends StatelessWidget {
  final String title;
  final String author;
  final String? coverUrl;
  final String? badge; // рейтинг LiveLib
  final VoidCallback? onTap;

  const BookCardSmall({
    super.key,
    required this.title,
    required this.author,
    this.coverUrl,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                BookCover(coverUrl: coverUrl, width: 120, height: 170),
                if (badge != null && badge!.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(badge!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Карточка книги в списке результатов поиска.
class BookListTile extends StatelessWidget {
  final BookEntry book;
  final VoidCallback? onTap;

  const BookListTile({super.key, required this.book, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(coverUrl: book.coverUrl, width: 64, height: 92),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (book.authorsText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(book.authorsText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ),
                    if (book.annotation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(stripHtml(book.annotation),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7))),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
