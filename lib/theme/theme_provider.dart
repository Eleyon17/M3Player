import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/navidrome_client.dart';
import '../models/song.dart';
import '../providers/audio_provider.dart';

final themeProvider = NotifierProvider<ThemeNotifier, ThemeData>(ThemeNotifier.new);

class ThemeNotifier extends Notifier<ThemeData> {
  bool isDarkMode = true;

  @override
  ThemeData build() {
    _initTheme();
    _listenToCurrentSong();
    return _buildTheme(null);
  }

  Future<void> _initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('isDarkMode')) {
      isDarkMode = prefs.getBool('isDarkMode') ?? true;
      final currentSong = ref.read(queueProvider).currentSong;
      if (currentSong != null) {
        _updatePalette(currentSong);
      } else {
        state = _buildTheme(null);
      }
    }
  }

  Future<void> toggleTheme() async {
    isDarkMode = !isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
    final currentSong = ref.read(queueProvider).currentSong;
    if (currentSong != null) {
      _updatePalette(currentSong);
    } else {
      state = _buildTheme(null);
    }
  }

  ThemeData _buildTheme(ColorScheme? customScheme) {
    final scheme = customScheme ?? ColorScheme.fromSeed(
      seedColor: const Color(0xFF8C6DB4),
      brightness: isDarkMode ? Brightness.dark : Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent, // Allow blur to bleed
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      textTheme: GoogleFonts.nunitoTextTheme(
        ThemeData(brightness: isDarkMode ? Brightness.dark : Brightness.light).textTheme,
      ),
    );
  }

  void _listenToCurrentSong() {
    ref.listen<Song?>(
      queueProvider.select((state) => state.currentSong),
      (previous, current) {
        if (current != null && current.id != previous?.id) {
          _updatePalette(current);
        }
      },
    );
  }

  Future<void> _updatePalette(Song song) async {
    final api = ref.read(navidromeClientProvider);
    final url = api.getCoverUrl(song.coverArt ?? song.albumId ?? song.id, size: 300);
    
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final palette = await PaletteGenerator.fromImageProvider(imageProvider);
      
      // Get all extracted colors sorted by how prominent they are (population)
      final colors = palette.paletteColors.toList()
        ..sort((a, b) => b.population.compareTo(a.population));
        
      // Take up to the top 3 most prominent colors
      final topColors = colors.take(3).map((p) => p.color).toList();
      
      // Average them out
      Color baseColor = const Color(0xFF8C6DB4);
      if (topColors.isNotEmpty) {
        int r = 0, g = 0, b = 0;
        for (var c in topColors) {
          r += c.red;
          g += c.green;
          b += c.blue;
        }
        baseColor = Color.fromARGB(
          255,
          (r / topColors.length).round(),
          (g / topColors.length).round(),
          (b / topColors.length).round(),
        );
      }
      
      ColorScheme scheme;
      if (isDarkMode) {
        scheme = ColorScheme.fromSeed(
          seedColor: baseColor,
          brightness: Brightness.dark,
        );
      } else {
        scheme = ColorScheme.fromSeed(
          seedColor: baseColor,
          brightness: Brightness.light,
        );
      }
      
      state = _buildTheme(scheme);
    } catch (e) {
      print("Palette extraction failed: $e");
      // Fallback if image loading fails
      state = _buildTheme(null);
    }
  }
}
