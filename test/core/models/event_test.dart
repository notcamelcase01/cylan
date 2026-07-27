import 'package:cylan/core/models/control_point.dart';
import 'package:cylan/core/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fields every event payload carries, so each test can vary only the part
/// it cares about.
Map<String, dynamic> _summary({Map<String, dynamic> extra = const {}}) => {
      'id': 1,
      'name': 'Sunrise ride',
      'creator': 'alice',
      'event_type': 'RIDE',
      'visibility': 'PUBLIC',
      'status': 'PUBLISHED',
      'start_date': '2026-08-01T05:30:00Z',
      'assembly_point': 'Tank Bund',
      'assembly_point_map_url': null,
      'entry_fee': 0,
      'currency': 'INR',
      'max_subscribers': null,
      'subscriber_count': 3,
      'is_full': false,
      'has_document': false,
      'created_at': '2026-07-01T10:00:00Z',
      ...extra,
    };

/// A detail payload — keyed off `description`, which detail always carries.
Map<String, dynamic> _detail({Map<String, dynamic> extra = const {}}) =>
    _summary(extra: {'description': 'Easy pace', ...extra});

void main() {
  group('default_control_points', () {
    test('parses the organiser points', () {
      final event = Event.fromJson(_detail(extra: {
        'default_control_points': [
          {
            'id': 'cp1',
            'label': 'Water',
            'type': 'water',
            'latitude': 17.4,
            'longitude': 78.4,
          },
        ],
      }));

      final point = event.defaultControlPoints.single;
      expect(point.id, 'cp1');
      expect(point.label, 'Water');
      expect(point.type, ControlPointType.water);
      expect(point.latitude, 17.4);
      expect(point.sourceEventId, isNull,
          reason: 'set only once the rider imports it');
    });

    test('is empty when the event has none', () {
      expect(
        Event.fromJson(_detail(extra: {'default_control_points': []}))
            .defaultControlPoints,
        isEmpty,
      );
    });

    test('is empty on a summary payload, which never carries the field', () {
      expect(Event.fromJson(_summary()).defaultControlPoints, isEmpty);
    });

    test('a type this build does not know falls back to checkpoint', () {
      final event = Event.fromJson(_detail(extra: {
        'default_control_points': [
          {
            'id': 'cp1',
            'label': 'Ferry',
            'type': 'teleporter',
            'latitude': 17.4,
            'longitude': 78.4,
          },
        ],
      }));
      expect(event.defaultControlPoints.single.type,
          ControlPointType.checkpoint);
    });
  });

  group('toEventJson', () {
    test('sends only what the API stores', () {
      final json = ControlPoint(
        id: 'cp1',
        label: 'Water',
        type: ControlPointType.water,
        latitude: 17.4,
        longitude: 78.4,
        // Both are rider-side only: a distance derived from the route, and a
        // note of which event a copy came from.
        distanceKm: 12.5,
        sourceEventId: 3,
      ).toEventJson();

      expect(json, {
        'id': 'cp1',
        'label': 'Water',
        'type': 'water',
        'latitude': 17.4,
        'longitude': 78.4,
      });
    });

    test('round-trips through the API shape', () {
      final original = ControlPoint(
        id: 'cp1',
        label: 'Bridge',
        type: ControlPointType.danger,
        latitude: 17.4,
        longitude: 78.4,
        distanceKm: 0,
      );
      final back = ControlPoint.fromEventJson(original.toEventJson());

      expect(back.id, original.id);
      expect(back.label, original.label);
      expect(back.type, original.type);
      expect(back.latitude, original.latitude);
      expect(back.longitude, original.longitude);
    });
  });
}
