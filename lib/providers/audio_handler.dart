import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../api/navidrome_client.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;
  final NavidromeClient api;
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  
  static const String customActionFavorite = 'action_favorite';
  static const String customActionShuffle = 'action_shuffle';
  static const String customActionLoop = 'action_loop';

  MyAudioHandler(this.player, this.api) {
    player.setAudioSource(_playlist);
    _listenToPlayerState();
    _listenToSequenceState();
  }

  void _listenToPlayerState() {
    player.playbackEventStream.listen((event) {
      final playing = player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          const MediaControl(
            androidIcon: 'drawable/ic_stat_favorite',
            label: 'Favorite',
            action: MediaAction.custom,
            customAction: CustomMediaAction(name: customActionFavorite),
          ),
          const MediaControl(
            androidIcon: 'drawable/ic_stat_shuffle',
            label: 'Shuffle',
            action: MediaAction.custom,
            customAction: CustomMediaAction(name: customActionShuffle),
          ),
          const MediaControl(
            androidIcon: 'drawable/ic_stat_loop',
            label: 'Loop',
            action: MediaAction.custom,
            customAction: CustomMediaAction(name: customActionLoop),
          )
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
        repeatMode: _getRepeatMode(player.loopMode),
        shuffleMode: player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      ));
    });
  }

  AudioServiceRepeatMode _getRepeatMode(LoopMode loopMode) {
    switch (loopMode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  void _listenToSequenceState() {
    player.sequenceStateStream.listen((sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) {
        queue.add([]);
        return;
      }
      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);
      
      final currentIndex = sequenceState?.currentIndex;
      if (currentIndex != null && currentIndex < items.length) {
        mediaItem.add(items[currentIndex]);
      }
    });
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    await player.seekToNext();
    if (!player.playing) play();
  }

  @override
  Future<void> skipToPrevious() async {
    await player.seekToPrevious();
    if (!player.playing) play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        await player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      await player.setShuffleModeEnabled(false);
    } else {
      await player.setShuffleModeEnabled(true);
      await player.shuffle();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == customActionFavorite) {
      final current = mediaItem.value;
      if (current != null) {
        // Optimistic UI update could go here
        try {
           final song = await api.getSong(current.id);
           if (song != null) {
              if (song.starred != null) {
                 await api.unstar(song.id);
              } else {
                 await api.star(song.id);
              }
           }
        } catch (_) {}
      }
    } else if (name == customActionShuffle) {
      await player.setShuffleModeEnabled(!player.shuffleModeEnabled);
      if (player.shuffleModeEnabled) {
        await player.shuffle();
      }
    } else if (name == customActionLoop) {
      final current = player.loopMode;
      if (current == LoopMode.off) {
        await player.setLoopMode(LoopMode.all);
      } else if (current == LoopMode.all) {
        await player.setLoopMode(LoopMode.one);
      } else {
        await player.setLoopMode(LoopMode.off);
      }
    }
  }

  // --- Android Auto MediaBrowser ---
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return [
        const MediaItem(id: 'tab_artists', title: 'Artists', playable: false),
        const MediaItem(id: 'tab_albums', title: 'Albums', playable: false),
        const MediaItem(id: 'tab_playlists', title: 'Playlists', playable: false),
        const MediaItem(id: 'tab_favorites', title: 'Favorites', playable: false),
      ];
    }
    
    try {
      if (parentMediaId == 'tab_artists') {
        final artists = await api.getArtists();
        return artists.map<MediaItem>((a) => MediaItem(id: 'artist_${a['id']}', title: a['name'] ?? 'Unknown', playable: false)).toList();
      }
      if (parentMediaId == 'tab_albums') {
        final albums = await api.getAlbumList();
        return albums.map<MediaItem>((a) => MediaItem(id: 'album_${a['id']}', title: a['title'] ?? 'Unknown', playable: false)).toList();
      }
      if (parentMediaId == 'tab_favorites') {
        final songs = await api.getStarred();
        return songs.map<MediaItem>((s) => _songToMediaItem(s)).toList();
      }
      if (parentMediaId == 'tab_playlists') {
        final playlists = await api.getPlaylists();
        return playlists.map<MediaItem>((p) => MediaItem(
          id: 'playlist_${p['id']}',
          title: p['name'] ?? 'Unknown Playlist',
          playable: false,
        )).toList();
      }
      
      if (parentMediaId.startsWith('playlist_')) {
        final id = parentMediaId.split('_').last;
        final songs = await api.getPlaylistSongs(id);
        return songs.map<MediaItem>((s) => _songToMediaItem(s)).toList();
      }
      
      if (parentMediaId.startsWith('artist_')) {
        final id = parentMediaId.split('_').last;
        final albums = await api.getArtist(id);
        return albums.map<MediaItem>((a) => MediaItem(id: 'album_${a['id']}', title: a['name'] ?? 'Unknown', playable: false)).toList();
      }
      if (parentMediaId.startsWith('album_')) {
        final id = parentMediaId.split('_').last;
        final songs = await api.getAlbum(id);
        return songs.map<MediaItem>((s) => _songToMediaItem(s)).toList();
      }
    } catch (e) {
      print("Error fetching children for Android Auto: $e");
    }

    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    try {
      final song = await api.getSong(mediaId);
      if (song != null) return _songToMediaItem(song);
    } catch (_) {}
    return null;
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    try {
      final results = await api.search(query);
      final songs = (results['songs'] as List).cast<Song>();
      return songs.map<MediaItem>((s) => _songToMediaItem(s)).toList();
    } catch (_) {}
    return [];
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    try {
      final song = await api.getSong(mediaId);
      if (song != null) {
        await replaceQueue([song]);
        play();
      }
    } catch (_) {}
  }

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final results = await search(query);
    if (results.isNotEmpty) {
      await replaceQueue([Song.fromJson(results.first.extras!)]);
      play();
    }
  }

  // Helpers
  MediaItem _songToMediaItem(Song song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      album: song.album,
      artist: song.artist,
      artUri: Uri.parse(api.getCoverUrl(song.albumId ?? song.id, size: 500)),
      duration: Duration(seconds: song.duration),
      extras: song.toJson(),
    );
  }

  Future<void> replaceQueue(List<Song> songs, {int initialIndex = 0}) async {
    final sources = songs.map((s) => AudioSource.uri(Uri.parse(api.getStreamUrl(s.id)), tag: _songToMediaItem(s))).toList();
    if (sources.isNotEmpty) {
      mediaItem.add(sources[initialIndex].tag as MediaItem);
    }
    if (sources.length == 1) {
      await player.setAudioSource(sources.first);
    } else {
      _playlist = ConcatenatingAudioSource(children: sources);
      await player.setAudioSource(_playlist, initialIndex: initialIndex);
    }
  }
  
  Future<void> addSongsToQueue(List<Song> songs) async {
    final sources = songs.map((s) => AudioSource.uri(Uri.parse(api.getStreamUrl(s.id)), tag: _songToMediaItem(s))).toList();
    await _playlist.addAll(sources);
  }
}
