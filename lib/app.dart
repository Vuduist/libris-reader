import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubits/settings_cubit.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

class LibrisApp extends StatelessWidget {
  const LibrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settings) {
        final isSepia = settings.themeMode == AppThemeMode.sepia;
        final ThemeMode mode;
        switch (settings.themeMode) {
          case AppThemeMode.system:
            mode = ThemeMode.system;
            break;
          case AppThemeMode.light:
            mode = ThemeMode.light;
            break;
          case AppThemeMode.dark:
            mode = ThemeMode.dark;
            break;
          case AppThemeMode.sepia:
            mode = ThemeMode.light;
            break;
        }
        return MaterialApp(
          title: 'Libris Reader',
          debugShowCheckedModeBanner: false,
          theme: isSepia ? AppTheme.sepia() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const Shell(),
        );
      },
    );
  }
}
