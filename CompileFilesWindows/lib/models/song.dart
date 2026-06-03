class Song {
  final String id;
  final String title;
  final String? artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final String? coverArt;
  final int duration;
  final int track;
  final String? suffix;
  final int bitRate;
  final String? starred;
  
  Song({
    required this.id,
    required this.title,
    this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.coverArt,
    this.duration = 0,
    this.track = 0,
    this.suffix,
    this.bitRate = 0,
    this.starred,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'],
      artistId: json['artistId']?.toString(),
      album: json['album'],
      albumId: json['albumId']?.toString(),
      coverArt: json['coverArt']?.toString(),
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
      track: json['track'] is int ? json['track'] : int.tryParse(json['track']?.toString() ?? '0') ?? 0,
      suffix: json['suffix'],
      bitRate: json['bitRate'] is int ? json['bitRate'] : int.tryParse(json['bitRate']?.toString() ?? '0') ?? 0,
      starred: json['starred']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'album': album,
      'albumId': albumId,
      'coverArt': coverArt,
      'duration': duration,
      'track': track,
      'suffix': suffix,
      'bitRate': bitRate,
      'starred': starred,
    };
  }
}
