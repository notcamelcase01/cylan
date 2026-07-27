import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/control_point.dart';
import '../../../core/models/ride_profile.dart';
import '../../../core/widgets/route_map.dart';

/// Full-screen map for choosing where a control point goes: tap the route to
/// drop a provisional pin, tap again to move it, then confirm.
///
/// Deliberately its own screen rather than tap-handling on the ride detail's
/// inline map — that map lives inside a scrolling list, where a tap-to-place
/// gesture fights the scroll and the map is too small to place a pin
/// accurately.
///
/// Pops with the chosen [LatLng], or null if the rider backs out.
class ControlPointPickerScreen extends StatefulWidget {
  final RideProfile profile;

  /// Already-placed points, drawn for context so the rider can see what's
  /// there and space a new one sensibly.
  final List<ControlPoint> existing;

  /// False when picking on an offline copy — the route draws as a plain line
  /// with no street tiles, since those can't be cached for offline use.
  final bool showBasemap;

  const ControlPointPickerScreen({
    super.key,
    required this.profile,
    this.existing = const [],
    this.showBasemap = true,
  });

  @override
  State<ControlPointPickerScreen> createState() =>
      _ControlPointPickerScreenState();
}

class _ControlPointPickerScreenState extends State<ControlPointPickerScreen> {
  LatLng? _picked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _picked;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a spot')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              picked == null
                  ? 'Tap the map to place your control point.'
                  : 'At ${widget.profile.nearestDistanceKm(picked).toStringAsFixed(1)} km along the route. '
                        'Tap again to move it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: RouteMap(
              profile: widget.profile,
              showBasemap: widget.showBasemap,
              // The provisional pin rides along as a control point of its own
              // so it draws exactly as the saved one will.
              controlPoints: [
                ...widget.existing,
                if (picked != null)
                  ControlPoint(
                    id: '_pending',
                    label: '',
                    type: ControlPointType.checkpoint,
                    latitude: picked.latitude,
                    longitude: picked.longitude,
                    distanceKm: widget.profile.nearestDistanceKm(picked),
                  ),
              ],
              onMapTapForControlPoint: (p) => setState(() => _picked = p),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: picked == null
                      ? null
                      : () => Navigator.pop(context, picked),
                  child: const Text('Use this spot'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
