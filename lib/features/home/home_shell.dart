import 'package:flutter/material.dart';

import '../events/screens/events_screen.dart';
import '../rides/screens/public_rides_screen.dart';
import '../rides/screens/rides_list_screen.dart';

/// The signed-in root: a three-tab bottom-nav wrapper around the existing
/// [RidesListScreen], [EventsScreen], and [PublicRidesScreen]. Each tab
/// renders its own `Scaffold` (app bar, FAB, …); this shell only adds the
/// bottom bar around them, so no tab's own behaviour changes.
///
/// The tabs live in an [IndexedStack] rather than being swapped out, so each
/// keeps its scroll position and provider state when the rider switches away
/// and back.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [RidesListScreen(), EventsScreen(), PublicRidesScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_bike_outlined),
            selectedIcon: Icon(Icons.directions_bike),
            label: 'Rides',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Public',
          ),
        ],
      ),
    );
  }
}
