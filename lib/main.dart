import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api/navidrome_client.dart';
import 'providers/audio_provider.dart';
import 'providers/audio_handler.dart';
import 'theme/theme_provider.dart';
import 'ui/login_screen.dart';
import 'ui/home_screen.dart';

import 'dart:io';
import 'dart:ui';
import 'api/proxy_server.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
  
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
late MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }
  
  if (!kIsWeb) {
    await ProxyServer.start();

    HttpOverrides.global = MyHttpOverrides();
    if (Platform.isLinux || Platform.isWindows) {
      JustAudioMediaKit.ensureInitialized();
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('nd_url');
  final savedUser = prefs.getString('nd_user');
  final savedPass = prefs.getString('nd_pass');

  final navidromeClient = NavidromeClient();
  if (savedUrl != null && savedUser != null && savedPass != null) {
    navidromeClient.configure(savedUrl, savedUser, savedPass);
  }

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(AudioPlayer(), navidromeClient),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_music',
    ),
  );




  runApp(ProviderScope(
    overrides: [
      navidromeClientProvider.overrideWith((ref) => navidromeClient),
      audioPlayerProvider.overrideWith((ref) => audioHandler.player),
    ],
    child: MyApp(initialRoute: (savedUrl != null && savedUser != null && savedPass != null) ? '/home' : '/login'),
  ));
}

class MyApp extends ConsumerWidget {
  final String initialRoute;
  const MyApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'M3Player',
      debugShowCheckedModeBanner: false,
      scrollBehavior: NoScrollbarBehavior(),
      theme: theme,
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
