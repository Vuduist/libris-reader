import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/tts_cubit.dart';

/// Мини-плеер TTS внизу экрана читалки.
class TtsPlayerPanel extends StatelessWidget {
  const TtsPlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<TtsCubit, TtsState>(
      builder: (context, state) {
        if (!state.active) return const SizedBox.shrink();
        final cubit = context.read<TtsCubit>();
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.graphic_eq,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.itemCount > 0
                              ? 'Абзац ${state.itemIndex + 1} из ${state.itemCount}'
                              : 'Озвучка',
                          style: theme.textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.sleepMinutes > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.bedtime,
                              size: 16, color: theme.colorScheme.primary),
                        ),
                      Text('${state.speed.toStringAsFixed(2)}×',
                          style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      tooltip: 'Предыдущий абзац',
                      onPressed: cubit.prevParagraph,
                    ),
                    IconButton(
                      iconSize: 36,
                      icon: Icon(state.status == TtsStatus.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      tooltip: state.status == TtsStatus.playing
                          ? 'Пауза'
                          : 'Продолжить',
                      color: theme.colorScheme.primary,
                      onPressed: cubit.togglePlay,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Следующий абзац',
                      onPressed: cubit.nextParagraph,
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop),
                      tooltip: 'Стоп',
                      onPressed: cubit.stop,
                    ),
                    IconButton(
                      icon: const Icon(Icons.speed),
                      tooltip: 'Скорость',
                      onPressed: () => _showSpeedDialog(context, cubit, state),
                    ),
                    IconButton(
                      icon: const Icon(Icons.record_voice_over),
                      tooltip: 'Голос',
                      onPressed: () => _showVoiceDialog(context, cubit, state),
                    ),
                    IconButton(
                      icon: Icon(state.sleepMinutes > 0
                          ? Icons.bedtime
                          : Icons.bedtime_outlined),
                      tooltip: 'Таймер сна',
                      color: state.sleepMinutes > 0
                          ? theme.colorScheme.primary
                          : null,
                      onPressed: () => _showSleepMenu(context, cubit, state),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedDialog(
      BuildContext context, TtsCubit cubit, TtsState state) {
    showDialog(
      context: context,
      builder: (ctx) {
        var speed = state.speed;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text('Скорость: ${speed.toStringAsFixed(2)}×'),
            content: Slider(
              value: speed,
              min: 0.5,
              max: 2.5,
              divisions: 8,
              label: '${speed.toStringAsFixed(2)}×',
              onChanged: (v) => setState(() => speed = v),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () {
                    cubit.setSpeed(speed);
                    Navigator.pop(ctx);
                  },
                  child: const Text('OK')),
            ],
          ),
        );
      },
    );
  }

  void _showVoiceDialog(
      BuildContext context, TtsCubit cubit, TtsState state) {
    final voices = cubit.availableVoices;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Голос'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: voices.isEmpty
              ? const Center(child: Text('Голоса не найдены'))
              : ListView.builder(
                  itemCount: voices.length,
                  itemBuilder: (ctx, i) {
                    final v = voices[i];
                    final selected = v.name == state.voiceName;
                    return ListTile(
                      dense: true,
                      title: Text(v.name,
                          style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      subtitle: Text(v.locale),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () {
                        cubit.setVoice(v);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть')),
        ],
      ),
    );
  }

  void _showSleepMenu(BuildContext context, TtsCubit cubit, TtsState state) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in [0, 15, 30, 60])
              ListTile(
                leading: Icon(minutes == 0
                    ? Icons.bedtime_off_outlined
                    : Icons.bedtime_outlined),
                title: Text(minutes == 0
                    ? 'Таймер сна: выкл'
                    : 'Таймер сна: $minutes мин'),
                trailing: state.sleepMinutes == minutes
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  cubit.setSleepTimer(minutes);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
