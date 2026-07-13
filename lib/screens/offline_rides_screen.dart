import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/offline_rides_provider.dart';
import '../services/offline_ride_store.dart';
import 'offline_ride_detail_screen.dart';

/// Lists routes saved for offline use. Reachable from the My Rides app bar so
/// it's still available when there's no connection and the online list can't
/// load.
class OfflineRidesScreen extends StatefulWidget {
  const OfflineRidesScreen({super.key});

  @override
  State<OfflineRidesScreen> createState() => _OfflineRidesScreenState();
}

class _OfflineRidesScreenState extends State<OfflineRidesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OfflineRidesProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineRidesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Offline rides')),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, OfflineRidesProvider provider) {
    if (provider.isLoading && provider.rides.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.download_for_offline_outlined,
                    size: 40, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text('No offline rides yet',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Open a ride and tap the download icon to save it here for use '
                'with no connection.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: provider.rides.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) return const _LimitationBanner();
        final offlineRide = provider.rides[index - 1];
        return _OfflineRideCard(offlineRide: offlineRide);
      },
    );
  }
}

class _LimitationBanner extends StatelessWidget {
  const _LimitationBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline routes show your route as a line without a street '
              'background, and weather frozen from when you saved them. Live GPS '
              'tracking still works; street maps, smoothing and fresh weather '
              'need a connection.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineRideCard extends StatelessWidget {
  final OfflineRide offlineRide;
  const _OfflineRideCard({required this.offlineRide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ride = offlineRide.ride;
    final weather = offlineRide.weather.isEmpty ? null : offlineRide.weather.first;

    return Dismissible(
      key: ValueKey(ride.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ride.name),
      onDismissed: (_) =>
          context.read<OfflineRidesProvider>().delete(ride.id),
      background: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  OfflineRideDetailScreen(offlineRide: offlineRide),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.offline_pin,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ride.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '${ride.distanceKm.toStringAsFixed(1)} km · saved '
                        '${DateFormat.yMMMd().format(offlineRide.savedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (weather != null) ...[
                  Text(weather.icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 2),
                  Text(
                    weather.temperatureC == null
                        ? '–'
                        : '${weather.temperatureC!.round()}°',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove offline copy?'),
        content: Text('"$name" will no longer be available offline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
