import 'package:flutter/foundation.dart';

import '../../../core/models/control_point.dart';
import '../../../core/models/ride_profile.dart';
import '../services/control_point_store.dart';

/// App-level store of every ride's personal control points, keyed by ride id.
///
/// Registered above the navigator (see `main.dart`) so points loaded on the
/// ride detail survive navigating into live tracking and back, and so the map
/// and the list always read the same set.
///
/// Every mutation writes straight through to disk — control points are the
/// rider's own work and exist nowhere else, so there's no "save" step to
/// forget and nothing to lose if the app is killed.
class ControlPointsProvider extends ChangeNotifier {
  final ControlPointStore _store = ControlPointStore();

  final Map<int, ControlPointSet> _sets = {};
  final Set<int> _loading = {};

  /// The ride's points in route order, or an empty list when the ride hasn't
  /// been loaded yet — callers render nothing rather than special-casing null.
  List<ControlPoint> pointsFor(int rideId) =>
      _sets[rideId]?.points ?? const [];

  bool hasLoaded(int rideId) => _sets.containsKey(rideId);

  /// Reads the ride's saved points from disk. A no-op once loaded (or while a
  /// load is in flight), so it's safe to call every time a screen opens.
  Future<void> load(int rideId) async {
    if (hasLoaded(rideId) || _loading.contains(rideId)) return;
    _loading.add(rideId);
    try {
      _sets[rideId] = await _store.load(rideId);
      notifyListeners();
    } finally {
      _loading.remove(rideId);
    }
  }

  /// Whether the rider has already imported [eventId]'s points into this ride.
  bool hasImported(int rideId, int eventId) =>
      _sets[rideId]?.importedEventIds.contains(eventId) ?? false;

  /// Copies an event's published points into the rider's own set.
  ///
  /// This is the *only* way an organiser's points reach a rider's list —
  /// nothing is ever seeded automatically. That's deliberate: a ride can be
  /// attached to any number of events, so anything automatic would have to
  /// guess which event's list the rider meant, and two events sharing a route
  /// would overwrite each other's points every time the rider switched
  /// between them.
  ///
  /// Each copy gets a fresh local id (organiser ids are only unique within
  /// their own event, so two imports could otherwise collide) and is placed
  /// along [profile]. Afterwards the copies are ordinary points of the
  /// rider's: editable, deletable, and untouched by anything the organiser
  /// does later.
  Future<void> importFromEvent(
    int rideId, {
    required int eventId,
    required List<ControlPoint> points,
    required RideProfile profile,
  }) async {
    await load(rideId);
    final current = _sets[rideId] ?? const ControlPointSet();
    if (current.importedEventIds.contains(eventId)) return;

    await _write(
      rideId,
      current.copyWith(
        points: _sorted([
          ...current.points,
          for (final p in points) p.importedInto(profile, eventId: eventId),
        ]),
        importedEventIds: {...current.importedEventIds, eventId},
      ),
    );
  }

  /// Removes every point that came from [eventId], and re-arms its import.
  ///
  /// Scoped to the one event on purpose: a rider subscribed to two events on
  /// the same route can drop one organiser's points without disturbing the
  /// other's, or their own.
  ///
  /// Points imported from that event are deleted outright, including any the
  /// rider went on to rename or move — once imported they're just their
  /// points, and there's nothing left that distinguishes an edited copy from
  /// a fresh one.
  Future<void> removeEventPoints(int rideId, int eventId) async {
    final current = _sets[rideId] ?? const ControlPointSet();
    await _write(
      rideId,
      current.copyWith(
        points: [
          for (final p in current.points)
            if (p.sourceEventId != eventId) p,
        ],
        importedEventIds: {...current.importedEventIds}..remove(eventId),
      ),
    );
  }

  Future<void> add(int rideId, ControlPoint point) async {
    final current = _sets[rideId] ?? const ControlPointSet();
    await _write(rideId, current.copyWith(
      points: _sorted([...current.points, point]),
    ));
  }

  /// Replaces the point with the same id, keeping route order in case the edit
  /// moved it.
  ///
  /// Points imported from an event are **not** editable and are silently left
  /// alone — they stay exactly as the organiser published them, so a rider can
  /// always trust that a point marked as an event's really is what the
  /// organiser set. The rider's recourse is to remove that event's points as a
  /// group and place their own.
  Future<void> update(int rideId, ControlPoint point) async {
    final current = _sets[rideId] ?? const ControlPointSet();
    await _write(rideId, current.copyWith(
      points: _sorted([
        for (final p in current.points)
          if (p.id == point.id && !p.isImported) point else p,
      ]),
    ));
  }

  /// Removes one of the rider's own points.
  ///
  /// Imported points are left alone, the same as in [update]: an event's set is
  /// the organiser's and is only ever removed whole, via [removeEventPoints].
  /// Letting them go one at a time would leave a partial copy of the
  /// organiser's list that still claimed to be theirs.
  Future<void> remove(int rideId, String pointId) async {
    final current = _sets[rideId] ?? const ControlPointSet();
    await _write(rideId, current.copyWith(
      points: [
        for (final p in current.points)
          if (p.id != pointId || p.isImported) p,
      ],
    ));
  }

  Future<void> _write(int rideId, ControlPointSet set) async {
    _sets[rideId] = set;
    notifyListeners();
    await _store.save(rideId, set);
  }

  static List<ControlPoint> _sorted(List<ControlPoint> points) =>
      points..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
}
