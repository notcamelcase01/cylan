import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/control_point.dart';
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
const double _weatherBubbleMinDistanceFraction = 0.06;

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

/// The map position for each thinned weather bubble. A bubble whose native
/// position lands within the min-distance gap of one already placed is shifted
/// back along the route by [_weatherBubbleMinDistanceFraction] of total
/// distance, so self-crossing routes don't stack bubbles on the same spot.
List<LatLng> _placeWeatherBubbles(
  RideProfile profile,
  List<WeatherPoint> bubbles,
) {
  final maxDistanceKm = bubbles
      .map((p) => p.distanceKm)
      .fold<double>(0, math.max);
  final minMeters = maxDistanceKm * 1000 * _weatherBubbleMinDistanceFraction;
  final shiftKm = maxDistanceKm * _weatherBubbleMinDistanceFraction;
  final placed = <LatLng>[];
  for (final wp in bubbles) {
    var pos = LatLng(wp.latitude, wp.longitude);
    if (placed.any((q) => _distance(pos, q) < minMeters)) {
      pos = profile.pointAtKm(wp.distanceKm - shiftKm);
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

  /// An optional wider route drawn faintly *behind* [profile], for context —
  /// used by the section detail, where [profile] is one climb/descent and this
  /// is the whole ride, so the rider can see where the section sits and which
  /// way the route continues. The camera still frames [profile], so the context
  /// line just trails off the edges until the user zooms out. Null on the full
  /// ride map (nothing to sit behind).
  final List<LatLng>? contextRoute;

  /// When true (the default during live tracking), the camera keeps snapping to
  /// each new [liveLocation]. The live-tracking screen turns this off when the
  /// rider pans the map so it stops fighting them, then flips it back on (which
  /// re-centers) when they tap Recenter.
  final bool followLocation;

  /// Called when a rider gesture moves the map while [followLocation] is on, so
  /// the parent can drop out of follow mode and show its Recenter button.
  final VoidCallback? onUserPannedAway;

  /// The rider's personal control points, drawn as labelled pins.
  final List<ControlPoint> controlPoints;

  /// Called when a control point's pin is tapped, so the parent can offer to
  /// edit or delete it.
  final void Function(ControlPoint)? onControlPointTap;

  /// When non-null the map is in "place a control point" mode: the next tap
  /// anywhere on the map reports its coordinates here instead of doing
  /// nothing. The parent is responsible for showing that the mode is active
  /// and for leaving it.
  final void Function(LatLng)? onMapTapForControlPoint;

  const RouteMap({
    super.key,
    required this.profile,
    this.liveLocation,
    this.liveHeading,
    this.weatherPoints = const [],
    this.highlightLocation,
    this.interactive = true,
    this.showBasemap = true,
    this.contextRoute,
    this.followLocation = true,
    this.onUserPannedAway,
    this.controlPoints = const [],
    this.onControlPointTap,
    this.onMapTapForControlPoint,
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
    if (loc == null || !widget.followLocation) return;
    // Snap to a new fix, or re-center when follow was just re-enabled (the
    // rider tapped Recenter after panning away).
    final newFix = loc != oldWidget.liveLocation;
    final reEngaged = !oldWidget.followLocation;
    if (newFix || reEngaged) {
      _followLocation(loc);
    }
  }

  // A rider drag/pinch while following drops us out of follow mode; a
  // programmatic camera move (a new fix, or Recenter) reports hasGesture:false
  // and is ignored, so following never cancels itself.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture && widget.followLocation) {
      widget.onUserPannedAway?.call();
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
    final weatherBubblePositions = _placeWeatherBubbles(profile, weatherPoints);
    final maxWeatherDistanceKm = weatherPoints
        .map((p) => p.distanceKm)
        .fold<double>(0, math.max);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(32),
        ),
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        onPositionChanged: _onPositionChanged,
        onTap: widget.onMapTapForControlPoint == null
            ? null
            : (_, point) => widget.onMapTapForControlPoint!(point),
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
        // Whole-ride line behind the main route, for the section detail (see
        // [contextRoute]). The route color at the normal width; the section
        // itself is drawn on top thicker and in dark orange, so it reads as a
        // highlighted stretch of the same route.
        if (widget.contextRoute != null && widget.contextRoute!.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.contextRoute!,
                strokeWidth: 4,
                color: routeColor,
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              // Thicken and recolor the section over its context line so it
              // stands out as "you are here" on the full route.
              strokeWidth: widget.contextRoute != null ? 7 : 4,
              color: widget.contextRoute != null
                  ? const Color(0xFFC2410C) // dark orange
                  : routeColor,
            ),
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
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.blue,
                          size: 30,
                        ),
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
                      secondHalf:
                          weatherPoints[i].distanceKm >=
                          maxWeatherDistanceKm / 2,
                    ),
                  ),
                ),
            ],
          ),
        // Last, so the rider's own pins sit above the weather bubbles and stay
        // tappable where the two overlap.
        if (widget.controlPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final cp in widget.controlPoints)
                Marker(
                  point: cp.position,
                  width: 24,
                  height: 24,
                  // Anchor the pin's point at the coordinate rather than its
                  // centre, so it marks the spot the way a map pin should.
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: widget.onControlPointTap == null
                        ? null
                        : () => widget.onControlPointTap!(cp),
                    child: _ControlPointPin(point: cp),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A control point's map pin: the type's icon on the type's colour.
class _ControlPointPin extends StatelessWidget {
  final ControlPoint point;
  const _ControlPointPin({required this.point});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: point.type.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 2),
        ],
      ),
      child: Icon(point.type.icon, color: Colors.white, size: 12),
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
          Text(point.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 1),
          Text(
            temp,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          if (point.windDirectionDeg != null) ...[
            const SizedBox(width: 1),
            Transform.rotate(
              angle: (point.windDirectionDeg! + 180) % 360 * math.pi / 180,
              child: Text(
                '↑',
                style: TextStyle(
                  fontSize: 20,
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
