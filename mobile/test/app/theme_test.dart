import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/app/theme.dart';

void main() {
  test('animexDarkTheme uses dark brightness and our background color', () {
    final t = animexDarkTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, const Color(0xFF0F1014));
    expect(t.useMaterial3, isTrue);
  });

  test('animexDarkTheme exposes the surfaceContainer card color', () {
    final t = animexDarkTheme();
    expect(t.colorScheme.surfaceContainer, const Color(0xFF1A1B22));
  });
}
