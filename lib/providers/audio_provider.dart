import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import '../models/song.dart';
import '../api/navidrome_client.dart';
import '../main.dart'; // Provides audioHandler
import '../api/navidrome_client.dart';
import 'lyrics_provider.dart';

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
  DateTime _lastLocalUpdate = DateTime.now();

  @override
  QueueState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _pollTimer?.cancel();
      _saveTimer?.cancel();
    });
    
    Future.microtask(() {
      _listenToPlayer();
      _loadQueue(isInitial: true);
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

  Timer? _saveTimer;

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
            if (Platform.isAndroid || Platform.isIOS) {
              if (savedHistory.isNotEmpty) itemsToPlay.add(savedHistory.first);
              itemsToPlay.add(savedCurrent);
              if (savedQueue.isNotEmpty) itemsToPlay.add(savedQueue.first);
            } else {
              itemsToPlay.add(savedCurrent);
            }
            final initialIndex = (Platform.isAndroid || Platform.isIOS) && savedHistory.isNotEmpty ? 1 : 0;
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

    // Note: just_audio automatically transitions to the next song in a ConcatenatingAudioSource
    // when a track completes. We intercept this via the index change (Mobile only).
    _player.currentIndexStream.listen((index) {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      if (_isChangingSongInternally || index == null) return;
      
      final hasPrev = state.history.isNotEmpty;
      final expectedCurrentIndex = hasPrev ? 1 : 0;
      
      if (index > expectedCurrentIndex) {
        // User pressed skip next OR the track finished normally
        next();
      } else if (index < expectedCurrentIndex) {
        // User pressed skip previous
        previous();
      }
    });
  }

  Future<void> playSong(Song song) async {
    _isChangingSongInternally = true;
    state = state.copyWith(currentSong: song);
    
    try {
      int initialIndex = 0;
      final itemsToPlay = <Song>[];
      
      if (Platform.isAndroid || Platform.isIOS) {
        // 1. Previous Track
        if (state.history.isNotEmpty) {
          itemsToPlay.add(state.history.first);
          initialIndex = 1;
        }
        // 2. Current Track
        itemsToPlay.add(song);
        // 3. Next Track
        if (state.queue.isNotEmpty) {
          itemsToPlay.add(state.queue.first);
        }
      } else {
        // Desktop/Web
        itemsToPlay.add(song);
      }

      audioHandler.play();
      audioHandler.replaceQueue(itemsToPlay, initialIndex: initialIndex).catchError((e) {
        print("Error in replaceQueue: $e");
      });
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
      ref.read(translatedLyricsProvider((id: song.id, title: song.title, artist: song.artist)).future);
    }
    for (int i = 0; i < 2 && i < state.queue.length; i++) {
      // Just reading the provider triggers the network fetch and caches the result
      final song = state.queue[i];
      ref.read(translatedLyricsProvider((id: song.id, title: song.title, artist: song.artist)).future);
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
    }
  }

  void removeSongIds(List<String> songIdsToRemove) {
    final newQueue = state.queue.where((s) => !songIdsToRemove.contains(s.id)).toList();
    state = state.copyWith(queue: newQueue);
  }

  void removeSongAt(int index) {
    if (index >= 0 && index < state.queue.length) {
      final newQueue = List<Song>.from(state.queue)..removeAt(index);
      state = state.copyWith(queue: newQueue);
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
      playSong(state.currentSong!);
      return;
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
      return;
    }
    while (state.queue.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 20));
      state = state.copyWith(queue: List.from(state.queue)..removeLast());
    }
  }

  void updateQueue(List<Song> newQueue) {
    state = state.copyWith(queue: newQueue);
  }

  Future<void> generateInstantMix() async {
    // Fetch a batch of random songs to serve as an instant mix
    // Navidrome's getRandomSongs will pull a fresh batch from the server
    final mixSongs = await _api.getRandomSongs(size: 20);
    addListToQueue(mixSongs);
  }

  void toggleShuffle() {
    final newShuffle = !state.isShuffle;
    if (newShuffle) {
      final newQueue = List<Song>.from(state.queue)..shuffle();
      state = state.copyWith(isShuffle: newShuffle, queue: newQueue);
    } else {
      state = state.copyWith(isShuffle: newShuffle);
    }
  }

  void toggleLoop() {
    final newMode = state.loopMode == AppLoopMode.off
        ? AppLoopMode.all
        : state.loopMode == AppLoopMode.all
            ? AppLoopMode.one
            : AppLoopMode.off;
    state = state.copyWith(loopMode: newMode);
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
}
