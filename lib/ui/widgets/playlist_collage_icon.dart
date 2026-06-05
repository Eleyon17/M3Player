import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/audio_provider.dart';

class PlaylistCollageIcon extends ConsumerStatefulWidget {
  final String playlistId;
  final double size;

  const PlaylistCollageIcon({Key? key, required this.playlistId, this.size = 56.0}) : super(key: key);

  @override
  ConsumerState<PlaylistCollageIcon> createState() => _PlaylistCollageIconState();
}

class _PlaylistCollageIconState extends ConsumerState<PlaylistCollageIcon> {
  List<String> _coverIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCovers();
  }

  Future<void> _fetchCovers() async {
    try {
      final api = ref.read(navidromeClientProvider);
      final songs = await api.getPlaylistSongs(widget.playlistId);
      final uniqueCovers = <String>{};
      for (final song in songs) {
        if (song.albumId != null) {
          uniqueCovers.add(song.albumId!);
        } else if (song.coverArt != null) {
          uniqueCovers.add(song.coverArt!);
        }
        if (uniqueCovers.length >= 4) break;
      }
      if (mounted) {
        setState(() {
          _coverIds = uniqueCovers.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }

    if (_coverIds.isEmpty) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.queue_music, color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    final api = ref.read(navidromeClientProvider);

    if (_coverIds.length < 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: api.getCoverUrl(_coverIds.first),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: api.getCoverUrl(_coverIds[0]),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: api.getCoverUrl(_coverIds[1]),
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: api.getCoverUrl(_coverIds[2]),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: api.getCoverUrl(_coverIds[3]),
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
