import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final url = api.getCoverUrl(song.coverArt ?? song.id, size: 300);
    
    try {
      final imageProvider = NetworkImage(url);
      
      final ColorScheme scheme = await ColorScheme.fromImageProvider(
        provider: imageProvider,
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
      );
      
      state = _buildTheme(scheme);
    } catch (e) {
      // Fallback if image loading fails
      state = _buildTheme(null);
    }
  }
}
