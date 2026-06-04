import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class QueueNotifier extends Notifier<QueueState> {
  @override
  QueueState build() {
    // The player provider might not be initialized yet, so listen later or in a microtask
    Future.microtask(() => _listenToPlayer());
    return QueueState();
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
    for (int i = 0; i < 2 && i < state.queue.length; i++) {
      // Just reading the provider triggers the network fetch and caches the result
      ref.read(translatedLyricsProvider(state.queue[i]).future);
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

  void addListToQueue(List<Song> songs) {
    if (songs.isEmpty) return;

    state = state.copyWith(queue: [...state.queue, ...songs]);
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

  void clearQueue() {
    state = state.copyWith(queue: []);
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
