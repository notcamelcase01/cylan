import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/ride_profile.dart';
import '../models/weather_point.dart';

/// Zoom range clamp applied to both the camera and the tile layer. Without
/// this, zooming out far enough requests a huge/degenerate set of world
/// tiles at very low zoom, which has caused GPU/memory crashes in
/// flutter_map (and most other slippy-map implementations) — capping how
/// far out the camera can go avoids that class of crash.
const double _minZoom = 3;
const double _maxZoom = 19;

/// Zoom used the first time the camera locks onto a live GPS fix.
const double _liveFollowZoom = 17;

/// Keeps the camera inside a single copy of the world (Web-Mercator latitude
/// limits). This is the key guard against the fast-zoom-out crash: it stops
/// the camera from reaching the very-low-zoom state where flutter_map tiles
/// the whole world (and repeats it horizontally), which both crashes on
/// device and duplicates every marker across each world copy.
final LatLngBounds _worldBounds = LatLngBounds(
  const LatLng(-85.05, -179.9),
  const LatLng(85.05, 179.9),
);

/// Minimum gap between weather bubbles shown on the map, by estimated arrival
/// time. The API returns a fixed number of points regardless of ride length,
/// so on a short ride they bunch up (e.g. one per km); thinning to ~one per
/// 30 min of travel keeps the map readable. The full set still shows in the
/// weather list.
const Duration _weatherBubbleGap = Duration(minutes: 30);

/// Minimum ground distance between two shown weather bubbles, as a fraction of
/// the ride's total distance. ETA spacing alone doesn't stop bubbles stacking
/// where the route crosses itself (loops, out-and-backs): two points far apart
/// in time can sit on nearly the same spot. Also requiring this geographic gap
/// keeps those from overlapping, and scaling it to ride length keeps the
/// spacing sensible on both short and long rides.
const double _weatherBubbleMinDistanceFraction = 0.02;

const Distance _distance = Distance();

/// Picks a readable subset of weather points spaced at least [_weatherBubbleGap]
/// apart by ETA *and* [_weatherBubbleMinDistanceFraction] of the ride's total
/// distance apart on the ground from every other kept point, always keeping the
/// first and last so the whole route is represented.
List<WeatherPoint> _thinWeather(List<WeatherPoint> points) {
  if (points.length <= 2) return points;
  // Ride distance drives the geographic spacing threshold. Points aren't
  // guaranteed sorted by distance, so take the max rather than the last.
  final maxDistanceKm =
      points.map((p) => p.distanceKm).reduce(math.max);
  final minMeters = maxDistanceKm * 1000 * _weatherBubbleMinDistanceFraction;
  final kept = <WeatherPoint>[points.first];
  bool clearsAllKept(WeatherPoint p) {
    final at = LatLng(p.latitude, p.longitude);
    for (final k in kept) {
      if (_distance(at, LatLng(k.latitude, k.longitude)) < minMeters) {
        return false;
      }
    }
    return true;
  }

  for (final p in points.skip(1)) {
    if (p.eta.difference(kept.last.eta) >= _weatherBubbleGap &&
        clearsAllKept(p)) {
      kept.add(p);
    }
  }
  final last = points.last;
  if (kept.last != last) {
    // Replace a too-close tail point, or append, so the finish is shown.
    if (last.eta.difference(kept.last.eta) < _weatherBubbleGap &&
        kept.length > 1) {
      kept[kept.length - 1] = last;
    } else {
      kept.add(last);
    }
  }
  return kept;
}

class RouteMap extends StatefulWidget {
  final RideProfile profile;
  final LatLng? liveLocation;
  final LatLng? nextTurn;
  final List<WeatherPoint> weatherPoints;

  /// Marks the point matching the index under the user's finger on the
  /// elevation/gradient chart (see `elevation_chart.dart`'s
  /// `onIndexSelected`), mirroring the web app's chart/map hover linkage.
  final LatLng? highlightLocation;

  /// When false, all gestures are disabled (used for the shareable snapshot).
  final bool interactive;

  const RouteMap({
    super.key,
    required this.profile,
    this.liveLocation,
    this.nextTurn,
    this.weatherPoints = const [],
    this.highlightLocation,
    this.interactive = true,
  });

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _mapController = MapController();
  bool _hasCenteredOnLive = false;

  @override
  void didUpdateWidget(covariant RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loc = widget.liveLocation;
    if (loc != null && loc != oldWidget.liveLocation) {
      _followLocation(loc);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // Keeps the camera centered on the rider as GPS fixes come in, mirroring
  // the web app's live mode (`map.panTo(...)` in live.js). The first fix
  // zooms in to street level; later fixes just pan, preserving whatever
  // zoom the rider has since chosen.
  void _followLocation(LatLng loc) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final zoom = _hasCenteredOnLive
          ? _mapController.camera.zoom
          : _liveFollowZoom;
      _hasCenteredOnLive = true;
      _mapController.move(loc, zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    if (profile.latitude.isEmpty) {
      return const Center(child: Text('No GPS data for this route'));
    }
    final points = [
      for (var i = 0; i < profile.latitude.length; i++)
        LatLng(profile.latitude[i], profile.longitude[i]),
    ];
    final bounds = LatLngBounds.fromPoints(points);
    final routeColor = Theme.of(context).colorScheme.primary;
    final weatherPoints = _thinWeather(widget.weatherPoints);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(32),
        ),
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        cameraConstraint: CameraConstraint.contain(bounds: _worldBounds),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.cylan',
          minZoom: _minZoom,
          maxZoom: _maxZoom,
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: points, strokeWidth: 4, color: routeColor),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: points.first,
              child: const Icon(Icons.flag, color: Colors.green),
            ),
            Marker(
              point: points.last,
              child: const Icon(Icons.flag_circle, color: Colors.red),
            ),
            if (widget.nextTurn != null)
              Marker(
                point: widget.nextTurn!,
                child: const Icon(
                  Icons.turn_right,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
            if (widget.liveLocation != null)
              Marker(
                point: widget.liveLocation!,
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
            if (widget.highlightLocation != null)
              Marker(
                point: widget.highlightLocation!,
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF97316),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (weatherPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final wp in weatherPoints)
                Marker(
                  point: LatLng(wp.latitude, wp.longitude),
                  width: 40,
                  height: 20,
                  // Scales the natural-size bubble down to fit the marker box
                  // so it can never overflow, whatever the font sizes / text.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _WeatherBubble(point: wp),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A weather-along-the-route bubble: emoji + rounded temperature + a wind
/// arrow. Open-Meteo reports the direction wind comes FROM, so the arrow is
/// rotated a further 180° to point where it's blowing TOWARD (matches map.js).
class _WeatherBubble extends StatelessWidget {
  final WeatherPoint point;
  const _WeatherBubble({required this.point});

  @override
  Widget build(BuildContext context) {
    final temp = point.temperatureC == null
        ? '–'
        : '${point.temperatureC!.round()}°';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(point.icon, style: const TextStyle(fontSize: 8)),
          const SizedBox(width: 1),
          Text(
            temp,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
          ),
          if (point.windDirectionDeg != null) ...[
            const SizedBox(width: 1),
            Transform.rotate(
              angle: (point.windDirectionDeg! + 180) % 360 * math.pi / 180,
              child: const Text('↑', style: TextStyle(fontSize: 8)),
            ),
          ],
        ],
      ),
    );
  }
}
