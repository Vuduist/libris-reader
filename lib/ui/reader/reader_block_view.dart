import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/reader_models.dart';
import 'paginator.dart';

/// Рендер одного блока текста книги с выделением и кастомным меню:
/// «Заметка / Поиск / Копировать / Перевести».
///
/// Тапы по ссылкам (сноски) обрабатываются через Listener + hit-test
/// TextPainter'ом: TapGestureRecognizer на span внутри SelectableText
/// ненадёжен (конфликтует с жестом выделения).
class ReaderBlockView extends StatefulWidget {
  final ReaderBlock block;
  final double fontSize;
  final int start; // -1 = целый блок
  final int end;
  final double? imageMaxHeight; // для paged-режима — по формуле пагинатора
  final bool highlighted; // подсветка озвучиваемого абзаца (TTS)
  final void Function(String href) onLink;
  final void Function(String selectedText) onNote;
  final void Function(String selectedText) onSearch;
  final void Function(String selectedText) onTranslate;

  const ReaderBlockView({
    super.key,
    required this.block,
    required this.fontSize,
    this.start = -1,
    this.end = -1,
    this.imageMaxHeight,
    this.highlighted = false,
    required this.onLink,
    required this.onNote,
    required this.onSearch,
    required this.onTranslate,
  });

  @override
  State<ReaderBlockView> createState() => _ReaderBlockViewState();
}

class _ReaderBlockViewState extends State<ReaderBlockView> {
  Offset? _downPos;
  DateTime? _downTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = widget.block;

    if (block.type == BlockType.spacer) {
      return const SizedBox(height: 10);
    }
    if (block.type == BlockType.image) {
      final bytes = block.imageBytes;
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.imageMaxHeight ?? 380),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    }

    final base = blockTextStyle(block, widget.fontSize)
        .copyWith(color: theme.colorScheme.onSurface);
    final linkColor = theme.colorScheme.primary;

    var spans = block.spans;
    if (widget.start >= 0) {
      spans = _sliceSpans(spans, widget.start, widget.end);
    }

    final hasLinks = spans.any((s) => s.linkHref != null);

    final textSpans = spans.map((s) {
      var style = base;
      if (s.bold) {
        style = style.copyWith(fontWeight: FontWeight.bold);
      }
      if (s.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (s.sup) style = style.copyWith(fontSize: base.fontSize! * 0.72);
      if (s.linkHref != null) {
        style = style.copyWith(
            color: linkColor, decoration: TextDecoration.underline);
      }
      return TextSpan(text: s.text, style: style);
    }).toList();

    final textAlign = block.type == BlockType.h1 ||
            block.type == BlockType.h2 ||
            block.type == BlockType.h3
        ? TextAlign.center
        : TextAlign.start;
    final spanTree = TextSpan(children: textSpans);

    Widget textWidget = SelectableText.rich(
      spanTree,
      textAlign: textAlign,
      contextMenuBuilder: (context, selectableTextState) {
        final value = selectableTextState.textEditingValue;
        final sel = value.selection;
        String selected = '';
        if (sel.isValid && !sel.isCollapsed) {
          final s = sel.start.clamp(0, value.text.length);
          final e = sel.end.clamp(0, value.text.length);
          if (e > s) selected = value.text.substring(s, e);
        }
        ContextMenuButtonItem item(
                String label, void Function(String) action) =>
            ContextMenuButtonItem(label: label, onPressed: () {
              ContextMenuController.removeAny();
              if (selected.isNotEmpty) action(selected);
            });
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableTextState.contextMenuAnchors,
          buttonItems: [
            item('Заметка', widget.onNote),
            item('Поиск', widget.onSearch),
            ContextMenuButtonItem(label: 'Копировать', onPressed: () {
              ContextMenuController.removeAny();
              if (selected.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: selected));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Скопировано')));
              }
            }),
            item('Перевести', widget.onTranslate),
          ],
        );
      },
    );

    if (hasLinks) {
      // Listener получает pointer-события вне арены жестов выделения.
      textWidget = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (d) {
          _downPos = d.localPosition;
          _downTime = DateTime.now();
        },
        onPointerUp: (d) {
          final down = _downPos;
          final downTime = _downTime;
          _downPos = null;
          if (down == null || downTime == null) return;
          final moved = (d.localPosition - down).distance;
          final elapsed = DateTime.now().difference(downTime);
          if (moved > 12 || elapsed > const Duration(milliseconds: 600)) {
            return;
          }
          _hitTestLink(d.localPosition, spanTree, spans, textAlign);
        },
        child: textWidget,
      );
    }

    // у продолжения блока (start > 0) отступ сверху не рисуем —
    // пагинатор учитывает spacing только для первого куска блока
    final isContinuation = widget.start > 0;
    return Padding(
      padding: EdgeInsets.only(
        top: isContinuation ? 0 : blockSpacingBefore(block),
        left: block.type == BlockType.epigraph ? 32 : 0,
      ),
      child: widget.highlighted
          ? Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: textWidget,
            )
          : textWidget,
    );
  }

  /// Находит ссылку под точкой тапа (с расширенной зоной ~10px).
  void _hitTestLink(Offset local, TextSpan spanTree, List<ReaderSpan> spans,
      TextAlign textAlign) {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final painter = TextPainter(
      text: spanTree,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: render.size.width);

    var offset = 0;
    for (final s in spans) {
      final start = offset;
      offset += s.text.length;
      if (s.linkHref == null) continue;
      final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: offset));
      for (final box in boxes) {
        if (box.toRect().inflate(10).contains(local)) {
          widget.onLink(s.linkHref!);
          return;
        }
      }
    }
  }

  /// Вырезает диапазон символов [start, end) из списка спанов.
  List<ReaderSpan> _sliceSpans(List<ReaderSpan> spans, int start, int end) {
    final out = <ReaderSpan>[];
    var pos = 0;
    for (final s in spans) {
      final spanStart = pos;
      final spanEnd = pos + s.text.length;
      pos = spanEnd;
      if (spanEnd <= start || spanStart >= end) continue;
      final cutStart = start > spanStart ? start - spanStart : 0;
      final cutEnd = end < spanEnd ? end - spanStart : s.text.length;
      out.add(ReaderSpan(s.text.substring(cutStart, cutEnd),
          bold: s.bold, italic: s.italic, sup: s.sup, linkHref: s.linkHref));
    }
    return out;
  }
}
