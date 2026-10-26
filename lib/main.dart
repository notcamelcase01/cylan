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

/// A saturated take on the seeded scheme.
///
/// `ColorScheme.fromSeed`'s default (tonalSpot) greys the seed out badly — the
/// blue survives in `primary` and everything else lands on near-neutral tones,
/// so screens read as grey cards on a grey page. So: seed with the `vibrant`
/// variant to keep chroma in the roles we don't name below, then pin the ones
/// that carry the app's look.
///
/// - `primary` stays exactly the web accent, since the map route, charts and
///   buttons are colour-matched to the site.
/// - `secondary` (teal) and `tertiary` (warm amber) are picked as deliberate
///   accents rather than hue rotations of the seed, giving badges, chips and
///   highlights something to be that isn't more blue.
/// - light surfaces are tinted toward the primary's hue rather than neutral
///   grey (a blue-white page); dark ones go the other way, to a flat matte
///   black that lets those accents do the work.
ColorScheme _buildColorScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );

  return switch (brightness) {
    Brightness.light => base.copyWith(
        primary: _seedColor,
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFD8E4FF),
        onPrimaryContainer: const Color(0xFF002B72),
        secondary: const Color(0xFF00737F),
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: const Color(0xFFA9EFF7),
        onSecondaryContainer: const Color(0xFF00363B),
        tertiary: const Color(0xFFB5530C),
        onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: const Color(0xFFFFDCC2),
        onTertiaryContainer: const Color(0xFF3E1A00),
        error: const Color(0xFFC11534),
        onError: const Color(0xFFFFFFFF),
        errorContainer: const Color(0xFFFFDAD9),
        onErrorContainer: const Color(0xFF5C0016),
        surface: const Color(0xFFF6F9FF),
        onSurface: const Color(0xFF131A2B),
        onSurfaceVariant: const Color(0xFF46506A),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF0F4FE),
        surfaceContainer: const Color(0xFFE8EEFC),
        surfaceContainerHigh: const Color(0xFFE0E8F9),
        surfaceContainerHighest: const Color(0xFFD8E1F5),
        outline: const Color(0xFF737E99),
        outlineVariant: const Color(0xFFC3CCE3),
        inverseSurface: const Color(0xFF29314A),
        onInverseSurface: const Color(0xFFEEF1FC),
        inversePrimary: const Color(0xFFAEC6FF),
        surfaceTint: _seedColor,
      ),
    Brightness.dark => base.copyWith(
        primary: const Color(0xFFA6C3FF),
        onPrimary: const Color(0xFF002F73),
        // Brighter than M3 would pick, so filled chips and selected states
        // stay visibly blue against the navy surfaces rather than muddying.
        primaryContainer: const Color(0xFF2A5CD6),
        onPrimaryContainer: const Color(0xFFE6EEFF),
        secondary: const Color(0xFF5FD8E6),
        onSecondary: const Color(0xFF00363B),
        secondaryContainer: const Color(0xFF00727F),
        onSecondaryContainer: const Color(0xFFC9F6FC),
        tertiary: const Color(0xFFFFB784),
        onTertiary: const Color(0xFF4A1F00),
        tertiaryContainer: const Color(0xFFA8480A),
        onTertiaryContainer: const Color(0xFFFFE3CE),
        error: const Color(0xFFFFB4AB),
        onError: const Color(0xFF690009),
        errorContainer: const Color(0xFFA3000F),
        onErrorContainer: const Color(0xFFFFDAD6),
        // Matte black: near-neutral and flat, with only a trace of the blue
        // hue left in so it reads as deliberate rather than dead grey. The
        // accents above stay vivid — the point is bright colour on black.
        surface: const Color(0xFF0A0A0C),
        onSurface: const Color(0xFFE8E8EE),
        onSurfaceVariant: const Color(0xFFAFAFBA),
        surfaceContainerLowest: const Color(0xFF050506),
        surfaceContainerLow: const Color(0xFF111114),
        surfaceContainer: const Color(0xFF16161A),
        surfaceContainerHigh: const Color(0xFF1C1C21),
        surfaceContainerHighest: const Color(0xFF232329),
        outline: const Color(0xFF77777F),
        outlineVariant: const Color(0xFF2B2B32),
        inverseSurface: const Color(0xFFE8E8EE),
        onInverseSurface: const Color(0xFF1A1A1F),
        inversePrimary: _seedColor,
        surfaceTint: const Color(0xFFA6C3FF),
      ),
  };
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = _buildColorScheme(brightness);
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
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
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      // The one place the accent is worth spending on an outline: it marks
      // which field has the keyboard.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.primary,
      selectedColor: colorScheme.primary,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.secondaryContainer,
      checkmarkColor: colorScheme.onSecondaryContainer,
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      indicatorColor: colorScheme.primary,
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      indicatorColor: colorScheme.primaryContainer,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: colorScheme.tertiary,
      textColor: colorScheme.onTertiary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
      circularTrackColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
