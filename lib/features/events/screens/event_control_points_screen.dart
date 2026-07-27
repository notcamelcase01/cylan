import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/control_point.dart';
import '../../../core/models/ride_profile.dart';
import '../../../core/widgets/route_map.dart';
import '../../rides/screens/control_point_picker_screen.dart';
import '../../rides/widgets/control_point_editor_sheet.dart';

/// Where an event's organiser places the control points every subscriber
/// starts with — water stops, checkpoints, junctions to warn about.
///
/// Editing here is entirely local to the screen; the finished list is popped
/// back to the event form and saved with the rest of the event, so backing out
/// changes nothing. That keeps a half-finished set from reaching subscribers,
/// and means this screen needs no save endpoint of its own.
///
/// Deliberately reuses the rider-facing [ControlPointPickerScreen] and
/// [ControlPointEditorSheet] — an organiser places a point exactly the way a
/// rider does, so there is no second implementation to keep in step.
class EventControlPointsScreen extends StatefulWidget {
  /// The event's attached ride. Its profile is fetched here: the event form
  /// only knows the ride's id, and points can't be placed without the route.
  final int rideId;
  final List<ControlPoint> initial;

  const EventControlPointsScreen({
    super.key,
    required this.rideId,
    this.initial = const [],
  });

  @override
  State<EventControlPointsScreen> createState() =>
      _EventControlPointsScreenState();
}

class _EventControlPointsScreenState extends State<EventControlPointsScreen> {
  late List<ControlPoint> _points = [...widget.initial];
  RideProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ride = await ApiClient.instance.getRide(widget.rideId);
      final profile = ride.profile;
      if (!mounted) return;
      setState(() {
        _profile = profile != null && profile.hasTrack ? profile : null;
        _error = _profile == null ? 'This route has no GPS track to place points on.' : null;
        _loading = false;
      });
      _placeExisting();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = "Couldn't load the route. Please try again.";
          _loading = false;
        });
      }
    }
  }

  /// Points loaded from the event arrive with no distance along the route —
  /// the API stores only coordinates. Fill that in now the profile is here, so
  /// the list can order and label them.
  void _placeExisting() {
    final profile = _profile;
    if (profile == null || _points.isEmpty) return;
    setState(() {
      _points = _sorted([
        for (final p in _points)
          p.copyWith(distanceKm: profile.nearestDistanceKm(p.position)),
      ]);
    });
  }

  static List<ControlPoint> _sorted(List<ControlPoint> points) =>
      points..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

  Future<void> _addByMap() async {
    final profile = _profile;
    if (profile == null) return;
    final picked = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ControlPointPickerScreen(profile: profile, existing: _points),
      ),
    );
    if (picked == null || !mounted) return;
    final point = await ControlPointEditorSheet.show(
      context,
      profile: profile,
      fixedPosition: picked,
    );
    if (point == null || !mounted) return;
    setState(() => _points = _sorted([..._points, point]));
  }

  Future<void> _addByDistance() async {
    final profile = _profile;
    if (profile == null) return;
    final point = await ControlPointEditorSheet.show(context, profile: profile);
    if (point == null || !mounted) return;
    setState(() => _points = _sorted([..._points, point]));
  }

  Future<void> _edit(ControlPoint point) async {
    final profile = _profile;
    if (profile == null) return;
    final edited = await ControlPointEditorSheet.show(
      context,
      profile: profile,
      initial: point,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _points = _sorted([
        for (final p in _points) if (p.id == edited.id) edited else p,
      ]);
    });
  }

  void _delete(ControlPoint point) {
    setState(() => _points = [for (final p in _points) if (p.id != point.id) p]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control points'),
        actions: [
          TextButton(
            // Popping the list is what "saves" it — into the event form, which
            // sends it with everything else.
            onPressed: () => Navigator.pop(context, _points),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (profile == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? 'Something went wrong.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadRoute,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              SizedBox(
                height: 220,
                child: RouteMap(
                  profile: profile,
                  controlPoints: _points,
                  onControlPointTap: _edit,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Everyone who opens this event gets these points. Riders can '
                  'then add their own or remove yours on their own device — '
                  "that never changes what's here.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: _points.isEmpty
                    ? Center(
                        child: Text(
                          'No control points yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final point in _points)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: point.type.color,
                                child: Icon(point.type.icon,
                                    size: 16, color: Colors.white),
                              ),
                              title: Text(point.label),
                              subtitle: Text(
                                '${point.type.label} · '
                                '${point.distanceKm.toStringAsFixed(1)} km',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => _edit(point),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove',
                                onPressed: () => _delete(point),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      // In the Scaffold's bottom slot rather than at the end of the body, so a
      // snackbar is laid out *above* these buttons instead of on top of them —
      // the "Removed … / Undo" bar was covering them for its whole duration.
      bottomNavigationBar: _loading || profile == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.straighten, size: 18),
                        label: const Text('By distance'),
                        onPressed: _addByDistance,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('On the map'),
                        onPressed: _addByMap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
