import 'dart:io';

import 'package:cylan/core/models/control_point.dart';
import 'package:cylan/core/models/ride_profile.dart';
import 'package:cylan/features/rides/providers/control_points_provider.dart';
import 'package:cylan/features/rides/services/control_point_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points the store at a real temp directory, so these exercise actual file
/// writes and reads — the on-disk format is what's under test.
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

ControlPoint _point(String id, {double km = 1, int? sourceEventId}) =>
    ControlPoint(
      id: id,
      label: 'Point $id',
      type: ControlPointType.water,
      latitude: 12.9,
      longitude: 77.5,
      distanceKm: km,
      sourceEventId: sourceEventId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cp_store_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('ControlPointStore', () {
    test('returns an empty set for a ride with nothing saved', () async {
      final set = await ControlPointStore().load(7);
      expect(set.points, isEmpty);
      expect(set.importedEventIds, isEmpty);
    });

    test('round-trips points through disk', () async {
      final store = ControlPointStore();
      await store.save(
        7,
        ControlPointSet(
          points: [_point('a', km: 2), _point('b', km: 5)],
          importedEventIds: const {42},
        ),
      );

      final loaded = await store.load(7);
      expect(loaded.points.map((p) => p.id), ['a', 'b']);
      expect(loaded.points.first.type, ControlPointType.water);
      expect(loaded.points.first.distanceKm, 2);
      expect(loaded.importedEventIds, {42});
    });

    test('keeps rides separate', () async {
      final store = ControlPointStore();
      await store.save(1, ControlPointSet(points: [_point('a')]));
      await store.save(2, ControlPointSet(points: [_point('b')]));

      expect((await store.load(1)).points.single.id, 'a');
      expect((await store.load(2)).points.single.id, 'b');
    });

    test('treats an unreadable file as empty rather than throwing', () async {
      final store = ControlPointStore();
      await store.save(7, ControlPointSet(points: [_point('a')]));
      await File('${tempDir.path}/control_points/7.json')
          .writeAsString('not json');

      expect((await store.load(7)).points, isEmpty);
    });

    test('a point saved by a newer build with an unknown type still loads',
        () async {
      await Directory('${tempDir.path}/control_points').create(recursive: true);
      await File('${tempDir.path}/control_points/7.json').writeAsString(
        '{"points":[{"id":"a","label":"Ferry","type":"teleporter",'
        '"latitude":12.9,"longitude":77.5,"distance_km":3}]}',
      );

      final loaded = await ControlPointStore().load(7);
      expect(loaded.points.single.label, 'Ferry');
      expect(loaded.points.single.type, ControlPointType.checkpoint);
    });
  });

  group('ControlPointsProvider', () {
    test('add keeps points in route order and persists them', () async {
      final provider = ControlPointsProvider();
      await provider.load(7);
      await provider.add(7, _point('far', km: 40));
      await provider.add(7, _point('near', km: 2));

      expect(provider.pointsFor(7).map((p) => p.id), ['near', 'far']);
      expect((await ControlPointStore().load(7)).points.map((p) => p.id),
          ['near', 'far']);
    });

    test('update replaces a point and re-sorts when it moved', () async {
      final provider = ControlPointsProvider();
      await provider.load(7);
      await provider.add(7, _point('a', km: 2));
      await provider.add(7, _point('b', km: 5));

      await provider.update(7, _point('a', km: 9).copyWith(label: 'moved'));

      expect(provider.pointsFor(7).map((p) => p.id), ['b', 'a']);
      expect(provider.pointsFor(7).last.label, 'moved');
    });

    test("removes one of the rider's own points", () async {
      final provider = ControlPointsProvider();
      await provider.load(7);
      await provider.add(7, _point('a'));
      await provider.remove(7, 'a');

      expect(provider.pointsFor(7), isEmpty);
    });

    test('points survive a fresh provider reading them back', () async {
      final provider = ControlPointsProvider();
      await provider.load(7);
      await provider.add(7, _point('a', km: 3));

      final reopened = ControlPointsProvider();
      await reopened.load(7);
      expect(reopened.pointsFor(7).single.id, 'a');
      expect(reopened.pointsFor(7).single.distanceKm, 3);
    });
  });

  group('importing an event', () {
    // A straight 4 km line, so a point's distance along the route follows from
    // its longitude.
    final profile = RideProfile(
      distanceKm: const [0, 1, 2, 3, 4],
      elevationM: const [0, 0, 0, 0, 0],
      gradientPct: const [0, 0, 0, 0, 0],
      latitude: const [12.0, 12.0, 12.0, 12.0, 12.0],
      longitude: const [77.0, 77.01, 77.02, 77.03, 77.04],
    );

    ControlPoint offered(String id, {double lng = 77.02}) =>
        ControlPoint.fromEventJson({
          'id': id,
          'label': 'Organiser $id',
          'type': 'water',
          'latitude': 12.0,
          'longitude': lng,
        });

    Future<void> import(
      ControlPointsProvider provider, {
      required int eventId,
      required List<ControlPoint> points,
    }) =>
        provider.importFromEvent(7,
            eventId: eventId, points: points, profile: profile);

    test('copies the points in and places them along the route', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1', lng: 77.03)]);

      final imported = provider.pointsFor(7).single;
      expect(imported.label, 'Organiser d1');
      expect(imported.distanceKm, 3);
      expect(imported.sourceEventId, 1);
      expect(provider.hasImported(7, 1), isTrue);
    });

    test('gives each copy a fresh local id, not the organiser id', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('cp1')]);
      expect(provider.pointsFor(7).single.id, isNot('cp1'));
    });

    test('two events using the same organiser id do not collide', () async {
      // The case the whole design exists for: one route, two events, ids that
      // are only unique within their own event.
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('cp1', lng: 77.01)]);
      await import(provider, eventId: 2, points: [offered('cp1', lng: 77.03)]);

      final points = provider.pointsFor(7);
      expect(points.length, 2);
      expect(points.map((p) => p.id).toSet().length, 2);
      expect(points.map((p) => p.sourceEventId), [1, 2]);
    });

    test('importing the same event twice adds nothing', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);
      await import(provider, eventId: 1, points: [offered('d1')]);
      expect(provider.pointsFor(7).length, 1);
    });

    test('removing one event leaves the other and the rider alone', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('a', lng: 77.01)]);
      await import(provider, eventId: 2, points: [offered('b', lng: 77.03)]);
      await provider.add(7, _point('mine', km: 2));

      await provider.removeEventPoints(7, 1);

      expect(provider.pointsFor(7).map((p) => p.sourceEventId), [null, 2]);
      expect(provider.hasImported(7, 1), isFalse);
      expect(provider.hasImported(7, 2), isTrue);
    });

    test('removing an event re-arms its import', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);
      await provider.removeEventPoints(7, 1);
      await import(provider, eventId: 1, points: [offered('d1')]);

      expect(provider.pointsFor(7).length, 1);
      expect(provider.hasImported(7, 1), isTrue);
    });

    test('an imported point cannot be edited', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);
      final imported = provider.pointsFor(7).single;

      await provider.update(7, imported.copyWith(label: 'hijacked'));

      expect(provider.pointsFor(7).single.label, 'Organiser d1');
    });

    test('an imported point cannot be deleted on its own', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);

      await provider.remove(7, provider.pointsFor(7).single.id);

      expect(provider.pointsFor(7).length, 1);
    });

    test('deleting the rider\'s own points never re-arms an import', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);
      await provider.add(7, _point('mine'));
      await provider.remove(7, 'mine');

      expect(provider.hasImported(7, 1), isTrue);
    });

    test('imports survive a fresh provider reading them back', () async {
      final provider = ControlPointsProvider();
      await import(provider, eventId: 1, points: [offered('d1')]);

      final reopened = ControlPointsProvider();
      await reopened.load(7);
      expect(reopened.hasImported(7, 1), isTrue);
      expect(reopened.pointsFor(7).single.sourceEventId, 1);
    });
  });
}
