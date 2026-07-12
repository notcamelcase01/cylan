import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../models/turn.dart';
import '../providers/live_tracking_provider.dart';
import '../widgets/route_map.dart';

class LiveTrackingScreen extends StatelessWidget {
  final Ride ride;

  const LiveTrackingScreen({super.key, required this.ride});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LiveTrackingProvider(ride)..start(),
      child: const _LiveTrackingView(),
    );
  }
}

IconData _turnIcon(Turn turn) {
  switch (turn.direction) {
    case 'left':
      return Icons.turn_left;
    case 'right':
      return Icons.turn_right;
    default:
      return Icons.navigation;
  }
}

String _formatDistance(double km) {
  final m = km * 1000;
  return m < 950 ? '${(m / 10).round() * 10} m' : '${km.toStringAsFixed(1)} km';
}

class _LiveTrackingView extends StatelessWidget {
  const _LiveTrackingView();

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
    final liveLocation = provider.position == null
        ? null
        : LatLng(provider.position!.latitude, provider.position!.longitude);
    final nextTurnLocation = provider.nextTurn == null
        ? null
        : provider.locationForTurn(provider.nextTurn!);

    return Column(
      children: [
        Expanded(
          child: RouteMap(
            profile: profile,
            liveLocation: liveLocation,
            nextTurn: nextTurnLocation,
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
            Row(
              children: [
                if (provider.nextTurn != null) ...[
                  Icon(_turnIcon(provider.nextTurn!), size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.distanceToNextTurnKm == null
                              ? provider.nextTurn!.label
                              : '${_formatDistance(provider.distanceToNextTurnKm!)} · ${provider.nextTurn!.label}',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text('next turn', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ] else
                  const Expanded(
                      child: Text("No more turns — you're near the finish")),
                Text(
                  '${(provider.traveledDistanceKm ?? 0).toStringAsFixed(1)} / '
                  '${provider.ride.distanceKm.toStringAsFixed(1)} km',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            // Cue list — the next few upcoming turns.
            if (provider.upcomingTurns.length > 1) ...[
              const Divider(height: 20),
              for (final turn in provider.upcomingTurns.skip(1))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(_turnIcon(turn), size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(turn.label)),
                      if (provider.traveledDistanceKm != null)
                        Text(
                          'in ${_formatDistance(turn.distanceKm - provider.traveledDistanceKm!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
