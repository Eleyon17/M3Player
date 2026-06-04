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
    final url = api.getCoverUrl(song.coverArt ?? song.id, size: 300);
    
    try {
      final imageProvider = NetworkImage(url);
      final palette = await PaletteGenerator.fromImageProvider(imageProvider);
      
      final baseColor = palette.vibrantColor?.color ?? palette.dominantColor?.color ?? const Color(0xFF8C6DB4);
      final hsl = HSLColor.fromColor(baseColor);
      final h = hsl.hue;
      final s = hsl.saturation;
      
      double clampS(double val) => val.clamp(0.0, 1.0);
      
      final lBg = isDarkMode ? 0.10 : 0.95;
      final lSurface = isDarkMode ? 0.12 : 0.90;
      final lSurfaceVar = isDarkMode ? 0.20 : 0.85;
      final lSurfaceCont = isDarkMode ? 0.25 : 0.80;
      final lPrimary = isDarkMode ? 0.80 : 0.40;
      final lPrimaryCont = isDarkMode ? 0.75 : 0.90;
      final lOnPrimaryCont = isDarkMode ? 0.15 : 0.10;
      final lOnBg = isDarkMode ? 0.90 : 0.10;
      final lOnSurfaceVar = isDarkMode ? 0.80 : 0.20;

      final bg = HSLColor.fromAHSL(1.0, h, clampS(s - 0.10), lBg).toColor();
      final surface = HSLColor.fromAHSL(1.0, h, clampS(s - 0.10), lSurface).toColor();
      final surfaceVariant = HSLColor.fromAHSL(1.0, h, clampS(s - 0.15), lSurfaceVar).toColor();
      final surfaceContainer = HSLColor.fromAHSL(1.0, h, clampS(s - 0.20), lSurfaceCont).toColor();
      
      final primary = HSLColor.fromAHSL(1.0, h, s, lPrimary).toColor();
      final primaryContainer = HSLColor.fromAHSL(1.0, h, clampS(s - 0.10), lPrimaryCont).toColor();
      final onPrimaryContainer = HSLColor.fromAHSL(1.0, h, clampS(s - 0.10), lOnPrimaryCont).toColor();
      
      final onBg = HSLColor.fromAHSL(1.0, h, s, lOnBg).toColor();
      final onSurfaceVariant = HSLColor.fromAHSL(1.0, h, s, lOnSurfaceVar).toColor();

      // We stash the actual dark vibrant/dominant colors in the scheme for the playbar gradient
      final darkVibrant = isDarkMode ? (palette.darkVibrantColor?.color ?? surfaceVariant) : (palette.lightVibrantColor?.color ?? surfaceVariant);

      final scheme = ColorScheme(
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: Colors.black,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: darkVibrant, // Store for gradients!
        onSecondary: Colors.black,
        error: Colors.redAccent,
        onError: Colors.white,
        background: bg,
        onBackground: onBg,
        surface: surface,
        onSurface: onBg,
        surfaceContainerHigh: surfaceContainer,
        surfaceVariant: surfaceVariant,
        onSurfaceVariant: onSurfaceVariant,
      );
      
      state = _buildTheme(scheme);
    } catch (e) {
      // Fallback if image loading fails
      state = _buildTheme(null);
    }
  }
}
