import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../../../core/models/weather_point.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/elevation_chart.dart';
import '../../../core/widgets/route_map.dart';
import '../../tracking/screens/live_tracking_screen.dart';
import '../services/offline_ride_store.dart';
import 'ride_detail_screen.dart';

/// Read-only detail for a route saved offline. Everything renders from disk
/// with no network: a fixed (zoom/pan-locked) overview map with the saved
/// weather bubbles, stats, the elevation/gradient chart, the frozen weather
/// forecast, and a Live button (GPS-only, so it works offline).
class OfflineRideDetailScreen extends StatefulWidget {
  final OfflineRide offlineRide;

  const OfflineRideDetailScreen({super.key, required this.offlineRide});

  @override
  State<OfflineRideDetailScreen> createState() =>
      _OfflineRideDetailScreenState();
}

class _OfflineRideDetailScreenState extends State<OfflineRideDetailScreen> {
  ProfileChartMode _chartMode = ProfileChartMode.elevation;
  int? _highlightIndex;

  Ride get _ride => widget.offlineRide.ride;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConnectivityService()..start(),
      child: Builder(builder: _buildScaffold),
    );
  }

  void _switchToLive(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RideDetailScreen(rideId: _ride.id),
    ));
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final offlineRide = widget.offlineRide;
    final ride = _ride;
    final profile = ride.profile;
    final hasTrack = profile != null && profile.latitude.isNotEmpty;
    final weather = offlineRide.weather;
    final online = context.watch<ConnectivityService>().online;

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.name),
        actions: [_ConnectivityDot(online: online)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (online) ...[
            _LiveAvailableBanner(onSwitch: () => _switchToLive(context)),
            const SizedBox(height: 10),
          ],
          _OfflineBanner(savedAt: offlineRide.savedAt),
          const SizedBox(height: 14),
          if (hasTrack)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 240,
                child: RouteMap(
                  profile: profile,
                  weatherPoints: weather,
                  showBasemap: false,
                  highlightLocation: _highlightIndex == null
                      ? null
                      : LatLng(
                          profile.latitude[_highlightIndex!],
                          profile.longitude[_highlightIndex!],
                        ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _StatsRow(ride: ride),
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Live'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LiveTrackingScreen(
                        ride: ride,
                        showBasemap: false,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (weather.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Weather along route',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              'Saved ${DateFormat('MMM d, HH:mm').format(offlineRide.savedAt)} · won\'t update offline',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final p in weather) ...[
              _WeatherRow(point: p),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// Small app-bar dot: green when the server is reachable, grey when not.
class _ConnectivityDot extends StatelessWidget {
  final bool online;
  const _ConnectivityDot({required this.online});

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF2E7D32) : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Tooltip(
        message: online ? 'Internet available' : 'Offline',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(online ? 'Online' : 'Offline',
                style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Actionable banner shown when the server becomes reachable, offering to open
/// the full live view (street map, fresh weather, smoothing).
class _LiveAvailableBanner extends StatelessWidget {
  final VoidCallback onSwitch;
  const _LiveAvailableBanner({required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    return Material(
      color: green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSwitch,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.wifi, size: 20, color: green),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Internet available — switch to the live view for the street '
                  'map, fresh weather and smoothing.',
                  style: TextStyle(color: green, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: green),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notice that this is an offline copy with a fixed map and frozen weather.
class _OfflineBanner extends StatelessWidget {
  final DateTime savedAt;
  const _OfflineBanner({required this.savedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.offline_pin,
              size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline copy. The map shows your route as a line without a '
              'street background, and weather is frozen from when you saved it. '
              'Live GPS tracking still works.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherRow extends StatelessWidget {
  final WeatherPoint point;
  const _WeatherRow({required this.point});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, HH:mm');
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Text(point.icon, style: const TextStyle(fontSize: 28)),
        title: Text(
          '${point.distanceKm.toStringAsFixed(1)} km · ${point.condition}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${dateFmt.format(point.eta)} · '
          '${point.temperatureC?.toStringAsFixed(0) ?? '–'}°C '
          '(feels ${point.feelsLikeC?.toStringAsFixed(0) ?? '–'}°C) · '
          'wind ${point.windKmh?.toStringAsFixed(0) ?? '–'} km/h ${point.windDirection} · '
          '${point.precipitationMm?.toStringAsFixed(1) ?? '0'} mm',
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Ride ride;
  const _StatsRow({required this.ride});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = [
      (Icons.straighten, 'Distance', '${ride.distanceKm.toStringAsFixed(1)} km'),
      (Icons.trending_up, 'Ascent', '${ride.totalAscentM.toStringAsFixed(0)} m'),
      (Icons.trending_down, 'Descent', '${ride.totalDescentM.toStringAsFixed(0)} m'),
      (Icons.terrain, 'Max grade', '${ride.maxGradientPct.toStringAsFixed(1)}%'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (icon, label, value) in stats)
            Column(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(height: 4),
                Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
        ],
      ),
    );
  }
}
