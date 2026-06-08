import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
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
    final url = api.getCoverUrl(song.albumId ?? song.id, size: 300);
    
    try {
      final imageProvider = NetworkImage(url);
      final palette = await PaletteGenerator.fromImageProvider(imageProvider);
      
      // Check for race condition: did the user skip to another song while we were downloading?
      final currentSong = ref.read(queueProvider).currentSong;
      if (currentSong == null || currentSong.id != song.id) {
        return;
      }

      // Priority: dominantColor over vibrantColor to match ColorThief behavior
      final baseColor = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? const Color(0xFF8C6DB4);
      final hsl = HSLColor.fromColor(baseColor);
      final h = hsl.hue;
      final s = hsl.saturation;
      
      ColorScheme scheme;
      
      if (isDarkMode) {
        scheme = const ColorScheme.dark().copyWith(
          surface: HSLColor.fromAHSL(1.0, h, (s - 0.1).clamp(0.0, 1.0), 0.12).toColor(),
          surfaceContainerHighest: HSLColor.fromAHSL(1.0, h, (s - 0.15).clamp(0.0, 1.0), 0.20).toColor(),
          secondaryContainer: HSLColor.fromAHSL(1.0, h, (s - 0.2).clamp(0.0, 1.0), 0.25).toColor(),
          primary: HSLColor.fromAHSL(1.0, h, s, 0.80).toColor(),
          primaryContainer: HSLColor.fromAHSL(1.0, h, (s - 0.1).clamp(0.0, 1.0), 0.75).toColor(),
          onPrimaryContainer: HSLColor.fromAHSL(1.0, h, (s - 0.1).clamp(0.0, 1.0), 0.15).toColor(),
          onSurface: HSLColor.fromAHSL(1.0, h, s, 0.90).toColor(),
          onSurfaceVariant: HSLColor.fromAHSL(1.0, h, s, 0.80).toColor(),
          onSecondaryContainer: HSLColor.fromAHSL(1.0, h, s, 0.85).toColor(),
        );
      } else {
        scheme = const ColorScheme.light().copyWith(
          primary: HSLColor.fromAHSL(1.0, h, s, 0.25).toColor(),
          surface: HSLColor.fromAHSL(1.0, h, (s - 0.2).clamp(0.0, 1.0), 0.98).toColor(),
          surfaceContainerHighest: HSLColor.fromAHSL(1.0, h, s, 0.86).toColor(),
          secondaryContainer: HSLColor.fromAHSL(1.0, h, s, 0.80).toColor(),
          primaryContainer: HSLColor.fromAHSL(1.0, h, s, 0.80).toColor(),
          onPrimaryContainer: HSLColor.fromAHSL(1.0, h, s, 0.15).toColor(),
          onSurface: HSLColor.fromAHSL(1.0, h, s, 0.10).toColor(),
          onSurfaceVariant: HSLColor.fromAHSL(1.0, h, s, 0.25).toColor(),
          onSecondaryContainer: HSLColor.fromAHSL(1.0, h, s, 0.20).toColor(),
        );
      }
      
      state = _buildTheme(scheme);
    } catch (e) {
      // Fallback if image loading fails
      state = _buildTheme(null);
    }
  }
}
