import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../../../core/widgets/route_map.dart';
import '../providers/live_tracking_provider.dart';

/// Below this speed, GPS heading is too noisy to be worth showing (it can
/// swing wildly while stopped or barely moving), so the live marker falls
/// back to a plain dot. ~1.8 km/h — comfortably below walking pace.
const double _headingSpeedThresholdMps = 0.5;

class LiveTrackingScreen extends StatelessWidget {
  final Ride ride;

  /// When false, the live map is drawn without a tile basemap (route line only)
  /// — used for offline rides, so live GPS tracking works with no connection.
  final bool showBasemap;

  const LiveTrackingScreen({
    super.key,
    required this.ride,
    this.showBasemap = true,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LiveTrackingProvider(ride)..start(),
      child: _LiveTrackingView(showBasemap: showBasemap),
    );
  }
}

class _LiveTrackingView extends StatelessWidget {
  final bool showBasemap;

  const _LiveTrackingView({this.showBasemap = true});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LiveTrackingProvider>();
    final ride = provider.ride;

    return Scaffold(
      appBar: AppBar(title: Text('Live: ${ride.name}')),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, LiveTrackingProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.permissionMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 56),
              const SizedBox(height: 12),
              Text(provider.permissionMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Geolocator.openLocationSettings(),
                    child: const Text('Location settings'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: const Text('App settings'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.read<LiveTrackingProvider>().start(),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (provider.error != null) {
      return Center(child: Text(provider.error!));
    }

    final profile = provider.ride.profile!;
    final pos = provider.position;
    final liveLocation =
        pos == null ? null : LatLng(pos.latitude, pos.longitude);
    // GPS heading is noise below walking speed, so only show the arrow once
    // actually moving; otherwise the marker falls back to a plain dot.
    final liveHeading =
        pos != null && pos.speed > _headingSpeedThresholdMps
            ? pos.heading
            : null;
    return Column(
      children: [
        Expanded(
          child: RouteMap(
            profile: profile,
            liveLocation: liveLocation,
            liveHeading: liveHeading,
            showBasemap: showBasemap,
          ),
        ),
        _InfoPanel(provider: provider),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final LiveTrackingProvider provider;
  const _InfoPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offRoute = (provider.offRouteMeters ?? 0) > 60;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sits above the route rather than replacing it: the map is still
            // worth reading while the receiver searches, and this usually
            // clears itself.
            if (provider.gpsMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.location_searching,
                        color: theme.colorScheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(provider.gpsMessage!,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            if (offRoute)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.error, size: 18),
                    const SizedBox(width: 6),
                    Text('${provider.offRouteMeters!.toStringAsFixed(0)} m off route',
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            Text(
              '${(provider.traveledDistanceKm ?? 0).toStringAsFixed(1)} / '
              '${provider.ride.distanceKm.toStringAsFixed(1)} km',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
