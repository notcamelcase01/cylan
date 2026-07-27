import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/models/control_point.dart';

/// One ride's saved control points.
///
/// Everything here belongs to the rider. Points imported from an event were
/// copied in on request and are theirs from that moment — the set holds no
/// pending state, no link back to any event, and nothing that has to be
/// reconciled against the server when it's read.
class ControlPointSet {
  /// Every point for the ride, in route order — the rider's own and any they
  /// imported from an event.
  final List<ControlPoint> points;

  /// Events the rider has already imported from, so the same set isn't offered
  /// (or added) twice.
  ///
  /// Tracked separately from [points] because it has to survive the rider
  /// deleting every imported point one by one: that shouldn't quietly re-arm
  /// the import button. Only removing the event's points as a group does.
  final Set<int> importedEventIds;

  const ControlPointSet({
    this.points = const [],
    this.importedEventIds = const {},
  });

  bool get isEmpty => points.isEmpty && importedEventIds.isEmpty;

  ControlPointSet copyWith({
    List<ControlPoint>? points,
    Set<int>? importedEventIds,
  }) =>
      ControlPointSet(
        points: points ?? this.points,
        importedEventIds: importedEventIds ?? this.importedEventIds,
      );

  factory ControlPointSet.fromJson(Map<String, dynamic> json) =>
      ControlPointSet(
        points: (json['points'] as List<dynamic>? ?? [])
            .map((e) => ControlPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        importedEventIds: (json['imported_event_ids'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toSet(),
      );

  Map<String, dynamic> toJson() => {
        'points': [for (final p in points) p.toJson()],
        'imported_event_ids': importedEventIds.toList(),
      };
}

/// Persists each ride's control points to the app's documents directory, one
/// file per ride: `control_points/<rideId>.json`.
///
/// These are the rider's own annotations and exist only on this device — there
/// is no server copy, so unlike `WeatherStore` this is **not** a cache and must
/// never be cleared as though it could be refetched. Deleting a file here loses
/// the rider's work.
class ControlPointStore {
  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/control_points');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(int rideId) async =>
      File('${(await _rootDir()).path}/$rideId.json');

  /// The ride's saved set, or an empty one when nothing is saved yet.
  ///
  /// A file that can't be parsed is treated as empty rather than deleted: the
  /// rider's points are unrecoverable from anywhere else, so a bad read leaves
  /// the file alone in case a later build can make sense of it.
  Future<ControlPointSet> load(int rideId) async {
    try {
      final file = await _fileFor(rideId);
      if (!await file.exists()) return const ControlPointSet();
      return ControlPointSet.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const ControlPointSet();
    }
  }

  /// Writes the set, or removes the file once nothing is left to remember.
  Future<void> save(int rideId, ControlPointSet set) async {
    final file = await _fileFor(rideId);
    if (set.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(jsonEncode(set.toJson()));
  }
}
