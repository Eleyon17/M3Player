import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class NavidromeClient {
  String url = '';
  String user = '';
  String pass = '';
  String salt = '';
  String token = '';
  final String version = '1.16.1';
  final String client = 'm3-flutter';

  bool get isConfigured => url.isNotEmpty && user.isNotEmpty && pass.isNotEmpty;

  void configure(String url, String user, String pass) {
    this.url = url.trim();
    if (this.url.endsWith('/')) {
      this.url = this.url.substring(0, this.url.length - 1);
    }
    this.user = user;
    this.pass = pass;
    _generateAuth();
  }

  void _generateAuth() {
    salt = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode(pass + salt);
    token = md5.convert(bytes).toString();
  }

  String _getBaseParams() {
    return 'u=${Uri.encodeComponent(user)}&t=$token&s=$salt&v=$version&c=$client&f=json';
  }

  String _getMediaParams() {
    return 'u=${Uri.encodeComponent(user)}&t=$token&s=$salt&v=$version&c=$client';
  }

  String getCoverUrl(String? id, {int? size}) {
    if (id == null || id.isEmpty) return '';
    final sizeParam = size != null ? '&size=$size' : '';
    return '$url/rest/getCoverArt.view?id=$id$sizeParam&${_getMediaParams()}';
  }

  String getStreamUrl(String id) {
    return '$url/rest/stream.view?id=$id&${_getMediaParams()}&format=mp3';
  }

  Future<Map<String, dynamic>> _fetch(String endpoint, [String params = '']) async {
    if (!isConfigured) throw Exception('NavidromeClient not configured');
    final query = params.isNotEmpty ? '$params&${_getBaseParams()}' : _getBaseParams();
    final requestUrl = Uri.parse('$url/rest/$endpoint?$query');
    
    final response = await http.get(requestUrl);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final subsonicResponse = json['subsonic-response'];
      if (subsonicResponse['status'] == 'ok') {
        return subsonicResponse;
      } else {
        throw Exception(subsonicResponse['error']?['message'] ?? 'API Error');
      }
    } else {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
  }

  Future<bool> ping() async {
    try {
      await _fetch('ping.view');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Song>> getRandomSongs({int size = 50}) async {
    final response = await _fetch('getRandomSongs.view', 'size=$size');
    final songsList = response['randomSongs']?['song'] as List<dynamic>? ?? [];
    return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }
  
  Future<List<Song>> getSimilarSongs(String id, {int count = 15}) async {
    final response = await _fetch('getSimilarSongs.view', 'id=$id&count=$count');
    final songsList = response['similarSongs']?['song'] as List<dynamic>? ?? [];
    return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Song?> getSong(String id) async {
    final response = await _fetch('getSong.view', 'id=$id');
    final songData = response['song'];
    if (songData != null) {
      if (songData is List && songData.isNotEmpty) {
         return Song.fromJson(songData.first as Map<String, dynamic>);
      } else if (songData is Map) {
         return Song.fromJson(songData as Map<String, dynamic>);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getArtistInfo(String artistId) async {
    try {
      final response = await _fetch('getArtistInfo.view', 'id=$artistId');
      return response['artistInfo'] as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  Future<List<Song>> getTopSongs(String artistName, {int count = 4}) async {
    try {
      final response = await _fetch('getTopSongs.view', 'artist=$artistName&count=$count');
      final songsList = response['topSongs']?['song'] as List<dynamic>? ?? [];
      return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getArtist(String artistId) async {
    try {
      final response = await _fetch('getArtist.view', 'id=$artistId');
      return response['artist']?['album'] as List<dynamic>? ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> getWikipediaSummary(String artistName) async {
    try {
      final url = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/\${Uri.encodeComponent(artistName)}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['extract'] as String?;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
  
  Future<List<Map<String, dynamic>>> getArtists() async {
    try {
      final response = await _fetch('getArtists.view');
      final indexes = response['artists']?['index'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> allArtists = [];
      for (final index in indexes) {
        final artistList = index['artist'] as List<dynamic>? ?? [];
        allArtists.addAll(artistList.cast<Map<String, dynamic>>());
      }
      return allArtists;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAlbumList({String type = 'newest', int size = 50}) async {
    try {
      final response = await _fetch('getAlbumList.view', 'type=$type&size=$size');
      final albums = response['albumList']?['album'] as List<dynamic>? ?? [];
      return albums.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getStarred() async {
    try {
      final response = await _fetch('getStarred.view');
      final songsList = response['starred']?['song'] as List<dynamic>? ?? [];
      return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getAlbum(String albumId) async {
    try {
      final response = await _fetch('getAlbum.view', 'id=$albumId');
      final songsList = response['album']?['song'] as List<dynamic>? ?? [];
      return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> getLyrics(String? artist, String title) async {
    if (artist != null) {
      try {
        final uri = Uri.parse('https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(artist)}&track_name=${Uri.encodeComponent(title)}');
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['syncedLyrics'] != null && data['syncedLyrics'].toString().isNotEmpty) {
            return data['syncedLyrics'];
          }
          if (data['plainLyrics'] != null && data['plainLyrics'].toString().isNotEmpty) {
            return data['plainLyrics'];
          }
        }
      } catch (_) {}
    }

    // Fallback to Navidrome
    try {
      final params = artist != null 
        ? 'artist=${Uri.encodeComponent(artist)}&title=${Uri.encodeComponent(title)}'
        : 'title=${Uri.encodeComponent(title)}';
      final response = await _fetch('getLyrics.view', params);
      return response['lyrics']?['value'] as String?;
    } catch (e) {
      return null;
    }
  }
  
  Future<Map<String, List<dynamic>>> search(String query) async {
    try {
      final response = await _fetch('search3.view', 'query=${Uri.encodeComponent(query)}&songCount=15&albumCount=10&artistCount=10');
      final result = response['searchResult3'] ?? {};
      
      final songsList = result['song'] as List<dynamic>? ?? [];
      final albumsList = result['album'] as List<dynamic>? ?? [];
      final artistsList = result['artist'] as List<dynamic>? ?? [];
      
      return {
        'songs': songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList(),
        'albums': albumsList.cast<Map<String, dynamic>>(),
        'artists': artistsList.cast<Map<String, dynamic>>(),
      };
    } catch (e) {
      return {'songs': [], 'albums': [], 'artists': []};
    }
  }

  Future<void> scrobble(String id, {bool submission = true}) async {
    await _fetch('scrobble.view', 'id=$id&submission=$submission');
  }

  Future<void> star(String id) async {
    await _fetch('star.view', 'id=$id');
  }

  Future<void> unstar(String id) async {
    await _fetch('unstar.view', 'id=$id');
  }

  Future<List<Map<String, dynamic>>> getRandomArtists(int count) async {
    try {
      final allArtists = await getArtists();
      if (allArtists.isEmpty) return [];
      final now = DateTime.now();
      final seed = now.year * 10000 + now.month * 100 + now.day;
      allArtists.shuffle(Random(seed));
      return allArtists.take(count).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getTopSongsFromFavoriteArtists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastFetch = prefs.getInt('last_favorite_artists_fetch') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (now - lastFetch < 3 * 60 * 60 * 1000) {
        final cached = prefs.getString('cached_favorite_artists_songs');
        if (cached != null) {
          final List<dynamic> decoded = jsonDecode(cached);
          return decoded.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
        }
      }

      final starredSongs = await getStarred();
      final starredIds = starredSongs.map((s) => s.id).toSet();
      
      final int seedVal = (DateTime.now().millisecondsSinceEpoch ~/ (3 * 60 * 60 * 1000)) + starredSongs.length;
      final random = Random(seedVal);

      final Set<String> artistNames = starredSongs.map((s) => s.artist ?? '').where((s) => s.isNotEmpty).toSet();
      
      List<String> artists = artistNames.toList();
      if (artists.isEmpty) {
         // Fallback if no starred songs
         final randSongs = await getRandomSongs(size: 20);
         artists = randSongs.map((s) => s.artist ?? '').where((s) => s.isNotEmpty).toSet().toList();
      }
      artists.shuffle(random);
      artists = artists.take(5).toList();
      
      List<Song> songs = [];
      final futures = artists.map((artist) => getTopSongs(artist, count: 10));
      final results = await Future.wait(futures);
      
      for (final top in results) {
        // Never suggest a song you've already favorited
        songs.addAll(top.where((s) => !starredIds.contains(s.id)));
      }
      songs.shuffle(random);
      
      // Save to cache
      await prefs.setInt('last_favorite_artists_fetch', now);
      await prefs.setString('cached_favorite_artists_songs', jsonEncode(songs.map((s) => s.toJson()).toList()));
      
      return songs;
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getRediscoverSongs({int count = 50}) async {
    try {
      // Fetch a large pool of random songs
      final response = await _fetch('getRandomSongs.view', 'size=300');
      final songsList = response['randomSongs']?['song'] as List<dynamic>? ?? [];
      final songs = songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
      
      // Sort by playCount (ascending, treating 0 as first)
      songs.sort((a, b) {
        return a.playCount.compareTo(b.playCount);
      });
      return songs.take(count).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getPlaylists() async {
    try {
      final response = await _fetch('getPlaylists.view');
      return response['playlists']?['playlist'] as List<dynamic>? ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> getPlaylistSongs(String id) async {
    try {
      final response = await _fetch('getPlaylist.view', 'id=$id');
      final songsList = response['playlist']?['entry'] as List<dynamic>? ?? [];
      return songsList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  // --- Playlist Manipulation API ---
  Future<void> createPlaylist(String name) async {
    try {
      await _fetch('createPlaylist.view', 'name=${Uri.encodeComponent(name)}');
    } catch (e) {
      print("Error creating playlist: $e");
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      await _fetch('deletePlaylist.view', 'id=$id');
    } catch (e) {
      print("Error deleting playlist: $e");
    }
  }

  Future<void> updatePlaylist(String id, {List<String>? songIdsToAdd, List<int>? songIndexesToRemove}) async {
    try {
      final params = <String>['playlistId=$id'];
      if (songIdsToAdd != null) {
        for (var songId in songIdsToAdd) {
          params.add('songIdToAdd=$songId');
        }
      }
      if (songIndexesToRemove != null) {
        for (var index in songIndexesToRemove) {
          params.add('songIndexToRemove=$index');
        }
      }
      if (params.length > 1) {
        await _fetch('updatePlaylist.view', params.join('&'));
      }
    } catch (e) {
      print("Error updating playlist: $e");
    }
  }

  // --- Play Queue Syncing API ---
  Future<void> savePlayQueue(List<String> songIds, {String? currentId, int? positionMillis}) async {
    try {
      final params = <String>[];
      for (var id in songIds) {
        params.add('id=$id');
      }
      if (currentId != null) {
        params.add('current=$currentId');
      }
      if (positionMillis != null) {
        params.add('position=$positionMillis');
      }
      final paramString = params.join('&');
      
      // If the queue is huge, standard GET might exceed URI limits.
      // We will use POST for savePlayQueue to avoid URI too long errors.
      if (!isConfigured) throw Exception('NavidromeClient not configured');
      final query = _getBaseParams();
      final requestUrl = Uri.parse('$url/rest/savePlayQueue.view?$query');
      
      final response = await http.post(
        requestUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: paramString,
      );
      
      if (response.statusCode != 200) {
        print("Error saving play queue: HTTP ${response.statusCode}");
      }
    } catch (e) {
      print("Error saving play queue: $e");
    }
  }

  Future<Map<String, dynamic>?> getPlayQueue() async {
    try {
      final response = await _fetch('getPlayQueue.view');
      final playQueue = response['playQueue'];
      if (playQueue == null) return null;
      
      final entryList = playQueue['entry'] as List<dynamic>? ?? [];
      final songs = entryList.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
      
      return {
        'songs': songs,
        'current': playQueue['current']?.toString(), // The ID of current song
        'position': playQueue['position'], // in milliseconds
      };
    } catch (e) {
      print("Error getting play queue: $e");
      return null;
    }
  }
}
