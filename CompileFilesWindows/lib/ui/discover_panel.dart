import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/navidrome_client.dart';
import '../models/song.dart';
import '../providers/audio_provider.dart';
import 'widgets/bubbly_widgets.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../providers/translation_provider.dart';

class DiscoverSearchQuery extends Notifier<String> {
  @override
  String build() => '';
}

final discoverSearchQueryProvider = NotifierProvider<DiscoverSearchQuery, String>(DiscoverSearchQuery.new);

class DiscoverPanel extends ConsumerStatefulWidget {
  const DiscoverPanel({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoverPanel> createState() => _DiscoverPanelState();
}

class _DiscoverPanelState extends ConsumerState<DiscoverPanel> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  
  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showTranslationsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          title: const Text('Translate Lyrics to:'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('None'),
                leading: Radio<String>(
                  value: 'none',
                  groupValue: ref.watch(translationLanguageProvider),
                  onChanged: (val) {
                    ref.read(translationLanguageProvider.notifier).state = val!;
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).state = 'none';
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Spanish'),
                leading: Radio<String>(
                  value: 'es',
                  groupValue: ref.watch(translationLanguageProvider),
                  onChanged: (val) {
                    ref.read(translationLanguageProvider.notifier).state = val!;
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).state = 'es';
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('English'),
                leading: Radio<String>(
                  value: 'en',
                  groupValue: ref.watch(translationLanguageProvider),
                  onChanged: (val) {
                    ref.read(translationLanguageProvider.notifier).state = val!;
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).state = 'en';
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    return Column(
      children: [
        // Soft Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search for songs, albums, or artists...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchQuery.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(discoverSearchQueryProvider.notifier).state = '';
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      ref.read(discoverSearchQueryProvider.notifier).state = val;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.settings),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                offset: const Offset(0, 48),
                onSelected: (value) {
                  if (value == 'translations') {
                    _showTranslationsDialog(context, ref);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'translations',
                    child: Row(children: [Icon(Icons.translate), SizedBox(width: 12), Text('Translations')]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'theme',
                    child: Row(children: [Icon(Icons.palette), SizedBox(width: 12), Text('Theme')]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'changelog',
                    child: Row(children: [Icon(Icons.history), SizedBox(width: 12), Text('Changelog')]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(children: [Icon(Icons.logout), SizedBox(width: 12), Text('Logout')]),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        Expanded(
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TabBar(
                    isScrollable: false,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    splashBorderRadius: BorderRadius.circular(30),
                    labelPadding: const EdgeInsets.symmetric(vertical: 4.0),
                  labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: "All"),
                    Tab(text: "Artists"),
                    Tab(text: "Albums"),
                    Tab(text: "Favorites"),
                  ],
                ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _NestedNav(initialRoute: const _AllTab()),
                      _NestedNav(initialRoute: _ArtistsTab()),
                      _NestedNav(initialRoute: _AlbumsTab()),
                      _FavoritesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NestedNav extends StatelessWidget {
  final Widget initialRoute;
  const _NestedNav({required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(builder: (_) => initialRoute);
      },
    );
  }
}

// ==========================
// TABS & SEARCH
// ==========================

class _SearchResultsTab extends ConsumerWidget {
  final String query;
  const _SearchResultsTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    return FutureBuilder<Map<String, List<dynamic>>>(
      future: api.search(query),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final results = snapshot.data!;
        final songs = (results['songs'] as List).cast<Song>();
        final albums = (results['albums'] as List).cast<Map<String, dynamic>>();
        final artists = (results['artists'] as List).cast<Map<String, dynamic>>();

        if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
          return const Center(child: Text("No results found."));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (artists.isNotEmpty) ...[
              Text("Artists", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: artists.length,
                  itemBuilder: (context, index) => SizedBox(
                    width: 160,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: ArtistTile(artist: artists[index]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (albums.isNotEmpty) ...[
              Text("Albums", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: albums.length,
                  itemBuilder: (context, index) => SizedBox(
                    width: 160,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: AlbumTile(album: albums[index]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (songs.isNotEmpty) ...[
              Text("Songs", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...songs.map((song) => SongTile(song: song)),
            ]
          ],
        );
      },
    );
  }
}


class _AllTab extends ConsumerWidget {
  const _AllTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    if (searchQuery.isNotEmpty) {
      return _SearchResultsTab(query: searchQuery);
    }

    final api = ref.watch(navidromeClientProvider);
    return FutureBuilder<List<Song>>(
      future: api.getRandomSongs(size: 50),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final songs = snapshot.data!;
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) => SongTile(song: songs[index]),
        );
      },
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    final searchQuery = ref.watch(discoverSearchQueryProvider).toLowerCase();

    return FutureBuilder<List<Song>>(
      future: api.getStarred(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        var songs = snapshot.data!;
        if (searchQuery.isNotEmpty) {
          songs = songs.where((s) {
            return s.title.toLowerCase().contains(searchQuery) || 
                   (s.artist?.toLowerCase().contains(searchQuery) ?? false) ||
                   (s.album?.toLowerCase().contains(searchQuery) ?? false);
          }).toList();
        }
        
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) => SongTile(song: songs[index]),
        );
      },
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    
    final future = searchQuery.isNotEmpty
        ? api.search(searchQuery).then((res) => (res['artists'] as List).cast<Map<String, dynamic>>())
        : api.getArtists();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final artists = snapshot.data!;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            return ArtistTile(artist: artists[index]);
          },
        );
      },
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  final String? artistId;
  const _AlbumsTab({this.artistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    
    final future = artistId != null 
        ? api.getArtist(artistId!).then((albums) => albums.cast<Map<String, dynamic>>())
        : searchQuery.isNotEmpty
            ? api.search(searchQuery).then((res) => (res['albums'] as List).cast<Map<String, dynamic>>())
            : api.getAlbumList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: artistId != null ? AppBar(
        title: const Text("Albums"),
        backgroundColor: Colors.transparent,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ) : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final albums = snapshot.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) => AlbumTile(album: albums[index]),
          );
        },
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  final String albumId;
  final String albumTitle;

  const _SongsTab({required this.albumId, required this.albumTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(albumTitle),
        backgroundColor: Colors.transparent,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: FutureBuilder<List<Song>>(
        future: api.getAlbum(albumId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final songs = snapshot.data!;
          return ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) => SongTile(song: songs[index]),
          );
        },
      ),
    );
  }
}

// ==========================
// TILES & ACTIONS
// ==========================

class SongTile extends ConsumerWidget {
  final Song song;
  const SongTile({Key? key, required this.song}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        onTap: () {
          ref.read(queueProvider.notifier).playInstantly(song);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: api.getCoverUrl(song.albumId ?? song.id, size: 150),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.music_note),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(song.artist ?? 'Unknown Artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.playlist_play, size: 28),
                  onPressed: () {
                    ref.read(queueProvider.notifier).insertNext(song);
                  },
                  tooltip: "Play Next",
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add, size: 28),
                  onPressed: () {
                    ref.read(queueProvider.notifier).addListToQueue([song]);
                  },
                  tooltip: "Add to Queue",
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}

class AlbumTile extends ConsumerWidget {
  final Map<String, dynamic> album;
  const AlbumTile({Key? key, required this.album}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    final albumId = album['id'];
    final albumTitle = album['name'] ?? album['title'] ?? 'Unknown Album';
    
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SongsTab(albumId: albumId, albumTitle: albumTitle),
        ));
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: api.getCoverUrl(albumId),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.album, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      albumTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary, size: 28),
                    onPressed: () async {
                      final songs = await api.getAlbum(albumId);
                      ref.read(queueProvider.notifier).addListToQueue(songs);
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.remove, color: Theme.of(context).colorScheme.error, size: 28),
                    onPressed: () async {
                      final songs = await api.getAlbum(albumId);
                      ref.read(queueProvider.notifier).removeSongIds(songs.map((s) => s.id).toList());
                    },
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

class ArtistTile extends ConsumerWidget {
  final Map<String, dynamic> artist;
  const ArtistTile({Key? key, required this.artist}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    final artistId = artist['id'];
    final artistName = artist['name'] ?? 'Unknown Artist';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _AlbumsTab(artistId: artistId),
        ));
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: api.getCoverUrl(artistId),
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    child: Center(
                      child: Text(
                        artistName.isNotEmpty ? artistName.substring(0, 1).toUpperCase() : '?',
                        style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      artistName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary, size: 28),
                    onPressed: () async {
                       final albums = await api.getArtist(artistId);
                       List<Song> allSongs = [];
                       for (final a in albums) {
                         final songs = await api.getAlbum(a['id']);
                         allSongs.addAll(songs);
                       }
                       ref.read(queueProvider.notifier).addListToQueue(allSongs);
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.remove, color: Theme.of(context).colorScheme.error, size: 28),
                    onPressed: () async {
                       final albums = await api.getArtist(artistId);
                       List<String> allSongIds = [];
                       for (final a in albums) {
                         final songs = await api.getAlbum(a['id']);
                         allSongIds.addAll(songs.map((s) => s.id));
                       }
                       ref.read(queueProvider.notifier).removeSongIds(allSongIds);
                    },
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
