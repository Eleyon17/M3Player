import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/audio_provider.dart';
import 'widgets/bubbly_widgets.dart';
import 'widgets/wiggling_progress_bar.dart';

class BottomControls extends ConsumerStatefulWidget {
  const BottomControls({Key? key}) : super(key: key);

  @override
  ConsumerState<BottomControls> createState() => _BottomControlsState();
}

class _BottomControlsState extends ConsumerState<BottomControls> {
  double? _dragValue;
  double _lastVolume = 1.0;

  String _formatDuration(Duration? duration) {
    if (duration == null) return "0:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(audioPlayerProvider);
    final currentSong = ref.watch(queueProvider).currentSong;
    final theme = Theme.of(context);
    final playbarColor = theme.colorScheme.surfaceContainerHighest;
    final isDarkPlaybar = playbarColor.computeLuminance() < 0.5;
    final elementColor = isDarkPlaybar ? Colors.white : Colors.black;
    final inactiveElementColor = elementColor.withValues(alpha: 0.3);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(45),
            color: playbarColor,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            children: [
              // Playback Controls (Left)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BubblyIconButton(
                    icon: Icons.shuffle,
                    noShadow: true,
                    iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    onPressed: () {
                      ref.read(queueProvider.notifier).toggleShuffle();
                    },
                  ),
                  const SizedBox(width: 16),
                  BubblyIconButton(
                    icon: Icons.skip_previous,
                    noShadow: true,
                    iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    onPressed: () {
                      ref.read(queueProvider.notifier).previous();
                    },
                  ),
                  const SizedBox(width: 16),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final processingState = playerState?.processingState;
                      final playing = playerState?.playing;
                      if (processingState == ProcessingState.loading ||
                          processingState == ProcessingState.buffering) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: BubblyIconButton(
                            customIcon: const SizedBox(
                              width: 40.0,
                              height: 40.0,
                              child: Padding(
                                padding: EdgeInsets.all(4.0),
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            color: Theme.of(context).colorScheme.primaryContainer,
                            onPressed: null,
                          ),
                        );
                      } else if (playing != true) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: BubblyIconButton(
                            customIcon: SolidPlayIcon(size: 40.0, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            noShadow: false,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            onPressed: player.play,
                          ),
                        );
                      } else if (processingState != ProcessingState.completed) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: BubblyIconButton(
                            customIcon: SolidPauseIcon(size: 40.0, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            noShadow: false,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            onPressed: player.pause,
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: BubblyIconButton(
                            customIcon: SolidPlayIcon(size: 40.0, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            noShadow: false,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            onPressed: () => player.seek(Duration.zero),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  BubblyIconButton(
                    icon: Icons.skip_next,
                    noShadow: true,
                    iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    onPressed: () {
                      ref.read(queueProvider.notifier).next();
                    },
                  ),
                  const SizedBox(width: 16),
                  BubblyIconButton(
                    icon: ref.watch(queueProvider).loopMode == AppLoopMode.one ? Icons.repeat_one : Icons.repeat,
                    noShadow: true,
                    color: ref.watch(queueProvider).loopMode != AppLoopMode.off ? Theme.of(context).colorScheme.primaryContainer : null,
                    iconColor: ref.watch(queueProvider).loopMode != AppLoopMode.off ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurfaceVariant,
                    onPressed: () {
                      ref.read(queueProvider.notifier).toggleLoop();
                    },
                  ),
                ],
              ),
              
              // Progress Bar (Center)
              Expanded(
                child: StreamBuilder<Duration?>(
                  stream: player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    var duration = player.duration;
                    if (duration == null || duration.inMilliseconds == 0) {
                      duration = Duration(seconds: currentSong?.duration ?? 0);
                    }
                    
                    return Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 24.0),
                          child: Text(_formatDuration(position), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: WigglingProgressBar(
                              value: (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
                                0.0, 
                                duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0
                              ),
                              max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                              isPlaying: player.playing,
                              activeColor: theme.colorScheme.primary,
                              inactiveColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                              thumbColor: theme.colorScheme.primary,
                              onChanged: (val) {
                                setState(() {
                                  _dragValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                player.seek(Duration(milliseconds: val.round()));
                                setState(() {
                                  _dragValue = null;
                                });
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 24.0),
                          child: Text(_formatDuration(duration), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              // Volume Control (Right)
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    StreamBuilder<double>(
                      stream: player.volumeStream,
                      builder: (context, snapshot) {
                        final currentVol = snapshot.data ?? 1.0;
                        return IconButton(
                          icon: Icon(currentVol > 0 ? Icons.volume_up : Icons.volume_off, size: 28, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          onPressed: () {
                            if (currentVol > 0) {
                              _lastVolume = currentVol;
                              player.setVolume(0);
                            } else {
                              player.setVolume(_lastVolume);
                            }
                          },
                        );
                      },
                    ),
                    SizedBox(
                      width: 150,
                      child: StreamBuilder<double>(
                        stream: player.volumeStream,
                        builder: (context, snapshot) {
                          return Slider(
                            value: snapshot.data ?? 1.0,
                            max: 1.0,
                            activeColor: theme.colorScheme.primary,
                            inactiveColor: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                            onChanged: player.setVolume,
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
        ),
      ),
      ),
      ),
      ),
    );
  }
}
