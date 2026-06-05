import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/audio_provider.dart';
import '../providers/lyrics_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({Key? key}) : super(key: key);

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _currentIndex = -1;
  bool _isTapped = false;
  bool _isUserScrolling = false;
  Timer? _scrollResumeTimer;
  int? _optimisticIndex;

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  void _scrollToCurrentLine(int index) {
    if (index != _currentIndex && index >= 0) {
      _currentIndex = index;
      if (_isTapped || _isUserScrolling) return; // Prevent yanking the screen if user manually tapped a lyric
      if (_itemScrollController.isAttached) {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.4, // Keep the active item nicely centered in the view
        );
      }
    }
  }

  int _getInitialIndex(List<LrcLine> lines, Duration position) {
    for (int i = 0; i < lines.length; i++) {
      if (position >= lines[i].time) {
        if (i == lines.length - 1 || position < lines[i + 1].time) {
          _currentIndex = i;
          return i;
        }
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(queueProvider.select((state) => state.currentSong));
    
    if (currentSong == null) {
      return const Center(child: Text("No song playing"));
    }

    final params = (id: currentSong.id, title: currentSong.title, artist: currentSong.artist, album: currentSong.album);
    final lyricsAsync = ref.watch(translatedLyricsProvider(params));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: lyricsAsync.when(
        data: (lyrics) {
          if (lyrics == null) {
            return Center(
              child: Text(
                "Lyrics not found",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            );
          }

          if (lyrics.hasSynced) {
            return _buildSyncedLyrics(lyrics.syncedLyrics!);
          } else {
            return _buildPlainLyrics(lyrics);
          }
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: \$err")),
      ),
    );
  }

  Widget _buildPlainLyrics(LyricsData data) {
    // Strip any rogue [mm:ss.xx] timestamps that might have leaked into plain text
    final cleanLyrics = data.plainLyrics!.replaceAll(RegExp(r'\[\d{2}:\d{2}\.\d{2,3}\]'), '');
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          Text(
            cleanLyrics,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.8),
            textAlign: TextAlign.center,
          ),
          if (data.translatedPlainLyrics != null && data.translatedPlainLyrics!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32.0),
              child: Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    "Translation",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data.translatedPlainLyrics!,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      height: 1.8,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSyncedLyrics(List<LrcLine> lines) {
    final player = ref.watch(audioPlayerProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollStartNotification) {
          if (notification.dragDetails != null) {
            _isUserScrolling = true;
            _scrollResumeTimer?.cancel();
          }
        } else if (notification is ScrollEndNotification) {
          _scrollResumeTimer?.cancel();
          _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _isUserScrolling = false);
            }
          });
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        initialScrollIndex: _getInitialIndex(lines, player.position),
        padding: const EdgeInsets.symmetric(vertical: 200, horizontal: 32),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          
          return StreamBuilder<Duration?>(
            stream: player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              
              bool isActive = false;
              if (_optimisticIndex != null) {
                isActive = index == _optimisticIndex;
              } else {
                if (position >= line.time) {
                  if (index == lines.length - 1 || position < lines[index + 1].time) {
                    isActive = true;
                    
                    if (_currentIndex != index) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToCurrentLine(index);
                      });
                    }
                  }
                }
              }
              
              return InkWell(
                onTap: () {
                  _isTapped = true;
                  setState(() => _optimisticIndex = index);
                  player.seek(line.time);
                  Future.delayed(const Duration(milliseconds: 800), () {
                    if (mounted) {
                      setState(() {
                        _isTapped = false;
                        _optimisticIndex = null;
                      });
                    }
                  });
                },
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  decoration: BoxDecoration(
                    color: isActive ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8) : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: AnimatedScale(
                    scale: isActive ? 1.0 : 0.85,
                    duration: const Duration(milliseconds: 300),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isActive 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      textAlign: TextAlign.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(line.text.isEmpty ? "..." : line.text),
                          if (line.translatedText != null && line.translatedText!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                line.translatedText!,
                                style: TextStyle(
                                  fontSize: (Theme.of(context).textTheme.headlineMedium?.fontSize ?? 24) * 0.7,
                                  fontStyle: FontStyle.italic,
                                  color: isActive 
                                    ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
