import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../providers/ride_detail_provider.dart';
import '../providers/weather_cache_provider.dart';
import '../services/share_image_service.dart';
import '../widgets/elevation_chart.dart';
import '../widgets/route_map.dart';
import 'live_tracking_screen.dart';
import 'weather_screen.dart';

class RideDetailScreen extends StatelessWidget {
  final int rideId;

  const RideDetailScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RideDetailProvider()..load(rideId),
      child: const _RideDetailView(),
    );
  }
}

class _RideDetailView extends StatefulWidget {
  const _RideDetailView();

  @override
  State<_RideDetailView> createState() => _RideDetailViewState();
}

class _RideDetailViewState extends State<_RideDetailView> {
  final _shareKey = GlobalKey();
  bool _sharing = false;
  ProfileChartMode _chartMode = ProfileChartMode.elevation;
  int? _highlightIndex;
  double? _pendingSmoothingWindow;

  Future<void> _applySmoothing(double windowM) async {
    setState(() => _pendingSmoothingWindow = windowM);
    await context.read<RideDetailProvider>().applySmoothing(windowM.round());
    if (mounted) setState(() => _pendingSmoothingWindow = null);
  }

  Future<void> _shareImage(Ride ride) async {
    setState(() => _sharing = true);
    try {
      await ShareImageService()
          .shareRepaintBoundary(_shareKey, fileName: ride.name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create the image')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RideDetailProvider>();
    final ride = provider.ride;

    return Scaffold(
      appBar: AppBar(
        title: Text(ride?.name ?? 'Ride'),
        actions: [
          if (ride != null)
            IconButton(
              icon: _sharing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              tooltip: 'Share image',
              onPressed: _sharing ? null : () => _shareImage(ride),
            ),
        ],
      ),
      body: Builder(builder: (context) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.error != null || ride == null) {
          return Center(child: Text(provider.error ?? 'Ride not found'));
        }
        return _buildContent(context, ride);
      }),
    );
  }

  Widget _buildContent(BuildContext context, Ride ride) {
    final profile = ride.profile;
    final hasTrack = profile != null && profile.latitude.isNotEmpty;
    // Weather is cached app-wide once fetched on the weather screen, so it
    // shows here (and in the share snapshot) even after navigating back.
    final weatherPoints =
        context.watch<WeatherCacheProvider>().pointsFor(ride.id) ?? const [];

    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Shareable summary: map + stats + current chart + branding.
        RepaintBoundary(
          key: _shareKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ride.name,
                      style:
                          theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (ride.recordedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(DateFormat.yMMMd().format(ride.recordedAt!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 14),
                  if (profile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 240,
                        child: RouteMap(
                          profile: profile,
                          weatherPoints: weatherPoints,
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
                  ],
                  _StatsRow(ride: ride),
                  if (hasTrack) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 150,
                      child: ElevationChart(
                        profile: profile,
                        mode: _chartMode,
                        onIndexSelected: (i) =>
                            setState(() => _highlightIndex = i),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Cylan · cyclingngin.duckdns.org',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
          _SmoothingControl(
            windowM: _pendingSmoothingWindow ?? ride.smoothingWindowM,
            busy: context.watch<RideDetailProvider>().isApplyingSmoothing,
            onChanged: (v) => setState(() => _pendingSmoothingWindow = v),
            onChangeEnd: _applySmoothing,
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Weather'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WeatherScreen(ride: ride),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Live'),
                onPressed: !hasTrack
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LiveTrackingScreen(ride: ride),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lets the rider trade off noise vs. detail in the elevation/gradient
/// profile — mirrors the web app's per-ride smoothing control
/// (`POST /rides/{id}/smoothing/`, 50-500 m window).
class _SmoothingControl extends StatelessWidget {
  final double windowM;
  final bool busy;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SmoothingControl({
    required this.windowM,
    required this.busy,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Text('Smoothing', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                height: 12,
                width: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const Spacer(),
            Text('${windowM.round()} m', style: theme.textTheme.bodySmall),
          ],
        ),
        Slider(
          value: windowM.clamp(50, 500),
          min: 50,
          max: 500,
          divisions: 45,
          label: '${windowM.round()} m',
          onChanged: busy ? null : onChanged,
          onChangeEnd: busy ? null : onChangeEnd,
        ),
      ],
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
