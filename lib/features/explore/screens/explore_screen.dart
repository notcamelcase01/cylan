import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../../events/screens/create_edit_event_screen.dart';
import '../../rides/screens/ride_detail_screen.dart';
import '../providers/explore_provider.dart';
import 'location_picker_screen.dart';

/// "Create event from this ride": no copy, no network call — just hands the
/// ride's id + a display label straight to event creation. The ride isn't the
/// caller's own, but a curated suggestion is always both PUBLIC and approved,
/// which is exactly what `EventWriteSerializer.validate_ride` requires to
/// attach it directly on save (see `CreateEditEventScreen.initialRide`).
class _CreateEventButton extends StatelessWidget {
  final int rideId;
  final String label;
  const _CreateEventButton({required this.rideId, required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateEditEventScreen(
              initialRide: (id: rideId, label: label),
            ),
          ),
        ),
        icon: const Icon(Icons.event_outlined, size: 18),
        label: const Text('Create event from this ride'),
      ),
    );
  }
}

/// The Explore tab: staff-approved curated rides, browsable as a flat list
/// or searched near a place the rider picks on a map. Every ride here is
/// `PUBLIC` by construction (curated/approved rides are always public), so
/// liking works exactly as it does from the ride's own detail screen — no
/// special-casing needed, `RideDetailScreen` already only hides the
/// owner-only smoothing control behind `readOnly`, never the like button.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<ExploreProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ExploreProvider>().loadFirstNearby();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    final place = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (place != null && mounted) {
      context.read<ExploreProvider>().searchNear(place);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExploreProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Pick a place',
            onPressed: _pickPlace,
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.locationFailed && !provider.isFiltered)
            _LocationFallbackBanner(provider: provider),
          if (provider.isFiltered) _FilterHeader(provider: provider),
          Expanded(
            child: _RideList(
              provider: provider,
              scrollController: _scrollController,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the list while filtered to a picked place or city — names
/// the filter and offers a way back to the unfiltered list.
class _FilterHeader extends StatelessWidget {
  final ExploreProvider provider;
  const _FilterHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final place = provider.pickedPlace;
    final city = provider.pickedCity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              place != null
                  ? 'Near ${place.latitude.toStringAsFixed(4)}, '
                      '${place.longitude.toStringAsFixed(4)}'
                  : 'Near $city',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => context.read<ExploreProvider>().clearPlace(),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Shown above the browse list when [ExploreProvider.loadFirstNearby]
/// couldn't get a location fix — explains why the list is unfiltered and
/// offers the same city search [RouteSuggestionsPanel] falls back to.
class _LocationFallbackBanner extends StatefulWidget {
  final ExploreProvider provider;
  const _LocationFallbackBanner({required this.provider});

  @override
  State<_LocationFallbackBanner> createState() =>
      _LocationFallbackBannerState();
}

class _LocationFallbackBannerState extends State<_LocationFallbackBanner> {
  bool _showCityPicker = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't get your location — showing all rides.",
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_showCityPicker)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _showCityPicker = true);
                  provider.loadCities();
                },
                icon: const Icon(Icons.location_city, size: 18),
                label: const Text('Search by city instead'),
              ),
            )
          else if (provider.citiesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (provider.cities.isEmpty)
            Text('No cities with curated routes yet.',
                style: theme.textTheme.bodySmall)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'City'),
              items: [
                for (final c in provider.cities)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (city) {
                if (city != null) provider.searchNearCity(city);
              },
            ),
        ],
      ),
    );
  }
}

class _RideList extends StatelessWidget {
  final ExploreProvider provider;
  final ScrollController scrollController;
  const _RideList({required this.provider, required this.scrollController});

  @override
  Widget build(BuildContext context) {
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
              child: Icon(Icons.explore_outlined,
                  size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
                provider.isFiltered
                    ? 'No approved rides here yet'
                    : 'No approved rides yet',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        controller: scrollController,
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
          return _ApprovedRideTile(ride: provider.rides[index]);
        },
      ),
    );
  }
}

class _ApprovedRideTile extends StatefulWidget {
  final Ride ride;
  const _ApprovedRideTile({required this.ride});

  @override
  State<_ApprovedRideTile> createState() => _ApprovedRideTileState();
}

class _ApprovedRideTileState extends State<_ApprovedRideTile> {
  bool _expanded = false;

  /// Whether [text] would actually be clipped at 2 lines in the available
  /// width — so the "Show more" toggle only appears when there's something to
  /// expand, rather than on every ride that happens to have a description.
  bool _overflowsTwoLines(String text, TextStyle? style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final theme = Theme.of(context);
    final descriptionStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RideDetailScreen(rideId: ride.id, readOnly: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(ride.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Icon(Icons.favorite, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('${ride.likesCount}', style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 4),
              _MetaChip(
                icon: Icons.straighten,
                label: '${ride.distanceKm.toStringAsFixed(1)} km',
              ),
              if (ride.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final overflows = !_expanded &&
                        _overflowsTwoLines(
                          ride.description,
                          descriptionStyle,
                          constraints.maxWidth,
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.description,
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: descriptionStyle,
                        ),
                        if (overflows || _expanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _expanded ? 'Show less' : 'Show more',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Icon(
                                    _expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              _CreateEventButton(
                rideId: ride.id,
                label: '${ride.name} · ${ride.distanceKm.toStringAsFixed(1)} km',
              ),
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
