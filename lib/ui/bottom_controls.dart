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
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(45),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.95),
                Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.95),
              ],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            // Playback Controls (Left)
            SizedBox(
              width: 350,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  BubblyIconButton(
                    icon: Icons.shuffle,
                    noShadow: true,
                    onPressed: () {
                      ref.read(queueProvider.notifier).toggleShuffle();
                    },
                  ),
                  const SizedBox(width: 8),
                  BubblyIconButton(
                    icon: Icons.skip_previous,
                    noShadow: true,
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
                          color: Theme.of(context).colorScheme.primary,
                          iconColor: Theme.of(context).colorScheme.onPrimary,
                          onPressed: player.play,
                        );
                      } else if (processingState != ProcessingState.completed) {
                        return BubblyIconButton(
                          icon: Icons.pause_rounded,
                          size: 48.0,
                          noShadow: false,
                          color: Theme.of(context).colorScheme.primary,
                          iconColor: Theme.of(context).colorScheme.onPrimary,
                          onPressed: player.pause,
                        );
                      } else {
                        return BubblyIconButton(
                          icon: Icons.play_arrow_rounded,
                          size: 48.0,
                          noShadow: false,
                          color: Theme.of(context).colorScheme.primary,
                          iconColor: Theme.of(context).colorScheme.onPrimary,
                          onPressed: () => player.seek(Duration.zero),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  BubblyIconButton(
                    icon: Icons.skip_next,
                    noShadow: true,
                    onPressed: () {
                      ref.read(queueProvider.notifier).next();
                    },
                  ),
                  const SizedBox(width: 8),
                  BubblyIconButton(
                    icon: ref.watch(queueProvider).loopMode == AppLoopMode.one ? Icons.repeat_one : Icons.repeat,
                    noShadow: true,
                    color: ref.watch(queueProvider).loopMode != AppLoopMode.off ? Theme.of(context).colorScheme.primaryContainer : null,
                    iconColor: ref.watch(queueProvider).loopMode != AppLoopMode.off ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                    onPressed: () {
                      ref.read(queueProvider.notifier).toggleLoop();
                    },
                  ),
                ],
              ),
            ),
            
            // Progress Bar (Center, Tight)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: StreamBuilder<Duration?>(
                    stream: player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = player.duration ?? Duration.zero;
                      
                      return Row(
                        children: [
                          Text(_formatDuration(position)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: WigglingProgressBar(
                                value: (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
                                  0.0, 
                                  duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0
                                ),
                                max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                                isPlaying: player.playing,
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
                          Text(_formatDuration(duration)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            
            // Volume Control (Right)
            SizedBox(
              width: 350,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  StreamBuilder<double>(
                    stream: player.volumeStream,
                    builder: (context, snapshot) {
                      final currentVol = snapshot.data ?? 1.0;
                      return IconButton(
                        icon: Icon(currentVol > 0 ? Icons.volume_up : Icons.volume_off, size: 28),
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
                          onChanged: player.setVolume,
                        );
                      },
                    ),
                  ),
                ],
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
