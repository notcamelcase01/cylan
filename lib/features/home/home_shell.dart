import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../events/screens/events_screen.dart';
import '../explore/providers/explore_provider.dart';
import '../explore/screens/explore_screen.dart';
import '../rides/providers/liked_rides_provider.dart';
import '../rides/screens/liked_rides_screen.dart';
import '../rides/screens/rides_list_screen.dart';

/// The signed-in root: a four-tab bottom-nav wrapper around the existing
/// [RidesListScreen] and [EventsScreen], plus [LikedRidesScreen] and
/// [ExploreScreen]. Each tab renders its own `Scaffold` (app bar, FAB, …);
/// this shell only adds the bottom bar around them, so neither tab's own
/// behaviour changes.
///
/// The tabs live in an [IndexedStack] rather than being swapped out, so each
/// keeps its scroll position and provider state when the rider switches away
/// and back. [LikedRidesProvider]/[ExploreProvider] are created once here
/// (not app-level like [RidesProvider]) but this shell holds a direct
/// reference to each so it can force a refresh every time its tab is
/// (re)selected — `IndexedStack` never rebuilds an inactive tab, so without
/// this a ride liked (or newly approved) elsewhere wouldn't show up here
/// until the tab happened to reload some other way (e.g. an app restart).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _likedRidesProvider = LikedRidesProvider();
  final _exploreProvider = ExploreProvider();
  late final _tabs = [
    const RidesListScreen(),
    const EventsScreen(),
    ChangeNotifierProvider.value(
      value: _likedRidesProvider,
      child: const LikedRidesScreen(),
    ),
    ChangeNotifierProvider.value(
      value: _exploreProvider,
      child: const ExploreScreen(),
    ),
  ];

  @override
  void dispose() {
    _likedRidesProvider.dispose();
    _exploreProvider.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    if (index == 2) _likedRidesProvider.refresh();
    if (index == 3) _exploreProvider.refreshIfBrowsing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
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
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Liked',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
        ],
      ),
    );
  }
}
