import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/author_cubit.dart';
import '../../services/opds_service.dart';
import '../../utils/html_utils.dart';
import '../opds/opds_list_page.dart';

/// Страница автора: биография + разделы (generic OPDS-навигация).
class AuthorPage extends StatelessWidget {
  final String authorId;
  final String name;

  const AuthorPage({super.key, required this.authorId, this.name = ''});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) =>
          AuthorCubit(ctx.read<OpdsService>())..load(authorId, fallbackName: name),
      child: BlocBuilder<AuthorCubit, AuthorState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text(state.authorName.isEmpty
                  ? 'Книги автора'
                  : 'Книги автора ${state.authorName}'),
            ),
            body: _body(context, state),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, AuthorState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(child: Text('Ошибка: ${state.error}'));
    }
    final theme = Theme.of(context);
    final bio = state.bio;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (bio != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Об авторе',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (bio.imageUrl != null)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: bio.imageUrl!,
                          height: 180,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  if (bio.contentHtml != null) ...[
                    const SizedBox(height: 8),
                    _ExpandableText(text: stripHtml(bio.contentHtml!)),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        ...state.sections.map((s) => Card(
              child: ListTile(
                leading: const Icon(Icons.book_outlined),
                title: Text(s.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        OpdsListPage(url: s.href, title: s.title))),
              ),
            )),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText({required this.text});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final tooLong = text.length > 600;
    final shown = !_expanded && tooLong ? '${text.substring(0, 600)}…' : text;
    return InkWell(
      onTap: tooLong ? () => setState(() => _expanded = !_expanded) : null,
      child: Text(shown, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
