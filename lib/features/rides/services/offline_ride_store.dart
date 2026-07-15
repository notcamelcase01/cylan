import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/models/ride.dart';
import '../../../core/models/ride_section.dart';
import '../../../core/models/weather_point.dart';

/// Thrown when a route can't be saved for offline use (e.g. it has no GPS
/// track). Carries a message safe to show the user.
class OfflineSaveException implements Exception {
  final String message;
  OfflineSaveException(this.message);
  @override
  String toString() => message;
}

/// A route saved for offline use: the ride and its frozen weather forecast,
/// captured at save time. Renders with no network — the map draws the route as
/// a vector line with no tile basemap (OSM tiles can't be cached for offline
/// use per their usage policy).
class OfflineRide {
  final Ride ride;
  final List<WeatherPoint> weather;
  final List<RideSection> sections;
  final DateTime savedAt;

  const OfflineRide({
    required this.ride,
    required this.weather,
    required this.sections,
    required this.savedAt,
  });
}

/// Just enough of a saved ride to draw one row of the offline list.
///
/// Exists so the list doesn't have to open [OfflineRide]s to render: a ride's
/// `ride.json` carries its entire GPS track (a 200 km recording is ~29k points
/// across five parallel arrays), and the list shows a name, a distance, a date
/// and one weather badge. Reading every track to render that was both a long
/// synchronous decode on the UI thread and — because `OfflineRidesProvider`
/// lives above the navigator for the whole process — tens of MB pinned in
/// memory for as long as the app ran.
///
/// These fields are denormalised into `meta.json` at save time; see
/// [OfflineRideStore.listSummaries].
class OfflineRideSummary {
  final int id;
  final String name;
  final double distanceKm;
  final DateTime savedAt;

  /// The ride's first forecast point, for the list's weather badge. Null when
  /// the ride was saved without a forecast.
  final WeatherPoint? firstWeather;

  const OfflineRideSummary({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.savedAt,
    required this.firstWeather,
  });

  factory OfflineRideSummary.of(OfflineRide r) => OfflineRideSummary(
        id: r.ride.id,
        name: r.ride.name,
        distanceKm: r.ride.distanceKm,
        savedAt: r.savedAt,
        firstWeather: r.weather.isEmpty ? null : r.weather.first,
      );
}

/// Persists rides (route + weather) to the app's documents directory so they
/// can be viewed with no connection. Layout:
///
///   `offline_rides/<id>/ride.json`      – the [Ride] (includes its profile)
///   `offline_rides/<id>/weather.json`   – the saved [WeatherPoint] list
///   `offline_rides/<id>/sections.json`  – the saved [RideSection] list
///   `offline_rides/<id>/meta.json`      – savedAt
class OfflineRideStore {
  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/offline_rides');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _rideDir(int id) async =>
      Directory('${(await _rootDir()).path}/$id');

  Future<bool> isSaved(int id) async =>
      File('${(await _rideDir(id)).path}/ride.json').exists();

  /// The contents of `meta.json`: when the ride was saved, plus the handful of
  /// fields the offline list renders, denormalised so [listSummaries] never has
  /// to open `ride.json` and its GPS track. See [OfflineRideSummary].
  Map<String, dynamic> _metaJson({
    required Ride ride,
    required List<WeatherPoint> weather,
    required DateTime savedAt,
  }) =>
      {
        'saved_at': savedAt.toIso8601String(),
        'id': ride.id,
        'name': ride.name,
        'distance_km': ride.distanceKm,
        'first_weather': weather.isEmpty ? null : weather.first.toJson(),
      };

  /// Writes the ride + weather + notable sections to disk, returning the
  /// `savedAt` recorded. Throws [OfflineSaveException] for a route with no GPS
  /// track; leaves nothing half-written behind on failure.
  ///
  /// Returning `savedAt` rather than `void` lets the caller build an
  /// [OfflineRideSummary] from what it already holds, instead of reading the
  /// multi-megabyte ride straight back off the disk it just wrote it to.
  Future<DateTime> save(
    Ride ride,
    List<WeatherPoint> weather,
    List<RideSection> sections,
  ) async {
    final profile = ride.profile;
    if (profile == null || profile.latitude.isEmpty) {
      throw OfflineSaveException('This ride has no GPS track to save offline.');
    }

    final dir = await _rideDir(ride.id);
    final savedAt = DateTime.now();
    try {
      await dir.create(recursive: true);
      await File('${dir.path}/ride.json')
          .writeAsString(jsonEncode(ride.toJson()));
      await File('${dir.path}/weather.json')
          .writeAsString(jsonEncode([for (final w in weather) w.toJson()]));
      await File('${dir.path}/sections.json')
          .writeAsString(jsonEncode([for (final s in sections) s.toJson()]));
      await File('${dir.path}/meta.json').writeAsString(
          jsonEncode(_metaJson(ride: ride, weather: weather, savedAt: savedAt)));
      return savedAt;
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Every saved ride's list-row fields, newest first, read from `meta.json`
  /// alone — the GPS tracks stay on disk until something actually opens one
  /// (see [load]). Skips any directory that can't be parsed.
  Future<List<OfflineRideSummary>> listSummaries() async {
    final root = await _rootDir();
    if (!await root.exists()) return [];
    final result = <OfflineRideSummary>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final summary = await _summaryOf(entity);
      if (summary != null) result.add(summary);
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
  }

  Future<OfflineRideSummary?> _summaryOf(Directory dir) async {
    try {
      final metaFile = File('${dir.path}/meta.json');
      if (!await metaFile.exists()) return null;
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;

      // A meta.json written before the summary fields existed carries only
      // saved_at, so there's nothing to render a row from. Fall back to the
      // slow path once — and rewrite the file while we're here, so this ride
      // never pays it again.
      if (meta['name'] == null) return _migrateLegacyMeta(dir);

      return OfflineRideSummary(
        id: meta['id'] as int,
        name: meta['name'] as String,
        distanceKm: (meta['distance_km'] as num).toDouble(),
        savedAt: DateTime.parse(meta['saved_at'] as String),
        firstWeather: meta['first_weather'] == null
            ? null
            : WeatherPoint.fromJson(
                meta['first_weather'] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads a pre-summary ride in full to build its row, then upgrades its
  /// `meta.json` in place. Best-effort: a failed rewrite just means the next
  /// listing migrates it again.
  Future<OfflineRideSummary?> _migrateLegacyMeta(Directory dir) async {
    final full = await _load(dir);
    if (full == null) return null;
    try {
      await File('${dir.path}/meta.json').writeAsString(jsonEncode(_metaJson(
        ride: full.ride,
        weather: full.weather,
        savedAt: full.savedAt,
      )));
    } catch (_) {
      // Not worth failing the listing over — we already have what we need.
    }
    return OfflineRideSummary.of(full);
  }

  Future<OfflineRide?> load(int id) async => _load(await _rideDir(id));

  Future<OfflineRide?> _load(Directory dir) async {
    try {
      final rideFile = File('${dir.path}/ride.json');
      final metaFile = File('${dir.path}/meta.json');
      if (!await rideFile.exists() || !await metaFile.exists()) return null;

      final ride = Ride.fromJson(
          jsonDecode(await rideFile.readAsString()) as Map<String, dynamic>);
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;

      final weatherFile = File('${dir.path}/weather.json');
      final weather = !await weatherFile.exists()
          ? <WeatherPoint>[]
          : (jsonDecode(await weatherFile.readAsString()) as List<dynamic>)
              .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
              .toList();

      // sections.json is absent for rides saved before offline sections were
      // added — treat a missing file as "no sections" rather than a failure.
      final sectionsFile = File('${dir.path}/sections.json');
      final sections = !await sectionsFile.exists()
          ? <RideSection>[]
          : (jsonDecode(await sectionsFile.readAsString()) as List<dynamic>)
              .map((e) => RideSection.fromJson(e as Map<String, dynamic>))
              .toList();

      return OfflineRide(
        ride: ride,
        weather: weather,
        sections: sections,
        savedAt: DateTime.parse(meta['saved_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(int id) async {
    final dir = await _rideDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
