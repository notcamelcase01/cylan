import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/control_point.dart';
import '../../rides/providers/control_points_provider.dart';

/// The organiser's control points for an event, and the button that copies
/// them into the rider's own list.
///
/// The list is always readable, imported or not — an organiser marking
/// "caution, bad junction" needs that to reach people who never press the
/// button. Importing only decides whether the rider gets their **own editable
/// copies** on the route.
///
/// Nothing is ever imported automatically. A route can be attached to any
/// number of events, so anything automatic would have to guess which event's
/// list the rider meant; two events sharing a route would then overwrite each
/// other every time the rider moved between them. Asking removes the guess.
class EventControlPointsCard extends StatefulWidget {
  final int eventId;
  final int rideId;
  final List<ControlPoint> points;

  const EventControlPointsCard({
    super.key,
    required this.eventId,
    required this.rideId,
    required this.points,
  });

  @override
  State<EventControlPointsCard> createState() => _EventControlPointsCardState();
}

class _EventControlPointsCardState extends State<EventControlPointsCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Tells us whether this event has already been imported into that ride.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ControlPointsProvider>().load(widget.rideId);
      }
    });
  }

  /// Copies the organiser's points in. Needs the ride's elevation profile to
  /// work out how far along the route each one sits, and the event payload's
  /// embedded ride doesn't carry it — so the ride is fetched here, on demand,
  /// rather than on every event open.
  Future<void> _import() async {
    final provider = context.read<ControlPointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ride = await ApiClient.instance.getRide(widget.rideId);
      final profile = ride.profile;
      if (profile == null || !profile.hasTrack) {
        messenger.showSnackBar(const SnackBar(
          content: Text("This route has no GPS track, so its control points "
              "can't be placed."),
        ));
        return;
      }
      await provider.importFromEvent(
        widget.rideId,
        eventId: widget.eventId,
        points: widget.points,
        profile: profile,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Added ${widget.points.length} control '
          '${widget.points.length == 1 ? "point" : "points"} to this route',
        ),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't add the control points. Please try again."),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final provider = context.read<ControlPointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove this event's control points?"),
        content: const Text(
          "They'll be taken off this route, including any you've since renamed "
          'or moved. Control points you added yourself, and any from other '
          'events, are left alone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.removeEventPoints(widget.rideId, widget.eventId);
    messenger.showSnackBar(
      const SnackBar(content: Text("Removed this event's control points")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imported = context
        .watch<ControlPointsProvider>()
        .hasImported(widget.rideId, widget.eventId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.push_pin_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text("Organiser's control points",
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              imported
                  ? "These are on your copy of the route. They're yours now — "
                        'edit or delete them from the route screen; changes the '
                        "organiser makes later won't follow."
                  : 'Add these to your own control points for this route. Once '
                        'added they become yours to edit or delete, and nothing '
                        'is shared back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final point in widget.points)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: point.type.color,
                  child: Icon(point.type.icon, size: 14, color: Colors.white),
                ),
                title: Text(point.label),
                subtitle: Text(
                  point.type.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : imported
                      ? TextButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text("Remove from my route"),
                          onPressed: _remove,
                        )
                      : FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add to my control points'),
                          onPressed: _import,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
