import 'dart:convert';
import 'dart:io';

import 'package:cylan/core/models/ride.dart';
import 'package:cylan/core/models/ride_profile.dart';
import 'package:cylan/core/models/weather_point.dart';
import 'package:cylan/features/rides/services/offline_ride_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points the store at a real temp directory, so these exercise actual file
/// writes and reads rather than a fake — the format on disk *is* what's under
/// test here, including what an older version of the app left behind.
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Ride _ride(int id, String name) => Ride(
      id: id,
      name: name,
      sourceFormat: 'gpx',
      recordedAt: null,
      createdAt: DateTime(2026, 1, 1),
      distanceKm: 42.5,
      distanceM: 42500,
      totalAscentM: 100,
      totalDescentM: 100,
      minElevationM: 0,
      maxElevationM: 100,
      netElevationM: 0,
      maxGradientPct: 5,
      minGradientPct: -5,
      pointCount: 3,
      profile: RideProfile(
        distanceKm: const [0, 1, 2],
        elevationM: const [10, 20, 30],
        gradientPct: const [1, 2, 3],
        latitude: const [12.9, 12.91, 12.92],
        longitude: const [77.5, 77.51, 77.52],
      ),
    );

WeatherPoint _weather(String icon) => WeatherPoint(
      distanceKm: 0,
      eta: DateTime(2026, 1, 1, 8),
      latitude: 12.9,
      longitude: 77.5,
      matchedTime: DateTime(2026, 1, 1, 8),
      temperatureC: 21.4,
      feelsLikeC: 20,
      precipitationMm: 0,
      humidityPct: 50,
      windKmh: 5,
      windDirectionDeg: 90,
      windDirection: 'E',
      condition: 'Clear',
      icon: icon,
    );

void main() {
  late Directory tmp;
  late OfflineRideStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cylan_offline_test');
    PathProviderPlatform.instance = _TempPathProvider(tmp.path);
    store = OfflineRideStore();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a saved ride is listed from meta.json alone', () async {
    await store.save(_ride(1, 'Nandi loop'), [_weather('☀️')], const []);

    final summaries = await store.listSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.id, 1);
    expect(summaries.single.name, 'Nandi loop');
    expect(summaries.single.distanceKm, 42.5);
    expect(summaries.single.firstWeather?.icon, '☀️',
        reason: 'the list badge reads the first forecast point');
  });

  test('listing never opens the GPS track', () async {
    await store.save(_ride(1, 'Nandi loop'), const [], const []);

    // Deleting ride.json leaves only the metadata. If listing still works, it
    // provably never touched the track — which is the entire point: the track
    // is the multi-megabyte part this provider used to hold forever.
    await File('${tmp.path}/offline_rides/1/ride.json').delete();

    final summaries = await store.listSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.name, 'Nandi loop');
  });

  test('load() returns the full ride, so the offline map can draw it',
      () async {
    await store.save(_ride(7, 'Ghat climb'), [_weather('🌧️')], const []);

    final full = await store.load(7);
    expect(full, isNotNull);
    expect(full!.ride.profile, isNotNull,
        reason: 'the offline detail draws the route from this profile — '
            'without it the map has nothing to render');
    expect(full.ride.profile!.latitude, hasLength(3));
    expect(full.ride.profile!.longitude, hasLength(3));
    expect(full.weather.single.icon, '🌧️');
    expect(full.savedAt, isNotNull);
  });

  test('save() reports the savedAt it wrote', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final savedAt = await store.save(_ride(1, 'a'), const [], const []);
    final reloaded = (await store.listSummaries()).single.savedAt;

    expect(savedAt.isAfter(before), isTrue);
    expect(reloaded.toIso8601String(), savedAt.toIso8601String(),
        reason: 'the caller builds its list row from this rather than reading '
            'the ride back off the disk it just wrote');
  });

  group('rides saved by an older version of the app', () {
    /// Writes a ride the way the app used to: a meta.json carrying only
    /// saved_at, with everything else living in ride.json.
    Future<void> writeLegacy(int id, String name) async {
      final dir = Directory('${tmp.path}/offline_rides/$id');
      await dir.create(recursive: true);
      await File('${dir.path}/ride.json')
          .writeAsString(jsonEncode(_ride(id, name).toJson()));
      await File('${dir.path}/weather.json')
          .writeAsString(jsonEncode([_weather('⛅').toJson()]));
      await File('${dir.path}/meta.json').writeAsString(
          jsonEncode({'saved_at': DateTime(2025, 6, 1).toIso8601String()}));
    }

    test('are still listed, by falling back to the ride itself', () async {
      await writeLegacy(3, 'Old favourite');

      final summaries = await store.listSummaries();
      expect(summaries, hasLength(1),
          reason: 'a ride saved before this format existed must not vanish '
              'from the list on upgrade');
      expect(summaries.single.name, 'Old favourite');
      expect(summaries.single.distanceKm, 42.5);
      expect(summaries.single.savedAt, DateTime(2025, 6, 1),
          reason: 'the original save date must survive the migration');
      expect(summaries.single.firstWeather?.icon, '⛅');
    });

    test('are upgraded in place, so the slow path is paid once', () async {
      await writeLegacy(3, 'Old favourite');
      await store.listSummaries();

      final meta = jsonDecode(
              await File('${tmp.path}/offline_rides/3/meta.json').readAsString())
          as Map<String, dynamic>;
      expect(meta['name'], 'Old favourite',
          reason: 'meta.json should now carry the summary fields');

      // Proven by the same trick as above: with ride.json gone, a listing that
      // still works can only be reading the upgraded metadata.
      await File('${tmp.path}/offline_rides/3/ride.json').delete();
      expect((await store.listSummaries()).single.name, 'Old favourite');
    });

    test('survive a directory that cannot be read at all', () async {
      await store.save(_ride(1, 'good'), const [], const []);
      final broken = Directory('${tmp.path}/offline_rides/999');
      await broken.create(recursive: true);
      await File('${broken.path}/meta.json').writeAsString('{not json');

      final summaries = await store.listSummaries();
      expect(summaries.map((s) => s.name), ['good'],
          reason: 'one unreadable ride must not take the whole list down');
    });
  });
}
