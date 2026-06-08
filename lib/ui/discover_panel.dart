import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/navidrome_client.dart';
import '../models/song.dart';
import '../providers/audio_provider.dart';
import 'widgets/bubbly_widgets.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/translation_provider.dart';
import '../theme/theme_provider.dart';
import 'widgets/playlist_collage_icon.dart';

class DiscoverSearchQuery extends Notifier<String> {
  @override
  String build() => '';
}

final discoverSearchQueryProvider = NotifierProvider<DiscoverSearchQuery, String>(DiscoverSearchQuery.new);

class SearchFilter extends Notifier<String> {
  @override
  String build() => 'All';
}

final searchFilterProvider = NotifierProvider<SearchFilter, String>(SearchFilter.new);

class DiscoverPanel extends ConsumerStatefulWidget {
  const DiscoverPanel({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoverPanel> createState() => _DiscoverPanelState();
}

class _DiscoverPanelState extends ConsumerState<DiscoverPanel> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _hasUpdate = false;
  final String CURRENT_APP_VERSION = 'v0.0.3';
  String? _latestVersionTag;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  int _parseVersion(String v) {
    final clean = v.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = clean.split('.');
    if (parts.length != 3) return 0;
    try {
      return int.parse(parts[0]) * 10000 + int.parse(parts[1]) * 100 + int.parse(parts[2]);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _checkUpdate() async {
    try {
      final res = await http.get(Uri.parse('https://api.github.com/repos/Eleyon17/M3Player/releases/latest'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final latestVersion = data['tag_name'];
        if (latestVersion != null) {
          final current = _parseVersion(CURRENT_APP_VERSION);
          final latest = _parseVersion(latestVersion);
          
          if (latest > current) {
            final prefs = await SharedPreferences.getInstance();
            final lastReadVersion = prefs.getString('last_read_version');
            if (lastReadVersion != latestVersion) {
              if (mounted) {
                setState(() {
                  _hasUpdate = true;
                  _latestVersionTag = latestVersion;
                });
              }
            }
          } else {
             if (mounted) {
                setState(() {
                  _hasUpdate = false;
                  _latestVersionTag = latestVersion; // Still save it for update button just in case
                });
             }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchChangelog() async {
    if (_latestVersionTag != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_read_version', _latestVersionTag!);
      setState(() => _hasUpdate = false);
    }
    
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
    try {
      final res = await http.get(Uri.parse('https://api.github.com/repos/Eleyon17/M3Player/releases/tags/$CURRENT_APP_VERSION'));
      Navigator.pop(context); // pop loading
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final body = data['body'] ?? 'No changelog available.';
        
        if (mounted) {
          showDialog(
            context: context,
            barrierColor: Colors.black54,
            builder: (context) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                title: Text('Changelog ($CURRENT_APP_VERSION)'),
                content: SingleChildScrollView(child: Text(body)),
                actions: [
                  if (_latestVersionTag != null && _parseVersion(_latestVersionTag!) > _parseVersion(CURRENT_APP_VERSION))
                    FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: Text('Update to $_latestVersionTag'),
                      onPressed: () {
                        launchUrl(Uri.parse('https://github.com/Eleyon17/M3Player/releases/latest'), mode: LaunchMode.externalApplication);
                      },
                    ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
                ],
              ),
            ),
          );
        }
      } else {
        throw Exception();
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load changelog.')));
    }
  }

  void _promptLogout() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out of M3Player?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              },
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showTranslationsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
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
                    ref.read(translationLanguageProvider.notifier).setLang(val!);
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).setLang('none');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Spanish'),
                leading: Radio<String>(
                  value: 'es',
                  groupValue: ref.watch(translationLanguageProvider),
                  onChanged: (val) {
                    ref.read(translationLanguageProvider.notifier).setLang(val!);
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).setLang('es');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('English'),
                leading: Radio<String>(
                  value: 'en',
                  groupValue: ref.watch(translationLanguageProvider),
                  onChanged: (val) {
                    ref.read(translationLanguageProvider.notifier).setLang(val!);
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  ref.read(translationLanguageProvider.notifier).setLang('en');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Column(
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
                    hintText: "Search...",
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 12.0, right: 8.0),
                      child: Icon(Icons.search),
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(discoverSearchQueryProvider.notifier).state = '';
                              },
                            ),
                          const SizedBox(width: 4),
                          ActionChip(
                            label: Text(ref.watch(searchFilterProvider), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            onPressed: () {
                              final filters = ['All', 'Songs', 'Artists', 'Albums', 'Favorites'];
                              final current = ref.read(searchFilterProvider);
                              final nextIndex = (filters.indexOf(current) + 1) % filters.length;
                              ref.read(searchFilterProvider.notifier).state = filters[nextIndex];
                            },
                          ),
                        ],
                      ),
                    ),
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
                icon: Badge(
                  isLabelVisible: _hasUpdate,
                  child: const Icon(Icons.settings),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                offset: const Offset(0, 48),
                onSelected: (value) {
                  if (value == 'translations') {
                    _showTranslationsDialog(context, ref);
                  } else if (value == 'theme') {
                    ref.read(themeProvider.notifier).toggleTheme();
                  } else if (value == 'changelog') {
                    _fetchChangelog();
                  } else if (value == 'logout') {
                    _promptLogout();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'translations',
                    child: Row(children: [Icon(Icons.translate), SizedBox(width: 12), Text('Translations')]),
                  ),
                  PopupMenuItem<String>(
                    value: 'theme',
                    child: Row(children: [
                      Icon(ref.watch(themeProvider.notifier).isDarkMode ? Icons.light_mode : Icons.dark_mode), 
                      const SizedBox(width: 12), 
                      const Text('Theme')
                    ]),
                  ),
                  PopupMenuItem<String>(
                    value: 'changelog',
                    child: Row(children: [
                      Badge(isLabelVisible: _hasUpdate, child: const Icon(Icons.history)), 
                      const SizedBox(width: 12), 
                      const Text('Changelog')
                    ]),
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
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    splashBorderRadius: BorderRadius.circular(100),
                    dividerColor: Colors.transparent,
                    labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: "Home"),
                      Tab(text: "Playlists"),
                      Tab(text: "Favorites"),
                    ],
                  ),
                ),
                 Expanded(
                  child: TabBarView(
                    children: [
                      _NestedNav(initialRoute: const _HomeTab()),
                      _NestedNav(initialRoute: const _PlaylistsTab()),
                      _NestedNav(initialRoute: const _FavoritesTab()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ],
      ),
      ),
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
    final searchFilter = ref.watch(searchFilterProvider);
    
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
            if (artists.isNotEmpty && (searchFilter == 'All' || searchFilter == 'Artists')) ...[
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
            if (albums.isNotEmpty && (searchFilter == 'All' || searchFilter == 'Albums')) ...[
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
            if (songs.isNotEmpty && (searchFilter == 'All' || searchFilter == 'Songs')) ...[
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


class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab();

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  late Future<List<Song>> _rediscoverFuture;
  late Future<List<Song>> _favoriteArtistsFuture;

  @override
  void initState() {
    super.initState();
    final api = ref.read(navidromeClientProvider);
    _rediscoverFuture = api.getRediscoverSongs(count: 30);
    _favoriteArtistsFuture = api.getTopSongsFromFavoriteArtists();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    if (searchQuery.isNotEmpty) {
      return _SearchResultsTab(query: searchQuery);
    }

    final api = ref.watch(navidromeClientProvider);
    return CustomScrollView(
      slivers: [
        // Category 1: From Artists you like
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text("From Artists you like", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 140, // Compact Song Tiles
            child: FutureBuilder<List<Song>>(
              future: _favoriteArtistsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final songs = snapshot.data!;
                if (songs.isEmpty) return const Center(child: Text("Favorite some artists first!"));
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: songs.length,
                  itemBuilder: (context, index) => SizedBox(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SongTile(song: songs[index], showActions: false),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        // Category 2: Highlights of the Day
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text("Highlights of the Day", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 240,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: api.getRandomArtists(5),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final artists = snapshot.data!;
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: artists.length,
                  itemBuilder: (context, index) => SizedBox(
                    width: 160,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: ArtistTile(artist: artists[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Category 3: Rediscover
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text("Rediscover", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        FutureBuilder<List<Song>>(
          future: _rediscoverFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
            }
            final songs = snapshot.data!;
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => SongTile(song: songs[index]),
                childCount: songs.length,
              ),
            );
          },
        ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 100)), // Bottom padding
      ],
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
        
        if (songs.isEmpty) return const Center(child: Text("No favorites yet."));
        
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) => SongTile(song: songs[index]),
        );
      },
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(navidromePlaylistsProvider);
    final api = ref.watch(navidromeClientProvider);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(context: context, builder: (context) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('New Playlist'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Playlist Name'),
                autofocus: true,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(onPressed: () async {
                  if (controller.text.trim().isNotEmpty) {
                    await api.createPlaylist(controller.text.trim());
                    ref.invalidate(navidromePlaylistsProvider);
                  }
                  if (context.mounted) Navigator.pop(context);
                }, child: const Text('Create')),
              ],
            );
          });
        },
        icon: const Icon(Icons.add),
        label: const Text('New Playlist'),
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: $err")),
        data: (playlists) {
          if (playlists.isEmpty) return const Center(child: Text("No playlists yet."));
          
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final p = playlists[index];
              return ListTile(
                leading: PlaylistCollageIcon(playlistId: p['id']),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(p['name'] ?? 'Playlist', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                subtitle: Text('${p['songCount'] ?? 0} tracks'),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _PlaylistSongsTab(playlistId: p['id'], playlistName: p['name'] ?? 'Playlist'),
                  ));
                },
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 28),
                  tooltip: 'Add entire playlist',
                  onPressed: () async {
                    final songs = await api.getPlaylistSongs(p['id']);
                    ref.read(queueProvider.notifier).addListToQueue(songs);
                  },
                ),
                onLongPress: () {
                  showDialog(context: context, builder: (context) => AlertDialog(
                    title: const Text('Delete Playlist?'),
                    content: Text('Are you sure you want to delete "${p['name']}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(onPressed: () async {
                        await api.deletePlaylist(p['id']);
                        ref.invalidate(navidromePlaylistsProvider);
                        if (context.mounted) Navigator.pop(context);
                      }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistSongsTab extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;

  const _PlaylistSongsTab({required this.playlistId, required this.playlistName});
  
  @override
  _PlaylistSongsTabState createState() => _PlaylistSongsTabState();
}

class _PlaylistSongsTabState extends ConsumerState<_PlaylistSongsTab> {
  late Future<List<Song>> _songsFuture;
  bool _isEditMode = false;
  final Set<int> _selectedIndexesToRemove = {};

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }
  
  void _loadSongs() {
    _songsFuture = ref.read(navidromeClientProvider).getPlaylistSongs(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.playlistName),
        backgroundColor: Colors.transparent,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: _isEditMode
            ? [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Confirm Delete',
                  onPressed: () async {
                    if (_selectedIndexesToRemove.isNotEmpty) {
                      final api = ref.read(navidromeClientProvider);
                      // API accepts 0-based indices to remove
                      await api.updatePlaylist(widget.playlistId, songIndexesToRemove: _selectedIndexesToRemove.toList());
                      setState(() { 
                        _isEditMode = false;
                        _selectedIndexesToRemove.clear();
                        _loadSongs(); 
                      });
                      ref.invalidate(navidromePlaylistsProvider);
                    } else {
                      setState(() { _isEditMode = false; });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Cancel',
                  onPressed: () {
                    setState(() {
                      _isEditMode = false;
                      _selectedIndexesToRemove.clear();
                    });
                  },
                ),
              ]
            : [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isEditMode = true;
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete Songs',
                ),
              ],
      ),
      body: FutureBuilder<List<Song>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final songs = snapshot.data!;
          return ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) => SongTile(
              song: songs[index],
              playlistId: widget.playlistId,
              playlistSongIndex: index,
              isEditMode: _isEditMode,
              isSelected: _selectedIndexesToRemove.contains(index),
              onSelectionChanged: (selected) {
                setState(() {
                  if (selected == true) {
                    _selectedIndexesToRemove.add(index);
                  } else {
                    _selectedIndexesToRemove.remove(index);
                  }
                });
              },
              onPlaylistRemoved: () {
                setState(() { _loadSongs(); });
                ref.invalidate(navidromePlaylistsProvider); // update count
              },
            ),
          );
        },
      ),
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
  final bool showActions;
  final String? playlistId;
  final int? playlistSongIndex;
  final VoidCallback? onPlaylistRemoved;
  final bool isEditMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;

  const SongTile({
    Key? key, 
    required this.song, 
    this.showActions = true,
    this.playlistId,
    this.playlistSongIndex,
    this.onPlaylistRemoved,
    this.isEditMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(navidromeClientProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        onTap: () {
          if (isEditMode) {
            onSelectionChanged?.call(!isSelected);
          } else {
            ref.read(queueProvider.notifier).playInstantly(song);
          }
        },
        onLongPress: () async {
          if (isEditMode) return;
          final playlists = await api.getPlaylists();
          if (!context.mounted) return;
          if (playlists.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Navidrome playlists found! Create one first.')));
            return;
          }
          
          if (playlistId != null && playlistSongIndex != null) {
            // In a playlist, give option to remove or add to another
            showDialog(context: context, builder: (context) {
              return AlertDialog(
                title: const Text('Playlist Options'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      title: const Text('Remove from this playlist', style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        await api.updatePlaylist(playlistId!, songIndexesToRemove: [playlistSongIndex!]);
                        onPlaylistRemoved?.call();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Playlist')));
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.playlist_add),
                      title: const Text('Add to another playlist...'),
                      onTap: () {
                        Navigator.pop(context);
                        _showAddToPlaylistDialog(context, api, playlists, song, ref);
                      },
                    ),
                  ],
                ),
              );
            });
          } else {
            // Not in a playlist, just show add to playlist dialog
            _showAddToPlaylistDialog(context, api, playlists, song, ref);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
            if (isEditMode)
              Checkbox(
                value: isSelected,
                onChanged: onSelectionChanged,
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
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
                if (showActions && !isEditMode) ...[
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
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _showAddToPlaylistDialog(BuildContext context, NavidromeClient api, List<dynamic> playlists, Song song, WidgetRef ref) {
  showDialog(context: context, builder: (context) {
    return AlertDialog(
      title: const Text('Add to Playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final p = playlists[index];
            return ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(p['name'] ?? 'Playlist'),
              onTap: () async {
                await api.updatePlaylist(p['id'], songIdsToAdd: [song.id]);
                ref.invalidate(navidromePlaylistsProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${p['name']}')));
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  });
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
                    imageUrl: api.getCoverUrl(albumId, size: 300),
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
                  imageUrl: api.getCoverUrl(artistId, size: 300),
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
