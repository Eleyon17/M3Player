import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/lyrics_provider.dart';

class TranslationLanguageNotifier extends Notifier<String> {
  @override
  String build() => 'none';
}

final translationLanguageProvider = NotifierProvider<TranslationLanguageNotifier, String>(TranslationLanguageNotifier.new);

class TranslationService {
  Future<String?> _translateRaw(String text, String targetLang) async {
    try {
      final url = Uri.parse('https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> json = jsonDecode(response.body);
        
        // json[2] contains the detected source language.
        final detectedLang = json.length > 2 ? json[2] as String? : null;
        if (detectedLang != null && detectedLang.toLowerCase() == targetLang.toLowerCase()) {
          return null; // Source language matches target language, skip translation
        }

        final List<dynamic> translations = json[0];
        StringBuffer sb = StringBuffer();
        for (var part in translations) {
          sb.write(part[0]);
        }
        return sb.toString();
      }
    } catch (e) {
      print('HTTP Translation failed: $e');
    }
    return null;
  }

  Future<LyricsData?> translateLyrics(LyricsData? original, String targetLang) async {
    if (original == null || targetLang == 'none') return original;

    try {
      if (original.hasSynced) {
        final lines = original.syncedLyrics!;
        final fullText = lines.map((l) => l.text).join('\n');
        
        final translatedFull = await _translateRaw(fullText, targetLang);
        if (translatedFull == null) return original;
        
        final translatedLines = translatedFull.split('\n');
        
        final newLines = <LrcLine>[];
        for (int i = 0; i < lines.length; i++) {
          final text = lines[i].text;
          final tText = i < translatedLines.length ? translatedLines[i] : null;
          newLines.add(LrcLine(
            time: lines[i].time,
            text: text,
            translatedText: tText,
          ));
        }
        return LyricsData(syncedLyrics: newLines, plainLyrics: original.plainLyrics);
      } else if (original.plainLyrics != null) {
        final translatedText = await _translateRaw(original.plainLyrics!, targetLang);
        if (translatedText != null) {
          return LyricsData(plainLyrics: original.plainLyrics, translatedPlainLyrics: translatedText);
        }
      }
    } catch (e) {
      print('Translation formatting failed: $e');
    }
    
    return original;
  }
}

final translationServiceProvider = Provider((ref) => TranslationService());
