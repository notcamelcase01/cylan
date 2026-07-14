import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/models/weather_point.dart';

/// A forecast fetched for a ride, with the window it was fetched for.
///
/// The window matters as much as the points: a forecast is only meaningful
/// for the `start`–`finish` the rider picked, so once [finish] is in the past
/// the whole entry is dead weight (see [isExpired]) rather than something to
/// keep showing.
class CachedForecast {
  final List<WeatherPoint> points;
  final DateTime start;
  final DateTime finish;
  final DateTime fetchedAt;

  const CachedForecast({
    required this.points,
    required this.start,
    required this.finish,
    required this.fetchedAt,
  });

  /// True once the planned window has ended — the forecast can't inform a ride
  /// that's already over, and its icon on the rides list would imply a
  /// freshness it doesn't have.
  bool get isExpired => finish.isBefore(DateTime.now());

  factory CachedForecast.fromJson(Map<String, dynamic> json) => CachedForecast(
        points: (json['points'] as List<dynamic>)
            .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        start: DateTime.parse(json['start'] as String),
        finish: DateTime.parse(json['finish'] as String),
        fetchedAt: DateTime.parse(json['fetched_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'points': [for (final p in points) p.toJson()],
        'start': start.toIso8601String(),
        'finish': finish.toIso8601String(),
        'fetched_at': fetchedAt.toIso8601String(),
      };
}

/// Persists fetched forecasts so they survive an app restart, one file per
/// ride: `weather_cache/<rideId>.json`.
///
/// This is deliberately separate from `OfflineRideStore`, which freezes a
/// forecast into an offline *copy* of a ride on purpose and never expires it.
/// This store is just a cache of online data: entries are dropped once their
/// window passes, and it's always safe to delete — the app refetches.
class WeatherStore {
  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/weather_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(int rideId) async =>
      File('${(await _rootDir()).path}/$rideId.json');

  Future<void> save(int rideId, CachedForecast forecast) async {
    await (await _fileFor(rideId)).writeAsString(jsonEncode(forecast.toJson()));
  }

  /// Every still-valid cached forecast, keyed by ride id. Entries whose window
  /// has passed — and any file that can't be parsed (corrupt, or written by an
  /// older format) — are deleted here rather than surfaced, so a bad cache
  /// file can never wedge startup.
  Future<Map<int, CachedForecast>> loadAll() async {
    final root = await _rootDir();
    if (!await root.exists()) return {};

    final result = <int, CachedForecast>{};
    for (final entity in root.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      final rideId = int.tryParse(name.substring(0, name.length - '.json'.length));
      if (rideId == null) continue;
      try {
        final forecast = CachedForecast.fromJson(
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>);
        if (forecast.isExpired) {
          await entity.delete();
          continue;
        }
        result[rideId] = forecast;
      } catch (_) {
        try {
          await entity.delete();
        } catch (_) {
          // Nothing useful to do — skip it and move on.
        }
      }
    }
    return result;
  }

  Future<void> delete(int rideId) async {
    final file = await _fileFor(rideId);
    if (await file.exists()) await file.delete();
  }
}
