import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/navidrome_client.dart';
import '../providers/audio_provider.dart';
import 'discover_panel.dart';
import 'queue_panel.dart';
import 'now_playing_panel.dart';
import 'bottom_controls.dart';
import 'mobile_view.dart';
import 'lyrics_panel.dart';

final showLyricsProvider = NotifierProvider<ShowLyricsNotifier, bool>(ShowLyricsNotifier.new);

class ShowLyricsNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final showHistoryProvider = NotifierProvider<ShowHistoryNotifier, bool>(ShowHistoryNotifier.new);

class ShowHistoryNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _wideSplitRatio = 0.5;
  double _narrowSplitRatio = 0.6;

  bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return const MobileView();
    }

    final showLyrics = ref.watch(showLyricsProvider);

    final currentSong = ref.watch(queueProvider.select((state) => state.currentSong));
    final api = ref.read(navidromeClientProvider);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark
                  ? [
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                      Theme.of(context).colorScheme.surface,
                    ]
                  : [
                      Theme.of(context).colorScheme.surfaceContainerLow,
                      Theme.of(context).colorScheme.surface,
                    ],
              ),
            ),
          ),
          
          // Subtle blurred overlay to retain texture
          if (currentSong != null)
            Opacity(
              opacity: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.08,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  child: CachedNetworkImage(
                    key: ValueKey(currentSong.id),
                    imageUrl: api.getCoverUrl(currentSong.coverArt ?? currentSong.id, size: 200),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            
          // Main UI
          Container(
            color: Colors.transparent, // Removed dark tint to brighten
            child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 1400;
                    
                    final centerPanel = AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.1),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: showLyrics 
                          ? const LyricsPanel(key: ValueKey('lyrics'))
                          : _buildBoxedDiscover(context),
                    );

                    final showHistory = ref.watch(showHistoryProvider);
                    final rightPanel = AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.1),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: showHistory 
                          ? const HistoryPanel(key: ValueKey('history'))
                          : const _BoxedQueue(key: ValueKey('queue')),
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          // Left Panel: Now Playing (Gets maximum space)
                          const Expanded(
                            flex: 4,
                            child: NowPlayingPanel(),
                          ),
                          const SizedBox(width: 24),
                          
                          // Center and Right Panels (Resizable)
                          Expanded(
                            flex: 8,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final totalWidth = constraints.maxWidth - 24;
                                final centerWidth = (totalWidth * _wideSplitRatio).clamp(0.0, totalWidth);
                                final rightWidth = totalWidth - centerWidth;

                                return Row(
                                  children: [
                                    SizedBox(
                                      width: centerWidth,
                                      child: centerPanel,
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onPanUpdate: (details) {
                                        setState(() {
                                          _wideSplitRatio += details.delta.dx / totalWidth;
                                          _wideSplitRatio = _wideSplitRatio.clamp(0.2, 0.8);
                                        });
                                      },
                                      child: SizedBox(
                                        width: 24,
                                        height: double.infinity,
                                        child: Center(
                                          child: Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: rightWidth,
                                      child: rightPanel,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        children: [
                          // Left Panel: Now Playing (Gets maximum space)
                          const Expanded(
                            flex: 5,
                            child: NowPlayingPanel(),
                          ),
                          const SizedBox(width: 24),
                          
                          // Right Panel: Stack Discover/Lyrics and Queue vertically (Resizable)
                          Expanded(
                            flex: 4,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final totalHeight = constraints.maxHeight - 24;
                                final centerHeight = (totalHeight * _narrowSplitRatio).clamp(0.0, totalHeight);
                                final rightHeight = totalHeight - centerHeight;

                                return Column(
                                  children: [
                                    SizedBox(
                                      height: centerHeight,
                                      child: centerPanel,
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onPanUpdate: (details) {
                                        setState(() {
                                          _narrowSplitRatio += details.delta.dy / totalHeight;
                                          _narrowSplitRatio = _narrowSplitRatio.clamp(0.2, 0.8);
                                        });
                                      },
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 24,
                                        child: Center(
                                          child: Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: rightHeight,
                                      child: rightPanel,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
            const BottomControls(),
          ],
        ),
      ),
      
      // Close button
      Positioned(
        top: 0,
        right: 0,
        child: IconButton(
          icon: const Icon(Icons.close, size: 24),
          color: Colors.white70,
          hoverColor: Colors.red,
          onPressed: () => exit(0),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildBoxedDiscover(BuildContext context) {
    return Container(
      key: const ValueKey('discover'),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
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
      child: const DiscoverPanel(),
    );
  }
}

class _BoxedQueue extends StatelessWidget {
  const _BoxedQueue({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
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
      child: const QueuePanel(),
    );
  }
}
