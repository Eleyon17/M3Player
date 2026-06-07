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

    int newCurrentIndex = -1;
    final currentTag = _playlist.sequence[currentIndex].tag as MediaItem;
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

    // Remove all items AFTER the current index.
    if (_playlist.length > currentIndex + 1) {
      await _playlist.removeRange(currentIndex + 1, _playlist.length);
    }
    // Remove all items BEFORE the current index.
    if (currentIndex > 0) {
      await _playlist.removeRange(0, currentIndex);
    }

    // Insert new items that come BEFORE it.
    if (newCurrentIndex > 0) {
      final beforeSources = newSongs.sublist(0, newCurrentIndex).map((s) {
        final rawUrl = api.getStreamUrl(s.id);
        final proxyUrl = kIsWeb ? rawUrl : ProxyServer.getProxyUrl(rawUrl);
        return AudioSource.uri(Uri.parse(proxyUrl), tag: _songToMediaItem(s));
      }).toList();
      await _playlist.insertAll(0, beforeSources);
    }

    // Insert new items that come AFTER it.
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
