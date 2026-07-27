import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/theme_provider.dart';
import 'features/audax/providers/audax_events_cache_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/auth_gate.dart';
import 'features/events/providers/checklists_cache_provider.dart';
import 'features/events/providers/events_cache_provider.dart';
import 'features/rides/providers/control_points_provider.dart';
import 'features/rides/providers/offline_rides_provider.dart';
import 'features/rides/providers/rides_provider.dart';
import 'features/rides/providers/sections_cache_provider.dart';
import 'features/weather/providers/weather_cache_provider.dart';

void main() {
  runApp(const CylanApp());
}

/// The web app's accent blue (#2f6df6), shared across map route, buttons,
/// and charts so the mobile app matches the site.
const _seedColor = Color(0xFF2F6DF6);

class CylanApp extends StatelessWidget {
  const CylanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        // restore() pulls previously fetched forecasts off disk so the rides
        // list shows its weather badges immediately after a cold start.
        ChangeNotifierProvider(create: (_) => WeatherCacheProvider()..restore()),
        ChangeNotifierProvider(create: (_) => SectionsCacheProvider()),
        ChangeNotifierProvider(create: (_) => OfflineRidesProvider()),
        // The rider's own control points, read off disk per ride on demand.
        // App-level so the ride detail, its map and live tracking all render
        // the same set without each reloading it.
        ChangeNotifierProvider(create: (_) => ControlPointsProvider()),
        // App-level (not screen-scoped) so a ride copied in from an event's
        // route can refresh the Rides tab, and the list survives tab switches.
        // Kept fresh per login: RidesListScreen reloads it on mount, and the
        // shell (hence that screen) is rebuilt on each sign-in.
        ChangeNotifierProvider(create: (_) => RidesProvider()),
        ChangeNotifierProvider(create: (_) => AudaxEventsCacheProvider()),
        ChangeNotifierProvider(create: (_) => EventsCacheProvider()),
        ChangeNotifierProvider(create: (_) => ChecklistsCacheProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Cylan',
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: themeProvider.mode,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
