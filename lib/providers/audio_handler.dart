import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../api/navidrome_client.dart';
import '../api/proxy_server.dart';

class MyAudioHandler {
  final AudioPlayer player;
  final NavidromeClient api;
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  MyAudioHandler(this.player, this.api);

  MediaItem _songToMediaItem(Song song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      album: song.album,
      artist: song.artist,
      artUri: Uri.tryParse(kIsWeb ? api.getCoverUrl(song.albumId ?? song.id, size: 500) : ProxyServer.getProxyUrl(api.getCoverUrl(song.albumId ?? song.id, size: 500))),
      // We pass the song data via extras so the UI can reconstruct it if needed
      extras: song.toJson(),
    );
  }

  Future<void> replaceQueue(List<Song> songs, {int initialIndex = 0}) async {
    final sources = songs.map((s) {
      final rawUrl = api.getStreamUrl(s.id);
      final proxyUrl = kIsWeb ? rawUrl : ProxyServer.getProxyUrl(rawUrl);
      return AudioSource.uri(Uri.parse(proxyUrl), tag: _songToMediaItem(s));
    }).toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(_playlist, initialIndex: initialIndex);
  }

  Future<void> addSongsToQueue(List<Song> songs) async {
    final sources = songs.map((s) {
      final rawUrl = api.getStreamUrl(s.id);
      final proxyUrl = kIsWeb ? rawUrl : ProxyServer.getProxyUrl(rawUrl);
      return AudioSource.uri(Uri.parse(proxyUrl), tag: _songToMediaItem(s));
    }).toList();
    await _playlist.addAll(sources);
  }

  /// Dynamically updates the native queue without interrupting playback
  Future<void> syncNativeQueue(List<Song> newSongs) async {
    final currentIndex = player.currentIndex;
    if (currentIndex == null || currentIndex < 0 || currentIndex >= _playlist.length) {
      await replaceQueue(newSongs);
      return;
    }

    final currentTag = _playlist.sequence[currentIndex].tag as MediaItem;
    int newCurrentIndex = -1;
    for (int i = 0; i < newSongs.length; i++) {
      if (newSongs[i].id == currentTag.id) {
        newCurrentIndex = i;
        break;
      }
    }

    if (newCurrentIndex == -1) {
      await replaceQueue(newSongs);
      return;
    }

    // CRITICAL FIX: NEVER remove or insert items at or before `currentIndex`.
    // Modifying items before the current playing item causes the native currentIndex to shift.
    // When currentIndex shifts, it triggers our `currentIndexStream` listener, 
    // which tricks the app into thinking the user pressed "Previous" or "Next" natively!
    // Since history natively is only ever 1 song (and we don't dynamically edit history anyway), 
    // we only need to dynamically sync the UPCOMING queue (everything after currentIndex).

    // Safely truncate history: Android Auto has memory limits. 
    // If the native currentIndex is > 1, it means old songs are accumulating in the native history.
    // We remove (0, currentIndex - 1) so exactly 1 previous song remains.
    // Note: Our Flutter app suppresses the `currentIndexStream` listener during dynamic syncs, 
    // so this visual index shift won't falsely trigger a "Previous" skip!
    if (currentIndex > 1) {
      await _playlist.removeRange(0, currentIndex - 1);
      // Wait! If we just removed items BEFORE currentIndex, the current index physically shifted!
      // This means we must NOT use the old `currentIndex` variable for calculating the upcoming removals below!
      // We need to re-fetch the new current index (or just recalculate it).
      // If we removed `currentIndex - 1` items, the new index is 1.
    }
    
    final updatedIndex = player.currentIndex ?? 1;

    // Remove all upcoming items from the native player
    if (_playlist.length > updatedIndex + 1) {
      await _playlist.removeRange(updatedIndex + 1, _playlist.length);
    }

    // Insert the new upcoming items
    if (newCurrentIndex < newSongs.length - 1) {
      final afterSources = newSongs.sublist(newCurrentIndex + 1).map((s) {
        final rawUrl = api.getStreamUrl(s.id);
        final proxyUrl = kIsWeb ? rawUrl : ProxyServer.getProxyUrl(rawUrl);
        return AudioSource.uri(Uri.parse(proxyUrl), tag: _songToMediaItem(s));
      }).toList();
      await _playlist.addAll(afterSources);
    }
  }

  Future<void> play() => player.play();

  Future<void> pause() => player.pause();

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> skipToNext() async {
    await player.seekToNext();
    if (!player.playing) play();
  }

  Future<void> skipToPrevious() async {
    await player.seekToPrevious();
    if (!player.playing) play();
  }

  Future<void> skipToQueueItem(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) play();
  }
}
