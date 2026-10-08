import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark, sepia }

enum ReadingMode { scroll, paged }

class SettingsState extends Equatable {
  final AppThemeMode themeMode;
  final ReadingMode readingMode;
  final String opdsBaseUrl;
  final double fontSize;
  final double ttsSpeed; // 0.5–2.5, шаг 0.25
  final String? ttsVoice; // name голоса TTS

  const SettingsState({
    this.themeMode = AppThemeMode.sepia,
    this.readingMode = ReadingMode.scroll,
    this.opdsBaseUrl = 'https://m.flibusta.is',
    this.fontSize = 18,
    this.ttsSpeed = 0.8,
    this.ttsVoice,
  });

  SettingsState copyWith({
    AppThemeMode? themeMode,
    ReadingMode? readingMode,
    String? opdsBaseUrl,
    double? fontSize,
    double? ttsSpeed,
    String? Function()? ttsVoice,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        readingMode: readingMode ?? this.readingMode,
        opdsBaseUrl: opdsBaseUrl ?? this.opdsBaseUrl,
        fontSize: fontSize ?? this.fontSize,
        ttsSpeed: ttsSpeed ?? this.ttsSpeed,
        ttsVoice: ttsVoice != null ? ttsVoice() : this.ttsVoice,
      );

  @override
  List<Object?> get props =>
      [themeMode, readingMode, opdsBaseUrl, fontSize, ttsSpeed, ttsVoice];
}

class SettingsCubit extends Cubit<SettingsState> {
  static const _kTheme = 'themeMode';
  static const _kReading = 'readingMode';
  static const _kBase = 'opdsBaseUrl';
  static const _kFont = 'fontSize';
  static const _kTtsSpeed = 'ttsSpeed';
  static const _kTtsVoice = 'ttsVoice';
  static const _kTtsSpeedMigrated = 'ttsSpeedDefaultV2';
  static const defaultBaseUrl = 'https://m.flibusta.is';

  final SharedPreferences _prefs;

  SettingsCubit(this._prefs) : super(_load(_prefs));

  static SettingsState _load(SharedPreferences prefs) {
    final theme = AppThemeMode.values.asNameMap()[prefs.getString(_kTheme)] ??
        AppThemeMode.sepia;
    final reading =
        ReadingMode.values.asNameMap()[prefs.getString(_kReading)] ??
            ReadingMode.scroll;
    // Дефолт скорости TTS — 0.8 (Google TTS на 1.0 говорит слишком быстро).
    // Миграция: у тех, кто ни разу не менял скорость (нет ключа) или у кого
    // остался старый дефолт 1.0, один раз переключаем на 0.8.
    var speed = prefs.getDouble(_kTtsSpeed) ?? 0.8;
    if (!prefs.containsKey(_kTtsSpeedMigrated)) {
      if (!prefs.containsKey(_kTtsSpeed) || speed == 1.0) speed = 0.8;
      prefs.setBool(_kTtsSpeedMigrated, true);
    }
    return SettingsState(
      themeMode: theme,
      readingMode: reading,
      opdsBaseUrl: prefs.getString(_kBase) ?? defaultBaseUrl,
      fontSize: prefs.getDouble(_kFont) ?? 18,
      ttsSpeed: speed.clamp(0.5, 2.5),
      ttsVoice: prefs.getString(_kTtsVoice),
    );
  }

  void setThemeMode(AppThemeMode mode) {
    _prefs.setString(_kTheme, mode.name);
    emit(state.copyWith(themeMode: mode));
  }

  void setReadingMode(ReadingMode mode) {
    _prefs.setString(_kReading, mode.name);
    emit(state.copyWith(readingMode: mode));
  }

  void setOpdsBaseUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    _prefs.setString(_kBase, clean);
    emit(state.copyWith(opdsBaseUrl: clean));
  }

  void resetOpdsBaseUrl() {
    _prefs.setString(_kBase, defaultBaseUrl);
    emit(state.copyWith(opdsBaseUrl: defaultBaseUrl));
  }

  void setFontSize(double size) {
    final clamped = size.clamp(12.0, 32.0);
    _prefs.setDouble(_kFont, clamped);
    emit(state.copyWith(fontSize: clamped));
  }

  void setTtsSpeed(double speed) {
    final clamped = (speed * 4).round() / 4;
    final limited = clamped.clamp(0.5, 2.5);
    _prefs.setDouble(_kTtsSpeed, limited);
    emit(state.copyWith(ttsSpeed: limited));
  }

  void setTtsVoice(String? voiceName) {
    if (voiceName == null) {
      _prefs.remove(_kTtsVoice);
    } else {
      _prefs.setString(_kTtsVoice, voiceName);
    }
    emit(state.copyWith(ttsVoice: () => voiceName));
  }
}
