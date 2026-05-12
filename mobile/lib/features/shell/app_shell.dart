import 'package:flutter/material.dart';

/// Bottom-tab shell. Children stay alive across tab switches (IndexedStack).
class AppShell extends StatefulWidget {
  final List<Widget> tabs;
  final List<NavigationDestination> destinations;
  final int initialIndex;

  const AppShell({
    super.key,
    required this.tabs,
    required this.destinations,
    this.initialIndex = 0,
  })  : assert(tabs.length == destinations.length,
            'tabs and destinations must be parallel'),
        assert(tabs.length >= 2);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.tabs.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: widget.tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: widget.destinations,
      ),
    );
  }
}
