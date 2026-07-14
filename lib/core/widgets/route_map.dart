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
/// in time can sit on nearly the same spot. When two bubbles fall within this
/// gap, the later one is shifted back along the route by this same fraction of
/// distance so it separates instead of stacking (see [_placeWeatherBubbles]).
const double _weatherBubbleMinDistanceFraction = 0.02;

const Distance _distance = Distance();

/// Picks a readable subset of weather points spaced at least [_weatherBubbleGap]
/// apart by ETA, always keeping the first and last so the whole route is
/// represented.
List<WeatherPoint> _thinWeather(List<WeatherPoint> points) {
  if (points.length <= 2) return points;
  final kept = <WeatherPoint>[points.first];
  for (final p in points.skip(1)) {
    if (p.eta.difference(kept.last.eta) >= _weatherBubbleGap) {
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

/// The route coordinate at [km] along the ride, linearly interpolated from the
/// profile's parallel distance/lat/lng samples. Used to move an overlapping
/// weather bubble back along the route to a real point on the line.
LatLng _routePointAtKm(RideProfile profile, double km) {
  final d = profile.distanceKm;
  if (d.isEmpty) return LatLng(profile.latitude.first, profile.longitude.first);
  if (km <= d.first) {
    return LatLng(profile.latitude.first, profile.longitude.first);
  }
  for (var i = 1; i < d.length; i++) {
    if (d[i] >= km) {
      final span = d[i] - d[i - 1];
      final t = span <= 0 ? 0.0 : (km - d[i - 1]) / span;
      return LatLng(
        profile.latitude[i - 1] + (profile.latitude[i] - profile.latitude[i - 1]) * t,
        profile.longitude[i - 1] + (profile.longitude[i] - profile.longitude[i - 1]) * t,
      );
    }
  }
  return LatLng(profile.latitude.last, profile.longitude.last);
}

/// The map position for each thinned weather bubble. A bubble whose native
/// position lands within the min-distance gap of one already placed is shifted
/// back along the route by [_weatherBubbleMinDistanceFraction] of total
/// distance, so self-crossing routes don't stack bubbles on the same spot.
List<LatLng> _placeWeatherBubbles(
    RideProfile profile, List<WeatherPoint> bubbles) {
  final maxDistanceKm =
      bubbles.map((p) => p.distanceKm).fold<double>(0, math.max);
  final minMeters = maxDistanceKm * 1000 * _weatherBubbleMinDistanceFraction;
  final shiftKm = maxDistanceKm * _weatherBubbleMinDistanceFraction;
  final placed = <LatLng>[];
  for (final wp in bubbles) {
    var pos = LatLng(wp.latitude, wp.longitude);
    if (placed.any((q) => _distance(pos, q) < minMeters)) {
      pos = _routePointAtKm(profile, wp.distanceKm - shiftKm);
    }
    placed.add(pos);
  }
  return placed;
}

class RouteMap extends StatefulWidget {
  final RideProfile profile;
  final LatLng? liveLocation;

  /// Course over ground in degrees from north, for the live-location arrow.
  /// GPS heading is noisy/meaningless while stationary, so callers should pass
  /// null when not moving — the marker then falls back to a plain dot.
  final double? liveHeading;
  final List<WeatherPoint> weatherPoints;

  /// Marks the point matching the index under the user's finger on the
  /// elevation/gradient chart (see `elevation_chart.dart`'s
  /// `onIndexSelected`), mirroring the web app's chart/map hover linkage.
  final LatLng? highlightLocation;

  /// When false, all gestures are disabled (used for the shareable snapshot).
  final bool interactive;

  /// When false, the map is drawn without a tile basemap — just the route line,
  /// markers and weather bubbles on a plain background. Used for offline rides,
  /// where OSM map tiles aren't available (their usage policy disallows caching
  /// them for offline use). The route is a vector line, so it still pans/zooms
  /// freely; only the streets underneath are missing.
  final bool showBasemap;

  const RouteMap({
    super.key,
    required this.profile,
    this.liveLocation,
    this.liveHeading,
    this.weatherPoints = const [],
    this.highlightLocation,
    this.interactive = true,
    this.showBasemap = true,
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
    final weatherBubblePositions =
        _placeWeatherBubbles(profile, weatherPoints);
    final maxWeatherDistanceKm =
        weatherPoints.map((p) => p.distanceKm).fold<double>(0, math.max);

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
        // With no basemap (offline), give the route line a plain, theme-aware
        // backdrop instead of the grey that would flash behind absent tiles.
        backgroundColor: widget.showBasemap
            ? const Color(0xFFE0E0E0)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all
              : InteractiveFlag.none,
        ),
      ),
      children: [
        if (widget.showBasemap)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.notcamelcase.cylan',
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
            if (widget.liveLocation != null)
              Marker(
                point: widget.liveLocation!,
                child: widget.liveHeading == null
                    ? const Icon(Icons.my_location, color: Colors.blue)
                    : Transform.rotate(
                        // navigation icon points up (north) at angle 0, so
                        // rotate directly by the heading (degrees -> radians).
                        angle: widget.liveHeading! * math.pi / 180,
                        child: const Icon(Icons.navigation,
                            color: Colors.blue, size: 30),
                      ),
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
              for (var i = 0; i < weatherPoints.length; i++)
                Marker(
                  point: weatherBubblePositions[i],
                  width: 40,
                  height: 20,
                  // Scales the natural-size bubble down to fit the marker box
                  // so it can never overflow, whatever the font sizes / text.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _WeatherBubble(
                      point: weatherPoints[i],
                      secondHalf: weatherPoints[i].distanceKm >=
                          maxWeatherDistanceKm / 2,
                    ),
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

  /// Whether this bubble falls in the second half of the ride distance. Those
  /// get an accent background (red on dark, grey on light) to distinguish the
  /// back half of the route from the front.
  final bool secondHalf;
  const _WeatherBubble({required this.point, this.secondHalf = false});

  @override
  Widget build(BuildContext context) {
    final temp = point.temperatureC == null
        ? '–'
        : '${point.temperatureC!.round()}°';
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final Color background;
    final Color foreground;
    if (secondHalf) {
      background = isDark ? const Color(0xFFC62828) : const Color(0xFFBDBDBD);
      foreground = isDark ? Colors.white : Colors.black87;
    } else {
      background = scheme.surface;
      foreground = scheme.onSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: background,
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
            style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w600, color: foreground),
          ),
          if (point.windDirectionDeg != null) ...[
            const SizedBox(width: 1),
            Transform.rotate(
              angle: (point.windDirectionDeg! + 180) % 360 * math.pi / 180,
              child: Text('↑', style: TextStyle(fontSize: 8, color: foreground)),
            ),
          ],
        ],
      ),
    );
  }
}
