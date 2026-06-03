import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'api/navidrome_client.dart';
import 'providers/audio_provider.dart';
import 'theme/theme_provider.dart';
import 'ui/login_screen.dart';
import 'ui/home_screen.dart';

import 'dart:io';
import 'dart:ui';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  JustAudioMediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('nd_url');
  final savedUser = prefs.getString('nd_user');
  final savedPass = prefs.getString('nd_pass');

  runApp(ProviderScope(
    overrides: [
      navidromeClientProvider.overrideWith((ref) {
        final client = NavidromeClient();
        if (savedUrl != null && savedUser != null && savedPass != null) {
          client.configure(savedUrl, savedUser, savedPass);
        }
        return client;
      }),
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
