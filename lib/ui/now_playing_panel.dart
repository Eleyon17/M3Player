import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import '../providers/audio_provider.dart';
import '../models/song.dart';
import 'widgets/bubbly_widgets.dart';
import 'home_screen.dart';

class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(queueProvider.select((state) => state.currentSong));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (currentSong != null) ...[
            Expanded(
              child: Center(
                child: InteractiveAlbumArt(song: currentSong),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: ValueKey(currentSong.id),
                mainAxisSize: MainAxisSize.min,
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).textTheme.titleLarge?.color?.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSong.album ?? '--',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).textTheme.titleMedium?.color?.withValues(alpha: 0.6)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                BubblyButton(
                  noShadow: true,
                  color: Colors.transparent,
                  onPressed: () {
                    ref.read(queueProvider.notifier).toggleFavorite();
                  },
                  child: AnimatedSwitcher(
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
                  noShadow: true,
                  onPressed: () {},
                ),
                BubblyIconButton(
                  icon: Icons.lyrics,
                  noShadow: true,
                  color: ref.watch(showLyricsProvider) ? Theme.of(context).colorScheme.primary : null,
                  iconColor: ref.watch(showLyricsProvider) ? Theme.of(context).colorScheme.onPrimary : null,
                  onPressed: () {
                    ref.read(showLyricsProvider.notifier).toggle();
                  },
                ),
              ],
            ),
          ] else ...[
            const Icon(Icons.music_note, size: 120, color: Colors.grey),
            const SizedBox(height: 32),
            Text(
              'Ready to Play',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a track from Discover',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).textTheme.titleLarge?.color?.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    );
  }
}

class InteractiveAlbumArt extends ConsumerStatefulWidget {
  final Song song;
  const InteractiveAlbumArt({Key? key, required this.song}) : super(key: key);

  @override
  ConsumerState<InteractiveAlbumArt> createState() => _InteractiveAlbumArtState();
}

class _InteractiveAlbumArtState extends ConsumerState<InteractiveAlbumArt> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFlipped = false;
  String? _bio;
  bool _isLoadingBio = false;
  int _bioDisplayLength = 250;
  List<Song>? _topSongs;
  List<Map<String, dynamic>>? _topAlbums;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _fetchBio(); // Fetch preemptively
  }

  @override
  void didUpdateWidget(covariant InteractiveAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      // Always reset the bio data when the song changes
      setState(() {
        _bio = null;
        _topSongs = null;
        _topAlbums = null;
        _bioDisplayLength = 250;
        _isLoadingBio = false;
      });
      
      // Fetch preemptively
      _fetchBio();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchBio() async {
    if (_bio != null || _isLoadingBio) return;
    setState(() => _isLoadingBio = true);
    final api = ref.read(navidromeClientProvider);
    
    // 1. Try Navidrome Artist Info
    String? bioText;
    if (widget.song.artistId != null) {
      final info = await api.getArtistInfo(widget.song.artistId!);
      bioText = info?['biography'];
    }
    
    // 2. Fallback to Wikipedia
    if ((bioText == null || bioText.isEmpty) && widget.song.artist != null) {
      bioText = await api.getWikipediaSummary(widget.song.artist!);
    }
    
    // 3. Fetch Top Songs / Albums using search
    if (widget.song.artist != null) {
      final searchResults = await api.search(widget.song.artist!);
      _topSongs = (searchResults['songs'] as List<Song>?)?.take(5).toList();
      _topAlbums = (searchResults['albums'] as List<Map<String, dynamic>>?)?.take(3).toList();
    }
    
    if (mounted) {
      setState(() {
        _bio = bioText ?? 'No biography information is available for this artist.';
        _isLoadingBio = false;
      });
    }
  }

  void _toggleFlip() {
    if (!_isFlipped) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _isFlipped = !_isFlipped;
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(navidromeClientProvider);
    
    return GestureDetector(
      onTap: _toggleFlip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_animation.value * math.pi);
            
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: _animation.value < 0.5
                ? _buildFront(api)
                : Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _buildBack(),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFront(api) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: CachedNetworkImage(
              key: ValueKey(widget.song.id),
              imageUrl: api.getCoverUrl(widget.song.coverArt ?? widget.song.id),
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note, size: 100),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBack() {
    final bioText = _bio ?? '';
    final isLongBio = bioText.length > _bioDisplayLength;
    final displayBio = isLongBio ? '${bioText.substring(0, _bioDisplayLength)}...' : bioText;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                widget.song.artist ?? 'Artist Info',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoadingBio
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayBio,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                            ),
                            if (isLongBio)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    setState(() => _bioDisplayLength += 100);
                                  },
                                  child: const Text('Read more'),
                                ),
                              ),
                            
                            if (_topSongs != null && _topSongs!.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text("Top Songs", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 140,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _topSongs!.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                                  itemBuilder: (context, i) {
                                    final s = _topSongs![i];
                                    return _HorizontalTile(
                                      imageUrl: ref.read(navidromeClientProvider).getCoverUrl(s.albumId ?? s.id),
                                      title: s.title,
                                      onTap: () {
                                        ref.read(queueProvider.notifier).insertNext(s);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (_topAlbums != null && _topAlbums!.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text("Top Albums", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 140,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _topAlbums!.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                                  itemBuilder: (context, i) {
                                    final a = _topAlbums![i];
                                    return _HorizontalTile(
                                      imageUrl: ref.read(navidromeClientProvider).getCoverUrl(a['id']),
                                      title: a['name'] ?? a['title'] ?? 'Unknown',
                                      onTap: () async {
                                        final api = ref.read(navidromeClientProvider);
                                        final albumSongs = await api.getAlbum(a['id']);
                                        ref.read(queueProvider.notifier).addListToQueue(albumSongs);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _HorizontalTile extends StatelessWidget {
  final String imageUrl;
  final String title;
  final VoidCallback onTap;
  
  const _HorizontalTile({required this.imageUrl, required this.title, required this.onTap});
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 100,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 100, height: 100,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
