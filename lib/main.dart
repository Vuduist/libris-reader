import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'cubits/library_cubit.dart';
import 'cubits/settings_cubit.dart';
import 'services/dictionary_service.dart';
import 'services/library_storage.dart';
import 'services/livelib_service.dart';
import 'services/opds_service.dart';
import 'services/translate_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storage = LibraryStorage();
  await storage.init();

  final settingsCubit = SettingsCubit(prefs);
  final opds = OpdsService(baseUrl: () => settingsCubit.state.opdsBaseUrl);

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: opds),
        RepositoryProvider.value(value: storage),
        RepositoryProvider(create: (_) => LiveLibService()),
        RepositoryProvider(create: (_) => DictionaryService()),
        RepositoryProvider(create: (_) => TranslateService()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: settingsCubit),
          BlocProvider(create: (_) => LibraryCubit(storage)..reload()),
        ],
        child: const LibrisApp(),
      ),
    ),
  );
}
