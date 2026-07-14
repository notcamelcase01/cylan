import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/ride_profile.dart';
import '../../../core/models/ride_section.dart';
import '../../../core/models/weather_point.dart';
import '../../../core/widgets/elevation_chart.dart';
import '../../../core/widgets/route_map.dart';

/// Zoomed-in view of a single notable climb/descent. Reuses [RouteMap] and
/// [ElevationChart] scoped to just this section: the map shows the section's
/// slice of the route (with the weather bubbles that fall on it), and the chart
/// shows only the section's elevation/gradient.
///
/// It takes the ride's full [profile] and slices it with the section's
/// `start_index`/`end_index` (which index into the same array), so the chart
/// keeps real elevation/gradient — the section's own `coordinates` alone would
/// only give the map line. Works identically online and offline; [showBasemap]
/// is `false` offline, where OSM tiles aren't available.
class SectionDetailScreen extends StatefulWidget {
  final RideSection section;
  final RideProfile profile;
  final List<WeatherPoint> weather;
  final bool showBasemap;

  const SectionDetailScreen({
    super.key,
    required this.section,
    required this.profile,
    this.weather = const [],
    this.showBasemap = true,
  });

  @override
  State<SectionDetailScreen> createState() => _SectionDetailScreenState();
}

class _SectionDetailScreenState extends State<SectionDetailScreen> {
  ProfileChartMode _chartMode = ProfileChartMode.gradient;
  int? _highlightIndex;

  /// The full profile sliced to this section (inclusive indices), guarded
  /// against an index that runs past the array (e.g. a profile re-smoothed to
  /// fewer points after the sections were computed).
  RideProfile get _sectionProfile {
    final p = widget.profile;
    final len = p.latitude.length;
    final start = widget.section.startIndex.clamp(0, len == 0 ? 0 : len - 1);
    final end = widget.section.endIndex.clamp(start, len == 0 ? 0 : len - 1);
    List<double> sub(List<double> l) =>
        l.isEmpty ? l : l.sublist(start, math.min(end + 1, l.length));
    return RideProfile(
      distanceKm: sub(p.distanceKm),
      elevationM: sub(p.elevationM),
      gradientPct: sub(p.gradientPct),
      latitude: sub(p.latitude),
      longitude: sub(p.longitude),
    );
  }

  /// Weather bubbles that fall on this section (by distance along the route).
  /// If none land inside the section's span — likely on a short section, since
  /// forecasts are spaced ~30 min apart — the single nearest point is used so
  /// the rider still sees the conditions for this patch.
  List<WeatherPoint> get _sectionWeather {
    final all = widget.weather;
    if (all.isEmpty) return const [];
    final s = widget.section;
    final within = [
      for (final w in all)
        if (w.distanceKm >= s.startKm && w.distanceKm <= s.endKm) w,
    ];
    if (within.isNotEmpty) return within;
    final mid = (s.startKm + s.endKm) / 2;
    final nearest = all.reduce((a, b) =>
        (a.distanceKm - mid).abs() <= (b.distanceKm - mid).abs() ? a : b);
    return [nearest];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final profile = _sectionProfile;
    final hasTrack = profile.latitude.isNotEmpty;
    final weather = _sectionWeather;
    // The whole ride, drawn faintly behind the section so the rider can see
    // where it sits and which way the route runs.
    final fullRoute = [
      for (var i = 0; i < widget.profile.latitude.length; i++)
        LatLng(widget.profile.latitude[i], widget.profile.longitude[i]),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(section.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(child: Text(section.label)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hasTrack)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 260,
                child: RouteMap(
                  profile: profile,
                  contextRoute: fullRoute,
                  // All the ride's bubbles, so the whole forecast shows along
                  // the context route — most sit outside the zoomed-in section
                  // view, which is fine; the caution callout below stays scoped
                  // to this section.
                  weatherPoints: widget.weather,
                  showBasemap: widget.showBasemap,
                  highlightLocation: _highlightIndex == null
                      ? null
                      : LatLng(
                          profile.latitude[_highlightIndex!],
                          profile.longitude[_highlightIndex!],
                        ),
                ),
              ),
            ),
          if (weather.isNotEmpty) ...[
            const SizedBox(height: 12),
            _WeatherWarning(points: weather, isDescent: !section.isClimb),
          ],
          const SizedBox(height: 16),
          _SectionStats(section: section),
          if (hasTrack) ...[
            const SizedBox(height: 14),
            Center(
              child: SegmentedButton<ProfileChartMode>(
                segments: const [
                  ButtonSegment(
                    value: ProfileChartMode.elevation,
                    label: Text('Elevation'),
                    icon: Icon(Icons.terrain),
                  ),
                  ButtonSegment(
                    value: ProfileChartMode.gradient,
                    label: Text('Gradient'),
                    icon: Icon(Icons.show_chart),
                  ),
                ],
                selected: {_chartMode},
                onSelectionChanged: (s) => setState(() => _chartMode = s.first),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ElevationChart(
                profile: profile,
                mode: _chartMode,
                onIndexSelected: (i) => setState(() => _highlightIndex = i),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'This section is highlighted from the full route. '
            'Distances above are measured along the whole ride.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Callout combining the section's steepness with the forecast on it — e.g. a
/// steep descent in the rain, where the rider should take extra care.
class _WeatherWarning extends StatelessWidget {
  final List<WeatherPoint> points;
  final bool isDescent;
  const _WeatherWarning({required this.points, required this.isDescent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Wettest point on the section drives the message.
    final wettest = points.reduce((a, b) =>
        (a.precipitationMm ?? 0) >= (b.precipitationMm ?? 0) ? a : b);
    final rain = (wettest.precipitationMm ?? 0) > 0;
    final caution = rain && isDescent;

    final scheme = theme.colorScheme;
    final Color bg = caution
        ? scheme.errorContainer.withValues(alpha: 0.6)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final Color fg =
        caution ? scheme.onErrorContainer : scheme.onSurfaceVariant;

    final String message;
    if (caution) {
      message = 'Rain on a descent — surfaces may be slick. Brake early and '
          'take it easy.';
    } else if (rain) {
      message = 'Rain expected along this section.';
    } else {
      message = 'Conditions along this section.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wettest.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${wettest.condition} · '
                  '${wettest.temperatureC?.toStringAsFixed(0) ?? '–'}°C · '
                  'wind ${wettest.windKmh?.toStringAsFixed(0) ?? '–'} km/h '
                  '${wettest.windDirection} · '
                  '${wettest.precipitationMm?.toStringAsFixed(1) ?? '0'} mm',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The section's numbers: length, elevation change, average and max gradient,
/// plus sharp-turn count for technical descents.
class _SectionStats extends StatelessWidget {
  final RideSection section;
  const _SectionStats({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final climb = section.isClimb;
    final stats = <(IconData, String, String)>[
      (Icons.straighten, 'Length', '${section.distanceKm.toStringAsFixed(1)} km'),
      (
        climb ? Icons.trending_up : Icons.trending_down,
        climb ? 'Ascent' : 'Descent',
        '${section.elevationChangeM.abs().toStringAsFixed(0)} m',
      ),
      (Icons.show_chart, 'Avg grade', '${section.avgGradientPct.toStringAsFixed(1)}%'),
      (Icons.terrain, 'Max grade', '${section.maxGradientPct.toStringAsFixed(1)}%'),
      if (!climb && section.sharpTurns > 0)
        (Icons.turn_right, 'Sharp turns', '${section.sharpTurns}'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runSpacing: 14,
        children: [
          for (final (icon, label, value) in stats)
            SizedBox(
              width: 84,
              child: Column(
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(height: 4),
                  Text(value,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
