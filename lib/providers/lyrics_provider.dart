import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../api/navidrome_client.dart';
import 'audio_provider.dart';
import 'translation_provider.dart';

class LrcLine {
  final Duration time;
  final String text;
  final String? translatedText;

  LrcLine({required this.time, required this.text, this.translatedText});
}

class LyricsData {
  final List<LrcLine>? syncedLyrics;
  final String? plainLyrics;
  final String? translatedPlainLyrics;

  LyricsData({this.syncedLyrics, this.plainLyrics, this.translatedPlainLyrics});
  
  bool get hasSynced => syncedLyrics != null && syncedLyrics!.isNotEmpty;
}

final lyricsProvider = FutureProvider.family<LyricsData?, Song>((ref, song) async {
  final api = ref.read(navidromeClientProvider);
  
  // 1. Try fetching from LRCLIB for synced lyrics using Search for fuzzy matching
  try {
    final searchQ = '${song.artist ?? ''} ${song.title}'.trim();
    final url = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(searchQ)}');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        final bestSynced = data.firstWhere(
          (item) => (item['syncedLyrics'] as String?)?.isNotEmpty == true,
          orElse: () => null,
        );
        
        if (bestSynced != null) {
          final lrcString = bestSynced['syncedLyrics'] as String;
          final parsed = _parseLrc(lrcString);
          if (parsed.isNotEmpty) {
            return LyricsData(syncedLyrics: parsed);
          } else {
            return LyricsData(plainLyrics: lrcString);
          }
        }
        
        final plainLrc = data.first['plainLyrics'] as String?;
        if (plainLrc != null && plainLrc.isNotEmpty) {
          return LyricsData(plainLyrics: plainLrc);
        }
      }
    }
  } catch (e) {
    print('LRCLIB search failed: $e');
  }

  // 2. Fallback to Navidrome API (usually unsynced)
  try {
    final naviLyrics = await api.getLyrics(song.artist, song.title);
    if (naviLyrics != null && naviLyrics.isNotEmpty) {
      return LyricsData(plainLyrics: naviLyrics);
    }
  } catch (e) {
    print('Navidrome lyrics fetch failed: \$e');
  }

  return null;
});

final translatedLyricsProvider = FutureProvider.family<LyricsData?, Song>((ref, song) async {
  final original = await ref.watch(lyricsProvider(song).future);
  final targetLang = ref.watch(translationLanguageProvider);
  
  final translatorService = ref.read(translationServiceProvider);
  return translatorService.translateLyrics(original, targetLang);
});

List<LrcLine> _parseLrc(String lrc) {
  final lines = lrc.split('\n');
  final result = <LrcLine>[];
  final timeRegExp = RegExp(r'\[(\d+):(\d{2})(?:\.(\d+))?\]');

  for (final line in lines) {
    final match = timeRegExp.firstMatch(line);
    if (match != null) {
      final mins = int.parse(match.group(1)!);
      final secs = int.parse(match.group(2)!);
      final millisRaw = match.group(3) ?? '0';
      
      int millis = 0;
      if (millisRaw.length == 1) millis = int.parse(millisRaw) * 100;
      else if (millisRaw.length == 2) millis = int.parse(millisRaw) * 10;
      else if (millisRaw.length >= 3) millis = int.parse(millisRaw.substring(0, 3));
      
      final text = line.substring(match.end).trim();
      final duration = Duration(minutes: mins, seconds: secs, milliseconds: millis);
      
      result.add(LrcLine(time: duration, text: text));
    }
  }
  return result;
}
