import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/control_point.dart';
import '../../../core/models/ride_profile.dart';
import '../providers/control_points_provider.dart';
import '../screens/control_point_picker_screen.dart';
import 'control_point_editor_sheet.dart';

/// The rider's own control points for a ride, in route order, with the two
/// ways of adding one: picking a spot on the map, or typing a distance along
/// the route.
///
/// Shows on every ride the rider can open — including routes they don't own —
/// because these annotations are personal and local to the device, not part of
/// the ride.
class ControlPointsCard extends StatelessWidget {
  final int rideId;
  final RideProfile profile;

  /// False on an offline copy, where the map picker draws the route without
  /// street tiles. Everything else works unchanged — control points are stored
  /// on the device, so none of this needs a connection.
  final bool showBasemap;

  const ControlPointsCard({
    super.key,
    required this.rideId,
    required this.profile,
    this.showBasemap = true,
  });

  Future<void> _addByMap(BuildContext context) async {
    final provider = context.read<ControlPointsProvider>();
    final picked = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ControlPointPickerScreen(
          profile: profile,
          existing: provider.pointsFor(rideId),
          showBasemap: showBasemap,
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final point = await ControlPointEditorSheet.show(
      context,
      profile: profile,
      fixedPosition: picked,
    );
    if (point != null) await provider.add(rideId, point);
  }

  Future<void> _addByDistance(BuildContext context) async {
    final provider = context.read<ControlPointsProvider>();
    final point = await ControlPointEditorSheet.show(context, profile: profile);
    if (point != null) await provider.add(rideId, point);
  }

  Future<void> _edit(BuildContext context, ControlPoint point) async {
    final provider = context.read<ControlPointsProvider>();
    final edited = await ControlPointEditorSheet.show(
      context,
      profile: profile,
      initial: point,
    );
    if (edited != null) await provider.update(rideId, edited);
  }

  Future<void> _delete(BuildContext context, ControlPoint point) async {
    final provider = context.read<ControlPointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete control point?'),
        content: Text('"${point.label}" will be removed from this route.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.remove(rideId, point.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted "${point.label}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = context.watch<ControlPointsProvider>().pointsFor(rideId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Control points', style: theme.textTheme.titleMedium),
                const Spacer(),
                MenuAnchor(
                  builder: (context, controller, _) => TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.map_outlined),
                      onPressed: () => _addByMap(context),
                      child: const Text('Pick on the map'),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.straighten),
                      onPressed: () => _addByDistance(context),
                      child: const Text('By distance along route'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (points.isEmpty)
              Text(
                'Mark water stops, checkpoints or anything else worth '
                'remembering. Yours only — they stay on this device and are '
                'never shared.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final point in points)
                _ControlPointTile(
                  point: point,
                  // An event's points stay exactly as the organiser published
                  // them: no editing, and no deleting one at a time. They're
                  // removed as a set from the event screen.
                  onEdit: point.isImported ? null : () => _edit(context, point),
                  onDelete:
                      point.isImported ? null : () => _delete(context, point),
                ),
          ],
        ),
      ),
    );
  }
}

class _ControlPointTile extends StatelessWidget {
  final ControlPoint point;

  /// Both null for a point imported from an event — those are the organiser's
  /// and the rider can't change them, so the row offers no way to try.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ControlPointTile({
    required this.point,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: point.type.color,
        child: Icon(point.type.icon, size: 16, color: Colors.white),
      ),
      title: Text(point.label),
      subtitle: Text(
        [
          point.type.label,
          '${point.distanceKm.toStringAsFixed(1)} km',
          // Where it came from, so a rider can tell at a glance which points
          // arrived with an event they joined — and, since those are locked,
          // why this row doesn't behave like the others.
          if (point.isImported) "the organiser's",
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onEdit,
      trailing: onDelete == null
          ? Tooltip(
              message: "Set by the event organiser — remove them from the "
                  'event screen',
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.outline,
              ),
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
    );
  }
}
