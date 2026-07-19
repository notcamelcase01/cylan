import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../providers/liked_rides_provider.dart';
import 'ride_detail_screen.dart';

/// The Liked Rides tab: every ride the signed-in rider has liked, whether or
/// not they own it. Opens each one read-only — a liked ride you don't own
/// would 404 on the owner-only smoothing control otherwise, same reasoning as
/// previewing another rider's route from an event.
class LikedRidesScreen extends StatefulWidget {
  const LikedRidesScreen({super.key});

  @override
  State<LikedRidesScreen> createState() => _LikedRidesScreenState();
}

class _LikedRidesScreenState extends State<LikedRidesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<LikedRidesProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LikedRidesProvider>().loadFirst();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LikedRidesProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Liked Rides')),
      body: _content(context, provider),
    );
  }

  Widget _content(BuildContext context, LikedRidesProvider provider) {
    if (provider.isLoading && provider.rides.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(provider.error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: provider.loadFirst,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (provider.rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.favorite_border,
                  size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No liked rides yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Rides you like show up here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: provider.rides.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= provider.rides.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _LikedRideTile(ride: provider.rides[index]);
        },
      ),
    );
  }
}

class _LikedRideTile extends StatelessWidget {
  final Ride ride;
  const _LikedRideTile({required this.ride});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RideDetailScreen(rideId: ride.id, readOnly: true),
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
                child: Icon(Icons.directions_bike,
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        _MetaChip(
                          icon: Icons.straighten,
                          label: '${ride.distanceKm.toStringAsFixed(1)} km',
                        ),
                        if (ride.recordedAt != null)
                          _MetaChip(
                            icon: Icons.event_outlined,
                            label: DateFormat.yMMMd().format(ride.recordedAt!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.favorite, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text('${ride.likesCount}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color)),
      ],
    );
  }
}
