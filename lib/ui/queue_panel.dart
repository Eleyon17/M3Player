import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as Math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:implicitly_animated_reorderable_list_2/implicitly_animated_reorderable_list_2.dart';
import 'package:implicitly_animated_reorderable_list_2/transitions.dart';
import '../providers/audio_provider.dart';
import '../models/song.dart';
import 'home_screen.dart'; // To access showHistoryProvider
import 'widgets/bubbly_widgets.dart';

class AnimatedBars extends ConsumerStatefulWidget {
  final Color color;
  const AnimatedBars({Key? key, required this.color}) : super(key: key);

  @override
  ConsumerState<AnimatedBars> createState() => _AnimatedBarsState();
}

class _AnimatedBarsState extends ConsumerState<AnimatedBars> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    final player = ref.read(audioPlayerProvider);
    if (player.playing) {
      _controller.repeat(reverse: true);
    }
    _sub = player.playingStream.listen((playing) {
      if (playing) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.read(audioPlayerProvider).playing;
    return SizedBox(
      width: 24,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final val = playing ? (Math.sin(_controller.value * Math.pi * 2 + index * 1.5) + 1) / 2 : 0.0;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: 4,
                height: 8 + (12 * val),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
class HistoryPanel extends ConsumerWidget {
  const HistoryPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(queueProvider).history;
    final api = ref.read(navidromeClientProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
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
      child: Container(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 8),
                      Text('Recently Played', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => ref.read(showHistoryProvider.notifier).toggle(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty 
                  ? const Center(child: Text("No history yet.", style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final song = history[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: api.getCoverUrl(song.albumId ?? song.id),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorWidget: (c, u, e) => Container(
                                width: 50, height: 50,
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.music_note),
                              ),
                            ),
                          ),
                          title: Text(song.title, style: Theme.of(context).textTheme.titleMedium),
                          subtitle: Text(song.artist ?? "Unknown Artist"),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class QueuePanel extends ConsumerWidget {
  const QueuePanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueState = ref.watch(queueProvider);
    final queue = queueState.queue;
    final api = ref.read(navidromeClientProvider);

    return Container(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue_music),
                    const SizedBox(width: 8),
                    Text('Up Next', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [
                    BubblyIconButton(
                      icon: Icons.history,
                      onPressed: () => ref.read(showHistoryProvider.notifier).toggle(),
                    ),
                    const SizedBox(width: 8),
                    BubblyIconButton(
                      icon: Icons.delete,
                      iconColor: Theme.of(context).colorScheme.error,
                      onPressed: () => ref.read(queueProvider.notifier).clearQueue(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (queueState.currentSong != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Material(
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6), width: 2),
                        ),
                        child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: api.getCoverUrl(queueState.currentSong!.albumId ?? queueState.currentSong!.id),
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 64, height: 64,
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.music_note),
                              ),
                            ),
                          ),
                          title: Text(queueState.currentSong!.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text(queueState.currentSong!.artist ?? "Unknown Artist", style: Theme.of(context).textTheme.bodyMedium),
                          trailing: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                            ),
                            child: AnimatedBars(color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                  if (queue.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 8.0),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text("Up Next", style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                          Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                        ],
                      ),
                    ),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: queue.isEmpty && queueState.currentSong == null ? 1.0 : 0.0,
                        child: const Center(child: Text('Queue is empty.', style: TextStyle(color: Colors.white54))),
                      ),
                      ImplicitlyAnimatedReorderableList<Song>(
                        items: queue,
                        areItemsTheSame: (oldItem, newItem) => oldItem.id == newItem.id,
                        onReorderFinished: (item, from, to, newItems) {
                          ref.read(queueProvider.notifier).updateQueue(newItems);
                        },
                        insertDuration: const Duration(milliseconds: 300),
                        removeDuration: const Duration(milliseconds: 300),
                        itemBuilder: (context, itemAnimation, item, index) {
                          return Reorderable(
                            key: ValueKey(item.id),
                            builder: (context, dragAnimation, inDrag) {
                              return SizeFadeTransition(
                                sizeFraction: 0.7,
                                curve: Curves.easeInOut,
                                animation: itemAnimation,
                                child: _buildItem(context, item, api, queueState, dragAnimation, ref),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (queue.length <= 3)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text("Instant Mix"),
                      onPressed: () {
                        ref.read(queueProvider.notifier).generateInstantMix();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, Song song, dynamic api, dynamic queueState, Animation<double> dragAnimation, WidgetRef ref) {
    final isCurrent = queueState.currentSong != null && song.id == queueState.currentSong!.id;
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.05).animate(dragAnimation),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final realIndex = ref.read(queueProvider).queue.indexWhere((s) => s.id == song.id);
            if (realIndex != -1) {
              ref.read(queueProvider.notifier).playFromQueue(realIndex);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Handle(
                  delay: Duration(milliseconds: 0),
                  child: Icon(Icons.drag_indicator, size: 24, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: CachedNetworkImage(
                    imageUrl: api.getCoverUrl(song.albumId ?? song.id),
                    width: 70,
                    height: 70,
                    memCacheWidth: 140,
                    memCacheHeight: 140,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 70,
                      height: 70,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary, size: 32),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist ?? 'Unknown Artist',
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    final realIndex = ref.read(queueProvider).queue.indexWhere((s) => s.id == song.id);
                    if (realIndex != -1) {
                      ref.read(queueProvider.notifier).removeSongAt(realIndex);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
