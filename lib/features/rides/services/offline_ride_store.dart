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

  /// Writes the ride + weather + notable sections to disk. Throws
  /// [OfflineSaveException] for a route with no GPS track; leaves nothing
  /// half-written behind on failure.
  Future<void> save(
    Ride ride,
    List<WeatherPoint> weather,
    List<RideSection> sections,
  ) async {
    final profile = ride.profile;
    if (profile == null || profile.latitude.isEmpty) {
      throw OfflineSaveException('This ride has no GPS track to save offline.');
    }

    final dir = await _rideDir(ride.id);
    try {
      await dir.create(recursive: true);
      await File('${dir.path}/ride.json')
          .writeAsString(jsonEncode(ride.toJson()));
      await File('${dir.path}/weather.json')
          .writeAsString(jsonEncode([for (final w in weather) w.toJson()]));
      await File('${dir.path}/sections.json')
          .writeAsString(jsonEncode([for (final s in sections) s.toJson()]));
      await File('${dir.path}/meta.json').writeAsString(jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// All saved rides, newest first. Skips any directory that can't be parsed.
  Future<List<OfflineRide>> list() async {
    final root = await _rootDir();
    if (!await root.exists()) return [];
    final result = <OfflineRide>[];
    for (final entity in root.listSync()) {
      if (entity is Directory) {
        final loaded = await _load(entity);
        if (loaded != null) result.add(loaded);
      }
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
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
