import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../providers/rides_provider.dart';
import '../providers/suggested_rides_provider.dart';
import '../widgets/suggestion_status_chip.dart';
import 'ride_detail_screen.dart';

/// The Public Rides tab: the rider's own rides opted into the
/// curated-suggestion pool (pending staff review, or already approved and
/// public), with a way to remove any of them from the pool. Its
/// [SuggestedRidesProvider] is app-level (see `main.dart`), same rationale as
/// [RidesProvider] — survives tab switches, and a suggest made from the Rides
/// tab or a revert made here needs a stable instance the other side can reach.
class PublicRidesScreen extends StatefulWidget {
  const PublicRidesScreen({super.key});

  @override
  State<PublicRidesScreen> createState() => _PublicRidesScreenState();
}

class _PublicRidesScreenState extends State<PublicRidesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<SuggestedRidesProvider>().loadMore();
      }
    });
    // Post-frame for the same reason as RidesListScreen: loadFirst notifies
    // synchronously, which can't happen during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuggestedRidesProvider>().loadFirst();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _confirmRemove(Ride ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from public suggestions?'),
        content: Text(
            '"${ride.name}" will no longer be suggested to other riders'
            '${ride.isSuggestionApproved ? ' and will go back to private' : ''}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _removeFromSuggestions(Ride ride) async {
    if (!await _confirmRemove(ride)) return;
    if (!mounted) return;

    final ok = await context.read<SuggestedRidesProvider>().unsuggest(ride.id);
    if (!mounted) return;
    if (ok) {
      // Keep the Rides tab's cached copy (if loaded) in sync so its chip and
      // "Make ride public" option come back without a manual pull.
      context.read<RidesProvider>().patchSuggestionStatus(ride.id, 'NONE');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${ride.name}" was removed from public suggestions.')),
      );
    } else {
      final error = context.read<SuggestedRidesProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? "Couldn't remove that ride.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuggestedRidesProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Public Rides')),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, SuggestedRidesProvider provider) {
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
            FilledButton(onPressed: provider.loadFirst, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (provider.rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.public_outlined,
                    size: 40, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text('No public suggestions yet',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Use ⋮ on a ride in Rides and choose "Make ride public" to '
                'suggest it to nearby event creators.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: provider.rides.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= provider.rides.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final ride = provider.rides[index];
          final theme = Theme.of(context);
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RideDetailScreen(rideId: ride.id)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SuggestionStatusChip(status: ride.publicSuggestionStatus),
                              Text('${ride.distanceKm.toStringAsFixed(1)} km',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant)),
                              if (ride.recordedAt != null)
                                Text(DateFormat.yMMMd().format(ride.recordedAt!),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'remove') _removeFromSuggestions(ride);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from public suggestions'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
