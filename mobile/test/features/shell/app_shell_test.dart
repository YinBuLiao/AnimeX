import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/features/shell/app_shell.dart';

/// Tab that pushes its own counter, used to verify state survives switches.
class _CountingTab extends StatefulWidget {
  final String label;
  const _CountingTab(this.label);
  @override
  State<_CountingTab> createState() => _CountingTabState();
}

class _CountingTabState extends State<_CountingTab> {
  int taps = 0;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.label}-$taps'),
      ),
    );
  }
}

void main() {
  testWidgets('renders all destinations and starts on initialIndex',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        tabs: const [
          Center(child: Text('TAB0')),
          Center(child: Text('TAB1')),
        ],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.explore), label: 'Discover'),
        ],
      ),
    ));
    // Both tabs are in the tree (IndexedStack), but only index 0 is on top.
    expect(find.text('TAB0'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
  });

  testWidgets('tapping a destination switches tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        tabs: const [
          Center(child: Text('TAB0')),
          Center(child: Text('TAB1')),
        ],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.explore), label: 'Discover'),
        ],
      ),
    ));
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    // After tap, the body's IndexedStack should show TAB1's content as
    // visible. The simplest check: locate the IndexedStack and verify index.
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
  });

  testWidgets('tab state survives navigation away and back', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        tabs: const [
          _CountingTab('a'),
          _CountingTab('b'),
        ],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.explore), label: 'Discover'),
        ],
      ),
    ));
    // Tap counter button in tab 0 three times.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('a-$i'));
      await tester.pump();
    }
    expect(find.text('a-3'), findsOneWidget);

    // Switch to tab 1 then back.
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('a-3'), findsOneWidget,
        reason: 'IndexedStack must preserve tab 0 state across switches');
  });
}
