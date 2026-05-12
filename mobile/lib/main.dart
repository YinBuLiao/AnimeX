import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/app/theme.dart';
import 'package:animex_mobile/core/download/download_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final downloads = await DownloadManager.create();
  runApp(ProviderScope(
    overrides: [
      downloadManagerProvider.overrideWithValue(downloads),
    ],
    child: const AnimeXApp(),
  ));
}

class AnimeXApp extends ConsumerWidget {
  const AnimeXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'AnimeX',
      theme: animexDarkTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
