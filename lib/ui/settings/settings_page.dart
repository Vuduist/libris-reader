import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/settings_cubit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
        text: context.read<SettingsCubit>().state.opdsBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Настройки')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _section(
                context,
                'Оформление',
                RadioGroup<AppThemeMode>(
                  groupValue: state.themeMode,
                  onChanged: (v) {
                    if (v != null) {
                      context.read<SettingsCubit>().setThemeMode(v);
                    }
                  },
                  child: Column(children: const [
                    RadioListTile(
                        value: AppThemeMode.system, title: Text('Системная')),
                    RadioListTile(
                        value: AppThemeMode.light, title: Text('Светлая')),
                    RadioListTile(
                        value: AppThemeMode.dark, title: Text('Темная')),
                    RadioListTile(
                        value: AppThemeMode.sepia,
                        title: Text('Сепия (Охра)')),
                  ]),
                ),
              ),
              _section(
                context,
                'Режим чтения',
                RadioGroup<ReadingMode>(
                  groupValue: state.readingMode,
                  onChanged: (v) {
                    if (v != null) {
                      context.read<SettingsCubit>().setReadingMode(v);
                    }
                  },
                  child: Column(children: const [
                    RadioListTile(
                        value: ReadingMode.paged,
                        title: Text('По страницам (горизонтально)')),
                    RadioListTile(
                        value: ReadingMode.scroll,
                        title: Text('Скролл (вертикально)')),
                  ]),
                ),
              ),
              _section(
                context,
                'Каталог',
                Column(children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                          labelText: 'Адрес каталога OPDS',
                          hintText: 'https://m.flibusta.is'),
                      onSubmitted: (v) =>
                          context.read<SettingsCubit>().setOpdsBaseUrl(v),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(children: [
                      FilledButton.tonal(
                        onPressed: () => context
                            .read<SettingsCubit>()
                            .setOpdsBaseUrl(_urlController.text),
                        child: const Text('Сохранить'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          context.read<SettingsCubit>().resetOpdsBaseUrl();
                          _urlController.text = SettingsCubit.defaultBaseUrl;
                        },
                        child: const Text('Сбросить'),
                      ),
                    ]),
                  ),
                ]),
              ),
              _section(
                context,
                'О приложении',
                const ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('Libris Reader Beta'),
                  subtitle: Text('Версия 1.0.0'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
        ),
        Card(child: child),
      ],
    );
  }
}
