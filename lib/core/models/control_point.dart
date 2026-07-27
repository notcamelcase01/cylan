import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'ride_profile.dart';

/// What a control point marks. The rider picks one when adding the point; it
/// drives the marker icon and colour on the map and in the list.
///
/// Unlike the API's enum-like strings (`Ride.sourceFormat` and friends, which
/// the server owns), this set is defined entirely in the app — control points
/// are local to the device — so a closed Dart enum is safe. [fromStorage] still
/// tolerates an unknown name so a file written by a newer build doesn't break
/// an older one.
enum ControlPointType {
  checkpoint('Checkpoint', Icons.flag_outlined, Color(0xFF2563EB)),
  water('Water', Icons.water_drop_outlined, Color(0xFF0891B2)),
  food('Food', Icons.restaurant_outlined, Color(0xFFEA580C)),
  mechanical('Mechanical', Icons.build_outlined, Color(0xFF6B7280)),
  rest('Rest stop', Icons.chair_outlined, Color(0xFF7C3AED)),
  danger('Caution', Icons.warning_amber_outlined, Color(0xFFDC2626));

  final String label;
  final IconData icon;
  final Color color;

  const ControlPointType(this.label, this.icon, this.color);

  static ControlPointType fromStorage(String? name) =>
      ControlPointType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => ControlPointType.checkpoint,
      );
}

/// A point of interest a rider pins to a route — a water stop, a checkpoint, a
/// junction to watch out for.
///
/// Control points are **personal and local to the device**: they're the rider's
/// own annotations on any route they can open, including rides they don't own,
/// and they never reach the server. See `ControlPointStore` for how they
/// persist.
///
/// The rider can place one by tapping the map or by typing a distance along the
/// route, but that's only how the position is *chosen* — either way the point
/// is stored as plain [latitude]/[longitude]. Nothing downstream has to care
/// which method was used, and a point never has to be re-derived from a route
/// that may have changed underneath it.
///
/// An event's organiser can publish a set of points, but those are only ever an
/// **offer**: the rider imports them on request (see
/// `ControlPointsProvider.importFromEvent`), which copies them in as ordinary
/// points of the rider's own. Nothing is ever seeded automatically, so two
/// events sharing one route can't fight over the rider's list — see
/// [sourceEventId].
class ControlPoint {
  /// Unique within a ride's set, and **always locally generated** (see
  /// [newId]) — including for a point imported from an event.
  ///
  /// Reusing the organiser's id here would be a bug: ids are only unique
  /// within one event, so a rider who imports two events that both happen to
  /// use `cp1` would end up with a collision in a single list.
  final String id;
  final String label;
  final ControlPointType type;
  final double latitude;
  final double longitude;

  /// How far along the route this point sits, derived from the route at
  /// creation time. Purely for ordering and display ("at km 42") — the
  /// position itself is [latitude]/[longitude].
  final double distanceKm;

  /// The event this point was imported from, or null when the rider placed it
  /// themselves.
  ///
  /// Only bookkeeping: an imported point is the rider's own copy, editable and
  /// deletable like any other. This records where it came from so the rider can
  /// remove one event's points without touching another's, and so the same
  /// event isn't offered for import twice.
  final int? sourceEventId;

  bool get isImported => sourceEventId != null;

  const ControlPoint({
    required this.id,
    required this.label,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.sourceEventId,
  });

  LatLng get position => LatLng(latitude, longitude);

  ControlPoint copyWith({
    String? label,
    ControlPointType? type,
    double? latitude,
    double? longitude,
    double? distanceKm,
  }) =>
      ControlPoint(
        id: id,
        label: label ?? this.label,
        type: type ?? this.type,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        distanceKm: distanceKm ?? this.distanceKm,
        sourceEventId: sourceEventId,
      );

  /// A copy of this point as the rider's own, ready to store — a fresh local
  /// id, its place along [profile] worked out, and a note of the event it came
  /// from. This is the whole of "importing": there is no live link back to the
  /// event afterwards, so the organiser editing their list later doesn't reach
  /// in and change anything the rider now owns.
  ControlPoint importedInto(RideProfile profile, {required int eventId}) =>
      ControlPoint(
        id: newId(),
        label: label,
        type: type,
        latitude: latitude,
        longitude: longitude,
        distanceKm: profile.nearestDistanceKm(position),
        sourceEventId: eventId,
      );

  factory ControlPoint.fromJson(Map<String, dynamic> json) => ControlPoint(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        type: ControlPointType.fromStorage(json['type'] as String?),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        sourceEventId: json['source_event_id'] as int?,
      );

  /// One of an event's published points, as the API sends it
  /// (`default_control_points` — id, label, type, latitude, longitude).
  ///
  /// These are only ever an offer to the rider, so what comes back here is a
  /// display shape, not something to store: [distanceKm] stays zero (the API's
  /// embedded ride carries no elevation profile to measure against) and
  /// [sourceEventId] stays null until the rider actually imports it, at which
  /// point [importedInto] fills both in.
  factory ControlPoint.fromEventJson(Map<String, dynamic> json) => ControlPoint(
        id: json['id'] as String,
        label: (json['label'] as String?)?.trim().isNotEmpty == true
            ? json['label'] as String
            : ControlPointType.fromStorage(json['type'] as String?).label,
        type: ControlPointType.fromStorage(json['type'] as String?),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceKm: 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'latitude': latitude,
        'longitude': longitude,
        'distance_km': distanceKm,
        'source_event_id': sourceEventId,
      };

  /// This point as the API's `default_control_points` wants it — position only,
  /// no [distanceKm] (the server has the route and doesn't store a derived
  /// distance) and no [sourceEventId] (that's a rider-side concept).
  Map<String, dynamic> toEventJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'latitude': latitude,
        'longitude': longitude,
      };

  /// An id for a rider-added point. Only has to be unique within one ride's
  /// set on one device, so the clock plus a few random digits is plenty — no
  /// need to pull in a UUID dependency.
  static String newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = math.Random().nextInt(1 << 20).toRadixString(36);
    return 'cp_${stamp}_$salt';
  }
}
