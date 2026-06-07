import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import '../api/navidrome_client.dart';
import '../main.dart'; // Provides audioHandler
import 'lyrics_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';

final navidromeClientProvider = Provider<NavidromeClient>((ref) {
  return NavidromeClient();
});

final navidromePlaylistsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(navidromeClientProvider).getPlaylists();
});

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  return audioHandler.player; // Returns the global instance created in main
});

final queueProvider = NotifierProvider<QueueNotifier, QueueState>(QueueNotifier.new);

enum AppLoopMode { off, all, one }

class QueueState {
  final List<Song> queue;
  final List<Song> history;
  final Song? currentSong;
  final bool isShuffle;
  final AppLoopMode loopMode;

  QueueState({
    this.queue = const [],
    this.history = const [],
    this.currentSong,
    this.isShuffle = false,
    this.loopMode = AppLoopMode.off,
  });

  QueueState copyWith({
    List<Song>? queue,
    List<Song>? history,
    Song? currentSong,
    bool? isShuffle,
    AppLoopMode? loopMode,
  }) {
    return QueueState(
      queue: queue ?? this.queue,
      history: history ?? this.history,
      currentSong: currentSong ?? this.currentSong,
      isShuffle: isShuffle ?? this.isShuffle,
      loopMode: loopMode ?? this.loopMode,
    );
  }
}

class QueueNotifier extends Notifier<QueueState> with WidgetsBindingObserver {
  Timer? _pollTimer;
  Timer? _saveTimer;
  Timer? _nativeSyncTimer;
  DateTime _lastLocalUpdate = DateTime.now();

  @override
  QueueState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _pollTimer?.cancel();
      _saveTimer?.cancel();
      _nativeSyncTimer?.cancel();
    });
    
    Future.microtask(() {
      _listenToPlayer();
      _loadQueue(isInitial: true);
      _setupAndroidAuto();
      _startPolling();
    });
    return QueueState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User returned to the app, do a quick sync
      _loadQueue(isInitial: false);
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      // Only poll if we haven't made a local change in the last 5 seconds
      if (DateTime.now().difference(_lastLocalUpdate) > const Duration(seconds: 5)) {
        _loadQueue(isInitial: false);
      }
    });
  }

  @override
  set state(QueueState value) {
    super.state = value;
    _lastLocalUpdate = DateTime.now();
    _saveQueue();
  }

  void _triggerDynamicSync() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _nativeSyncTimer?.cancel();
    _nativeSyncTimer = Timer(const Duration(milliseconds: 200), () async {
      if (_isChangingSongInternally || state.currentSong == null) return;
      
      final historyItems = state.history.take(1).toList().reversed.toList();
      final queueItems = state.queue.take(50).toList();
      final newSongs = <Song>[];
      newSongs.addAll(historyItems);
      newSongs.add(state.currentSong!);
      newSongs.addAll(queueItems);
      await audioHandler.syncNativeQueue(newSongs);
    });
  }

  Future<void> _loadQueue({bool isInitial = false}) async {
    try {
      final queueData = await _api.getPlayQueue();
      if (queueData != null) {
        final songs = queueData['songs'] as List<Song>;
        final currentId = queueData['current'] as String?;
        
        List<Song> savedHistory = [];
        List<Song> savedQueue = [];
        Song? savedCurrent;
        
        if (currentId != null) {
          final currentIndex = songs.indexWhere((s) => s.id == currentId);
          if (currentIndex != -1) {
            savedHistory = songs.sublist(0, currentIndex).reversed.toList();
            savedCurrent = songs[currentIndex];
            savedQueue = songs.sublist(currentIndex + 1);
          } else {
            savedQueue = songs;
          }
        } else {
          savedQueue = songs;
        }
        
        // If we are just polling, only update the queue if it's actually different to avoid jank.
        // We do a simple length/id check. If it's different, we update state.
        final isDifferent = state.currentSong?.id != savedCurrent?.id || 
                            state.queue.length != savedQueue.length || 
                            state.history.length != savedHistory.length;
                            
        if (isInitial || isDifferent) {
          state = state.copyWith(currentSong: savedCurrent, queue: savedQueue, history: savedHistory);
          if (savedCurrent != null && isInitial) {
            final itemsToPlay = <Song>[];
            int initialIndex = 0;
            if (Platform.isAndroid || Platform.isIOS) {
              final historyItems = savedHistory.take(1).toList().reversed.toList();
              final queueItems = savedQueue.take(50).toList();
              itemsToPlay.addAll(historyItems);
              initialIndex = historyItems.length;
              itemsToPlay.add(savedCurrent);
              itemsToPlay.addAll(queueItems);
            } else {
              itemsToPlay.add(savedCurrent);
            }
            audioHandler.replaceQueue(itemsToPlay, initialIndex: initialIndex);
            
            final position = queueData['position'] as int?;
            if (position != null && position > 0) {
              audioHandler.seek(Duration(milliseconds: position));
            }
          }
        }
      }
    } catch (e) {
      print("Error loading queue from server: $e");
    }
  }

  void _saveQueue() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final songIds = <String>[];
        // History is stored most-recent first. Server wants chronological.
        songIds.addAll(state.history.reversed.map((s) => s.id));
        if (state.currentSong != null) songIds.add(state.currentSong!.id);
        songIds.addAll(state.queue.map((s) => s.id));
        
        if (songIds.isNotEmpty) {
          await _api.savePlayQueue(
            songIds,
            currentId: state.currentSong?.id,
            positionMillis: _player.position.inMilliseconds,
          );
        }
      } catch (e) {
        print("Error saving queue to server: $e");
      }
    });
  }

  AudioPlayer get _player => ref.read(audioPlayerProvider);
  NavidromeClient get _api => ref.read(navidromeClientProvider);

  bool _isChangingSongInternally = false;

  void _listenToPlayer() {
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        next();
      }
    });

    JustAudioBackground.customEventStream.listen((event) {
      if (event == 'action_favorite') {
        toggleFavorite();
      } else if (event == 'action_shuffle') {
        toggleShuffle();
      }
    });

    // Note: just_audio automatically transitions to the next song in a ConcatenatingAudioSource
    // when a track completes. We intercept this via the index change.
    // The native audio player is the ABSOLUTE TRUTH. If it changes to a new song,
    // the Flutter app MUST adjust its queue and history to match.
    _player.currentIndexStream.listen((index) {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      if (index == null) return;
      
      final sequenceState = _player.sequenceState;
      if (sequenceState == null || sequenceState.sequence.isEmpty) return;
      if (index < 0 || index >= sequenceState.sequence.length) return;
      
      final currentSource = sequenceState.sequence[index];
      final mediaItem = currentSource.tag as MediaItem?;
      if (mediaItem == null) return;
      
      final nativePlayingId = mediaItem.id;
      
      // If the native player is playing what we expect, we're perfectly in sync!
      if (state.currentSong?.id == nativePlayingId) return;
      
      // Otherwise, the native player has autonomously transitioned (or skipped).
      // Find where this new song is in our upcoming queue:
      final queueIndex = state.queue.indexWhere((s) => s.id == nativePlayingId);
      if (queueIndex != -1) {
        // Native player skipped forward!
        final skipCount = queueIndex + 1;
        nativeSkipForward(skipCount);
        return;
      }
      
      // If not in queue, check history (user skipped backward natively):
      final historyIndex = state.history.indexWhere((s) => s.id == nativePlayingId);
      if (historyIndex != -1) {
        final skipCount = historyIndex + 1;
        nativeSkipBackward(skipCount);
        return;
      }
      
      // If it's in neither, we are totally out of sync or a full queue replacement is occurring.
      // `playSong` will handle rebuilding the entire state.
    });
  }

  void nativeSkipForward(int count) {
    if (count <= 0) return;
    
    var newQueue = List<Song>.from(state.queue);
    var newHistory = List<Song>.from(state.history);
    Song? newCurrent = state.currentSong;
    
    if (count > newQueue.length) count = newQueue.length;
    if (count == 0) return;
    
    final targetIndex = count - 1;
    final targetSong = newQueue[targetIndex];
    
    // YANK BEHAVIOR:
    // If count > 1 (meaning the user tapped a specific song from the native queue list),
    // we pull that song out and leave the intermediate songs in the queue!
    // If count == 1 (rapid native skipping), this behaves identically to standard popping.
    newQueue.removeAt(targetIndex);
    
    if (newCurrent != null) {
      newHistory.insert(0, newCurrent);
      _api.scrobble(newCurrent.id, submission: true);
    }
    if (newHistory.length > 50) newHistory.removeLast();
    
    newCurrent = targetSong;
    
    state = state.copyWith(queue: newQueue, history: newHistory, currentSong: newCurrent);
    _api.scrobble(newCurrent.id, submission: false); // Report now playing
    _preloadLyrics();
    _triggerDynamicSync(); // Silently updates upcoming queue and truncates native history without interrupting playback
  }

  void nativeSkipBackward(int count) {
    if (count <= 0) return;
    
    var newQueue = List<Song>.from(state.queue);
    var newHistory = List<Song>.from(state.history);
    Song? newCurrent = state.currentSong;
    
    for (int i = 0; i < count; i++) {
      if (newHistory.isEmpty) break;
      if (newCurrent != null) {
        newQueue.insert(0, newCurrent);
      }
      newCurrent = newHistory.removeAt(0);
    }
    
    state = state.copyWith(queue: newQueue, history: newHistory, currentSong: newCurrent);
    _api.scrobble(newCurrent?.id ?? '', submission: false); // Report now playing
    _preloadLyrics();
    _triggerDynamicSync(); // Silently updates upcoming queue without interrupting playback
  }

  Future<void> playSong(Song song) async {
    _isChangingSongInternally = true;
    state = state.copyWith(currentSong: song);
    
    try {
      int initialIndex = 0;
      final itemsToPlay = <Song>[];
      
      if (Platform.isAndroid || Platform.isIOS) {
        // We pass a subset of the queue to the native OS to avoid memory issues
        // while still giving Android Auto/Wear OS enough context to display a queue.
        final historyItems = state.history.take(1).toList().reversed.toList();
        final queueItems = state.queue.take(50).toList();
        
        itemsToPlay.addAll(historyItems);
        initialIndex = historyItems.length;
        
        itemsToPlay.add(song);
        itemsToPlay.addAll(queueItems);
      } else {
        // Desktop/Web
        itemsToPlay.add(song);
      }

      await audioHandler.replaceQueue(itemsToPlay, initialIndex: initialIndex).catchError((e) {
        print("Error in replaceQueue: $e");
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Audio Engine Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          )
        );
      });
      audioHandler.play();
      _api.scrobble(song.id, submission: false); // Report now playing
      _preloadLyrics();
    } catch (e) {
      print("Error playing song: $e");
    } finally {
      // Debounce the internal change flag so index updates from just_audio are suppressed
      Future.delayed(const Duration(milliseconds: 500), () {
        _isChangingSongInternally = false;
      });
    }
  }

  void addToQueue(Song song) {
    state = state.copyWith(queue: [...state.queue, song]);
    if (state.currentSong == null) {
      next();
    } else {
      _triggerDynamicSync();
    }
  }

  void playNext(Song song) {
    state = state.copyWith(queue: [song, ...state.queue]);
    if (state.currentSong == null) {
      next();
    } else {
      _preloadLyrics();
    }
  }

  void playInstantly(Song song) {
    if (state.currentSong == null) {
      state = state.copyWith(queue: [song, ...state.queue]);
      next();
    } else {
      final currentIndex = state.queue.indexWhere((s) => s.id == state.currentSong?.id);
      if (currentIndex != -1) {
        final newQueue = List<Song>.from(state.queue);
        newQueue.insert(currentIndex + 1, song);
        state = state.copyWith(queue: newQueue);
        next();
      } else {
        state = state.copyWith(queue: [song, ...state.queue]);
        next();
      }
      // Note: next() calls playSong() which already calls _preloadLyrics()
    }
  }

  void _preloadLyrics() {
    if (state.currentSong != null) {
      final song = state.currentSong!;
      ref.read(translatedLyricsProvider((id: song.id, title: song.title, artist: song.artist, album: song.album)).future);
    }
    for (int i = 0; i < 2 && i < state.queue.length; i++) {
      // Just reading the provider triggers the network fetch and caches the result
      final song = state.queue[i];
      ref.read(translatedLyricsProvider((id: song.id, title: song.title, artist: song.artist, album: song.album)).future);
    }
  }

  void insertNext(Song song) {
    if (state.currentSong == null) {
      addListToQueue([song]);
      return;
    }
    
    // Insert at the top of the queue since currentSong is now separate from the queue list
    final newQueue = List<Song>.from(state.queue);
    newQueue.insert(0, song);
    state = state.copyWith(queue: newQueue);
    _preloadLyrics();
    _triggerDynamicSync();
  }

  Future<void> addListToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;

    if (songs.length > 50) {
      state = state.copyWith(queue: [...state.queue, ...songs]);
    } else {
      for (var song in songs) {
        await Future.delayed(const Duration(milliseconds: 30));
        state = state.copyWith(queue: [...state.queue, song]);
      }
    }

    if (state.currentSong == null) {
      next();
    } else {
      _preloadLyrics();
      _triggerDynamicSync();
    }
  }

  void removeSongIds(List<String> songIdsToRemove) {
    final newQueue = state.queue.where((s) => !songIdsToRemove.contains(s.id)).toList();
    state = state.copyWith(queue: newQueue);
    _triggerDynamicSync();
  }

  void removeSongAt(int index) {
    if (index >= 0 && index < state.queue.length) {
      final newQueue = List<Song>.from(state.queue)..removeAt(index);
      state = state.copyWith(queue: newQueue);
      _triggerDynamicSync();
    }
  }

  void playPrevious() {
    if (state.queue.isEmpty) return;
    final last = state.queue.last;
    state = state.copyWith(queue: [last, ...state.queue.sublist(0, state.queue.length - 1)]);
    playSong(last);
  }

  void next() {
    if (state.queue.isEmpty) {
      if (state.loopMode == AppLoopMode.all && state.history.isNotEmpty) {
        // Rebuild queue from history + current song
        final fullList = state.history.reversed.toList();
        if (state.currentSong != null) fullList.add(state.currentSong!);
        if (state.isShuffle) fullList.shuffle();
        state = state.copyWith(queue: fullList, history: []);
        if (state.queue.isNotEmpty) {
          next();
        }
      }
      return;
    }
    
    // Check loop one
    if (state.loopMode == AppLoopMode.one && state.currentSong != null) {
      _player.seek(Duration.zero);
      return;
    }
    
    if (Platform.isAndroid || Platform.isIOS) {
      if (_player.hasNext) {
        _player.seekToNext();
        return; // The currentIndexStream listener will handle the Flutter state update safely!
      }
    }
    
    final songToPlay = state.queue.first;
    final newQueue = List<Song>.from(state.queue)..removeAt(0);
    
    final newHistory = List<Song>.from(state.history);
    if (state.currentSong != null) {
      newHistory.insert(0, state.currentSong!);
      // Scrobble the previous track
      _api.scrobble(state.currentSong!.id, submission: true);
    }
    if (newHistory.length > 50) newHistory.removeLast();

    state = state.copyWith(
      queue: newQueue,
      history: newHistory,
    );
    
    playSong(songToPlay);
  }

  void playFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    
    final songToPlay = state.queue[index];
    final newQueue = List<Song>.from(state.queue);
    
    // Remove only the selected song from its current position
    newQueue.removeAt(index);
    
    final newHistory = List<Song>.from(state.history);
    if (state.currentSong != null) {
      newHistory.insert(0, state.currentSong!);
      _api.scrobble(state.currentSong!.id, submission: true);
    }
    if (newHistory.length > 50) newHistory.removeLast();

    state = state.copyWith(
      queue: newQueue,
      history: newHistory,
    );
    
    playSong(songToPlay);
  }

  void previous() {
    if (state.history.isEmpty) {
      _player.seek(Duration.zero);
      return;
    }
    
    if (Platform.isAndroid || Platform.isIOS) {
      if (_player.hasPrevious) {
        _player.seekToPrevious();
        return; // The currentIndexStream listener will handle the Flutter state update safely!
      }
    }
    
    final songToPlay = state.history.first;
    final newHistory = List<Song>.from(state.history)..removeAt(0);
    
    final newQueue = List<Song>.from(state.queue);
    if (state.currentSong != null) {
      newQueue.insert(0, state.currentSong!);
    }

    state = state.copyWith(
      queue: newQueue,
      history: newHistory,
    );
    
    playSong(songToPlay);
  }

  Future<void> clearQueue() async {
    if (state.queue.length > 50) {
      state = state.copyWith(queue: []);
      _triggerDynamicSync();
      return;
    }
    while (state.queue.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = state.copyWith(queue: List.from(state.queue)..removeLast());
    }
    _triggerDynamicSync();
  }

  void updateQueue(List<Song> newQueue) {
    state = state.copyWith(queue: newQueue);
    _triggerDynamicSync();
  }

  Future<void> generateInstantMix() async {
    // Fetch a batch of random songs to serve as an instant mix
    // Navidrome's getRandomSongs will pull a fresh batch from the server
    final mixSongs = await _api.getRandomSongs(size: 20);
    addListToQueue(mixSongs);
  }

  void playQueue(List<Song> songs, {int initialIndex = 0}) {
    if (songs.isEmpty) return;
    
    final currentSong = songs[initialIndex];
    final history = songs.sublist(0, initialIndex).reversed.toList();
    final newQueue = songs.sublist(initialIndex + 1);
    
    state = state.copyWith(
      currentSong: currentSong,
      queue: newQueue,
      history: history,
      isShuffle: false,
    );
    
    audioHandler.player.seek(Duration.zero);
    _triggerDynamicSync();
  }

  void toggleShuffle() {
    final newShuffle = !state.isShuffle;
    if (newShuffle) {
      final newQueue = List<Song>.from(state.queue)..shuffle();
      state = state.copyWith(isShuffle: newShuffle, queue: newQueue);
    } else {
      state = state.copyWith(isShuffle: newShuffle);
    }
    _triggerDynamicSync();
  }

  void toggleLoop() {
    final nextMode = AppLoopMode.values[(state.loopMode.index + 1) % AppLoopMode.values.length];
    state = state.copyWith(loopMode: nextMode);
  }

  Future<void> toggleFavorite() async {
    final song = state.currentSong;
    if (song == null) return;
    
    final isStarred = song.starred != null;
    if (isStarred) {
      await _api.unstar(song.id);
    } else {
      await _api.star(song.id);
    }
    
    // Update local state without breaking json parse
    final updatedSongMap = song.toJson();
    updatedSongMap['starred'] = isStarred ? null : DateTime.now().toIso8601String();
    final updatedSong = Song.fromJson(updatedSongMap);
    
    final newQueue = state.queue.map((s) => s.id == song.id ? updatedSong : s).toList();
    final newHistory = state.history.map((s) => s.id == song.id ? updatedSong : s).toList();

    state = state.copyWith(
      currentSong: updatedSong,
      queue: newQueue,
      history: newHistory,
    );
  }

  void _setupAndroidAuto() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    
    final api = ref.read(navidromeClientProvider);
    
    JustAudioBackground.getChildrenCallback = (parentMediaId) async {
      try {
        if (parentMediaId == AudioService.browsableRootId || parentMediaId == 'root') {
          return [
            MediaItem(id: 'tab_playlists', title: 'Playlists', playable: false),
            MediaItem(id: 'tab_albums', title: 'Albums', playable: false),
            MediaItem(id: 'tab_artists', title: 'Artists', playable: false),
            MediaItem(id: 'tab_favorites', title: 'Favorites', playable: false),
          ];
        }
        
        if (parentMediaId == 'tab_playlists') {
          final playlists = await api.getPlaylists();
          return playlists.map((p) => MediaItem(id: "playlist_${p['id']}", title: p['name'] ?? 'Unknown', playable: false)).toList();
        }
        
        if (parentMediaId == 'tab_albums') {
          final albums = await api.getAlbumList(size: 50); // Get recent albums
          return albums.map((a) => MediaItem(
            id: "album_${a['id']}", 
            title: a['name'] ?? 'Unknown', 
            artist: a['artist'], 
            artUri: Uri.tryParse(api.getCoverUrl(a['id'], size: 500)),
            playable: false
          )).toList();
        }
        
        if (parentMediaId == 'tab_artists') {
          final artists = await api.getArtists();
          return artists.map((a) => MediaItem(id: "artist_${a['id']}", title: a['name'] ?? 'Unknown', playable: false)).toList();
        }
        
        if (parentMediaId == 'tab_favorites') {
          final songs = await api.getStarred();
          return songs.map((s) => MediaItem(
            id: "fav_song_${s.id}",
            title: s.title,
            album: s.album,
            artist: s.artist,
            artUri: Uri.tryParse(api.getCoverUrl(s.albumId ?? s.id, size: 500)),
            playable: true,
            extras: s.toJson()
          )).toList();
        }
        
        if (parentMediaId.startsWith('playlist_')) {
          final id = parentMediaId.substring(9);
          final songs = await api.getPlaylistSongs(id);
          return songs.map((s) => MediaItem(
            id: "playlist_${id}_song_${s.id}",
            title: s.title,
            album: s.album,
            artist: s.artist,
            artUri: Uri.tryParse(api.getCoverUrl(s.albumId ?? s.id, size: 500)),
            playable: true,
            extras: s.toJson()
          )).toList();
        }
        
        if (parentMediaId.startsWith('album_')) {
          final id = parentMediaId.substring(6);
          final songs = await api.getAlbum(id);
          return songs.map((s) => MediaItem(
            id: "album_${id}_song_${s.id}",
            title: s.title,
            album: s.album,
            artist: s.artist,
            artUri: Uri.tryParse(api.getCoverUrl(s.albumId ?? s.id, size: 500)),
            playable: true,
            extras: s.toJson()
          )).toList();
        }
        
        if (parentMediaId.startsWith('artist_')) {
          final id = parentMediaId.substring(7);
          final albums = await api.getArtist(id);
          return albums.map((a) => MediaItem(
            id: "album_${a['id']}", 
            title: a['name'] ?? 'Unknown', 
            artist: a['artist'], 
            artUri: Uri.tryParse(api.getCoverUrl(a['id'], size: 500)),
            playable: false
          )).toList();
        }
      } catch (e) {
        debugPrint('Error fetching Android Auto children: \$e');
      }
      
      return [];
    };

    JustAudioBackground.playFromMediaIdCallback = (mediaId) async {
      try {
        List<Song> queueToPlay = [];
        int startIndex = 0;
        
        if (mediaId.startsWith('album_')) {
          final parts = mediaId.split('_song_');
          final albumId = parts[0].substring(6);
          final songId = parts.length > 1 ? parts[1] : null;
          
          queueToPlay = await api.getAlbum(albumId);
          if (songId != null) {
            startIndex = queueToPlay.indexWhere((s) => s.id == songId);
            if (startIndex == -1) startIndex = 0;
          }
        } else if (mediaId.startsWith('playlist_')) {
          final parts = mediaId.split('_song_');
          final playlistId = parts[0].substring(9);
          final songId = parts.length > 1 ? parts[1] : null;
          
          queueToPlay = await api.getPlaylistSongs(playlistId);
          if (songId != null) {
            startIndex = queueToPlay.indexWhere((s) => s.id == songId);
            if (startIndex == -1) startIndex = 0;
          }
        } else if (mediaId.startsWith('fav_song_')) {
          final songId = mediaId.substring(9);
          queueToPlay = await api.getStarred();
          startIndex = queueToPlay.indexWhere((s) => s.id == songId);
          if (startIndex == -1) startIndex = 0;
        }
        
        if (queueToPlay.isNotEmpty) {
          playQueue(queueToPlay, initialIndex: startIndex);
        }
      } catch (e) {
        debugPrint('Error playing from Android Auto mediaId: \$e');
      }
    };
  }
}
