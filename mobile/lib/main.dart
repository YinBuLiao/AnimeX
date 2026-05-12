import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/app/theme.dart';

void main() {
  runApp(const ProviderScope(child: AnimeXApp()));
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
