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
          child: Stack(
            children: [
              // Playback Controls (Left)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 350,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      BubblyIconButton(
                        icon: Icons.shuffle,
                        noShadow: true,
                        iconColor: elementColor,
                        onPressed: () {
                          ref.read(queueProvider.notifier).toggleShuffle();
                        },
                      ),
                      const SizedBox(width: 8),
                      BubblyIconButton(
                        icon: Icons.skip_previous,
                        noShadow: true,
                        iconColor: elementColor,
                        onPressed: () {
                          ref.read(queueProvider.notifier).previous();
                        },
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<PlayerState>(
                        stream: player.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          final processingState = playerState?.processingState;
                          final playing = playerState?.playing;
                          if (processingState == ProcessingState.loading ||
                              processingState == ProcessingState.buffering) {
                            return Container(
                              margin: const EdgeInsets.all(8.0),
                              width: 48.0,
                              height: 48.0,
                              child: const CircularProgressIndicator(),
                            );
                          } else if (playing != true) {
                            return BubblyIconButton(
                              icon: Icons.play_arrow_rounded,
                              size: 48.0,
                              noShadow: false,
                              color: elementColor,
                              iconColor: isDarkPlaybar ? Colors.black : Colors.white,
                              onPressed: player.play,
                            );
                          } else if (processingState != ProcessingState.completed) {
                            return BubblyIconButton(
                              icon: Icons.pause_rounded,
                              size: 48.0,
                              noShadow: false,
                              color: elementColor,
                              iconColor: isDarkPlaybar ? Colors.black : Colors.white,
                              onPressed: player.pause,
                            );
                          } else {
                            return BubblyIconButton(
                              icon: Icons.play_arrow_rounded,
                              size: 48.0,
                              noShadow: false,
                              color: elementColor,
                              iconColor: isDarkPlaybar ? Colors.black : Colors.white,
                              onPressed: () => player.seek(Duration.zero),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      BubblyIconButton(
                        icon: Icons.skip_next,
                        noShadow: true,
                        iconColor: elementColor,
                        onPressed: () {
                          ref.read(queueProvider.notifier).next();
                        },
                      ),
                      const SizedBox(width: 8),
                      BubblyIconButton(
                        icon: ref.watch(queueProvider).loopMode == AppLoopMode.one ? Icons.repeat_one : Icons.repeat,
                        noShadow: true,
                        color: ref.watch(queueProvider).loopMode != AppLoopMode.off ? elementColor.withValues(alpha: 0.2) : null,
                        iconColor: ref.watch(queueProvider).loopMode != AppLoopMode.off ? elementColor : elementColor,
                        onPressed: () {
                          ref.read(queueProvider.notifier).toggleLoop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              // Progress Bar (Perfectly Centered)
              Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Padding(
                    // Pad to avoid overlapping with side controls on smaller screens
                    padding: const EdgeInsets.symmetric(horizontal: 360.0),
                    child: StreamBuilder<Duration?>(
                      stream: player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final duration = player.duration ?? Duration.zero;
                        
                        return Row(
                          children: [
                            Text(_formatDuration(position), style: TextStyle(color: elementColor)),
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
                                  inactiveColor: inactiveElementColor,
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
                            Text(_formatDuration(duration), style: TextStyle(color: elementColor)),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              
              // Volume Control (Right)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 350,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      StreamBuilder<double>(
                        stream: player.volumeStream,
                        builder: (context, snapshot) {
                          final currentVol = snapshot.data ?? 1.0;
                          return IconButton(
                            icon: Icon(currentVol > 0 ? Icons.volume_up : Icons.volume_off, size: 28, color: elementColor),
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
                              inactiveColor: inactiveElementColor,
                              onChanged: player.setVolume,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
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
