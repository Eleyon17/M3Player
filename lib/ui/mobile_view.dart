import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/audio_provider.dart';
import 'widgets/bubbly_widgets.dart';
import 'widgets/wiggling_progress_bar.dart';
import 'discover_panel.dart';
import 'queue_panel.dart';
import 'now_playing_panel.dart'; // We'll reuse the interactive album art widget if we want, or just the flip card.
import 'dart:math';
import 'lyrics_panel.dart';
import 'home_screen.dart' show showLyricsProvider;

class MobileView extends ConsumerStatefulWidget {
  const MobileView({Key? key}) : super(key: key);

  @override
  ConsumerState<MobileView> createState() => _MobileViewState();
}

class _MobileViewState extends ConsumerState<MobileView> {
  // Mobile views: 0 = Now Playing, 1 = Discover, 2 = Queue
  int _currentView = 0;
  double? _dragValue;

  void _switchView(int view) {
    setState(() {
      if (_currentView == view && view != 0) {
        _currentView = 0; // Toggle back to Now Playing
      } else {
        _currentView = view;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(queueProvider.select((state) => state.currentSong));
    final api = ref.read(navidromeClientProvider);

    Widget mainContent;
    if (_currentView == 1) {
      mainContent = const DiscoverPanel();
    } else if (_currentView == 2) {
      mainContent = const QueuePanel();
    } else {
      // Now Playing Mobile View
      mainContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (currentSong != null) ...[
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -300) {
                    ref.read(queueProvider.notifier).next();
                  } else if (velocity > 300) {
                    ref.read(queueProvider.notifier).previous();
                  }
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        final rotateAnim = Tween(begin: pi, end: 0.0).animate(animation);
                        return AnimatedBuilder(
                          animation: rotateAnim,
                          child: child,
                          builder: (context, ch) {
                            final isUnder = (ValueKey(ref.watch(showLyricsProvider)) != child.key);
                            var tilt = ((animation.value - 0.5).abs() - 0.5) * 0.003;
                            tilt *= isUnder ? -1.0 : 1.0;
                            final value = isUnder ? min(rotateAnim.value, pi / 2) : rotateAnim.value;
                            return Transform(
                              transform: Matrix4.rotationY(value)..setEntry(3, 0, tilt),
                              alignment: Alignment.center,
                              child: ch,
                            );
                          },
                        );
                      },
                      child: ref.watch(showLyricsProvider)
                          ? Container(
                              key: const ValueKey(true),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const AspectRatio(
                                aspectRatio: 1.0,
                                child: LyricsPanel(),
                              ),
                            )
                          : InteractiveAlbumArt(
                              key: const ValueKey(false),
                              song: currentSong,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Text(
                    currentSong.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentSong.artist ?? 'Unknown Artist',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).textTheme.titleLarge?.color?.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSong.album ?? '--',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).textTheme.titleMedium?.color?.withValues(alpha: 0.6)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () {
                    ref.read(queueProvider.notifier).toggleFavorite();
                  },
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      currentSong.starred != null ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey(currentSong.starred != null),
                      color: currentSong.starred != null ? Colors.red : Theme.of(context).colorScheme.onSurface,
                      size: 24.0,
                    ),
                  ),
                ),
                BubblyIconButton(
                  icon: Icons.download,
                  onPressed: () {},
                ),
                BubblyIconButton(
                  icon: Icons.lyrics,
                  color: ref.watch(showLyricsProvider) ? Theme.of(context).colorScheme.primary : null,
                  iconColor: ref.watch(showLyricsProvider) ? Theme.of(context).colorScheme.onPrimary : null,
                  onPressed: () {
                    ref.read(showLyricsProvider.notifier).toggle();
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
          ] else ...[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note, size: 120, color: Colors.grey),
                    const SizedBox(height: 32),
                    Text(
                      'Ready to Play',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a track from Discover',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).textTheme.titleLarge?.color?.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (currentSong != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: CachedNetworkImage(
                imageUrl: api.getCoverUrl(currentSong.coverArt ?? currentSong.id, size: 500),
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(color: Theme.of(context).colorScheme.surface),
              ),
            )
          else
            Container(color: Theme.of(context).colorScheme.surface),
            
          Container(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Expanded(
                      child: mainContent,
                    ),
                    // Mobile Playbar
                    _buildMobilePlaybar(context, ref),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobilePlaybar(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    
    return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: const Border(top: BorderSide(color: Colors.white12, width: 1)),
        ),
        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, left: 16.0, right: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StreamBuilder<bool>(
                  stream: player.shuffleModeEnabledStream,
                  builder: (context, snapshot) {
                    final isShuffle = snapshot.data ?? false;
                    return IconButton(
                      icon: const Icon(Icons.shuffle, size: 20),
                      color: isShuffle ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      onPressed: () {
                        player.setShuffleModeEnabled(!isShuffle);
                        if (!isShuffle) player.shuffle();
                      },
                    );
                  },
                ),
                Expanded(
                  child: StreamBuilder<Duration?>(
                    stream: player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = player.duration ?? Duration.zero;
                      return WigglingProgressBar(
                        value: (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
                          0.0, 
                          duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0
                        ),
                        max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                        isPlaying: player.playing,
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        thumbColor: Theme.of(context).colorScheme.primary,
                        onChanged: (val) {
                          setState(() {
                            _dragValue = val;
                          });
                        },
                        onChangeEnd: (val) {
                          player.seek(Duration(milliseconds: val.toInt()));
                          setState(() {
                            _dragValue = null;
                          });
                        },
                      );
                    },
                  ),
                ),
                StreamBuilder<LoopMode>(
                  stream: player.loopModeStream,
                  builder: (context, snapshot) {
                    final loopMode = snapshot.data ?? LoopMode.off;
                    IconData icon = Icons.repeat;
                    if (loopMode == LoopMode.one) icon = Icons.repeat_one;
                    
                    return IconButton(
                      icon: Icon(icon, size: 20),
                      color: loopMode != LoopMode.off ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      onPressed: () {
                        if (loopMode == LoopMode.off) {
                          player.setLoopMode(LoopMode.all);
                        } else if (loopMode == LoopMode.all) {
                          player.setLoopMode(LoopMode.one);
                        } else {
                          player.setLoopMode(LoopMode.off);
                        }
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.explore, color: _currentView == 1 ? Theme.of(context).colorScheme.primary : null),
                  onPressed: () => _switchView(1),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BubblyIconButton(
                      icon: Icons.skip_previous,
                      onPressed: () => ref.read(queueProvider.notifier).previous(),
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
                            color: Theme.of(context).colorScheme.primaryContainer,
                            iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            onPressed: player.play,
                          );
                        } else if (processingState != ProcessingState.completed) {
                          return BubblyIconButton(
                            icon: Icons.pause_rounded,
                            size: 48.0,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            onPressed: player.pause,
                          );
                        } else {
                          return BubblyIconButton(
                            icon: Icons.play_arrow_rounded,
                            size: 48.0,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            onPressed: () => player.seek(Duration.zero),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    BubblyIconButton(
                      icon: Icons.skip_next,
                      onPressed: () => ref.read(queueProvider.notifier).next(),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.queue_music, color: _currentView == 0 ? Theme.of(context).colorScheme.primary : null),
                  onPressed: () => _switchView(0),
                ),
              ],
            ),
          ],
        ),
      );
  }
}
