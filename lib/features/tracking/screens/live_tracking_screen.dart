import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../../../core/widgets/route_map.dart';
import '../../rides/providers/control_points_provider.dart';
import '../providers/live_tracking_provider.dart';

/// Below this speed, GPS heading is too noisy to be worth showing (it can
/// swing wildly while stopped or barely moving), so the live marker falls
/// back to a plain dot. 1 km/h.
const double _headingSpeedThresholdMps = 1000 / 3600;

/// Brand chrome for the live-tracking screen. [_brandBlue] is the app's seed
/// color (shared with the web app); the gradient pairs it with a brighter
/// sky/cyan so the header and stat badge feel energetic rather than flat.
const Color _brandBlue = Color(0xFF2F6DF6);
const LinearGradient _headerGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_brandBlue, Color(0xFF19C3E6)],
);

class LiveTrackingScreen extends StatelessWidget {
  final Ride ride;

  /// When false, the live map is drawn without a tile basemap (route line only)
  /// — used for offline rides, so live GPS tracking works with no connection.
  final bool showBasemap;

  const LiveTrackingScreen({
    super.key,
    required this.ride,
    this.showBasemap = true,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LiveTrackingProvider(ride)..start(),
      child: _LiveTrackingView(showBasemap: showBasemap),
    );
  }
}

class _LiveTrackingView extends StatefulWidget {
  final bool showBasemap;

  const _LiveTrackingView({this.showBasemap = true});

  @override
  State<_LiveTrackingView> createState() => _LiveTrackingViewState();
}

class _LiveTrackingViewState extends State<_LiveTrackingView> {
  @override
  void initState() {
    super.initState();
    // Load the rider's control points here rather than relying on whichever
    // screen pushed us to have done it — live tracking is reachable from the
    // offline ride detail too, and reads off disk with no network either way.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<ControlPointsProvider>()
          .load(context.read<LiveTrackingProvider>().ride.id);
    });
  }

  /// Whether the map is snapping to the rider. On by default; the rider drops
  /// out of it by panning the map, and taps Recenter to switch it back on.
  bool _following = true;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LiveTrackingProvider>();
    final ride = provider.ride;
    // Plain monochrome app bar (rather than the brand gradient) so it reads
    // as pure black/white against either theme instead of tinted blue.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? Colors.black : Colors.white;
    final onBarColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      // Let the map fill the whole screen and float the header over it, so
      // the map peeks behind the header's rounded corners.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: barColor,
        foregroundColor: onBarColor,
        elevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: onBarColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.directions_bike, size: 18, color: onBarColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ride.name,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontWeight: FontWeight.w700, color: onBarColor),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _LivePulse(color: onBarColor)),
          ),
        ],
      ),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, LiveTrackingProvider provider) {
    final theme = Theme.of(context);
    if (provider.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: _headerGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _brandBlue.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.directions_bike,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text('Getting your ride ready…',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Warming up the GPS',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (provider.permissionMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 56),
              const SizedBox(height: 12),
              Text(provider.permissionMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Geolocator.openLocationSettings(),
                    child: const Text('Location settings'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: const Text('App settings'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.read<LiveTrackingProvider>().start(),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (provider.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(provider.error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final profile = provider.ride.profile!;
    final pos = provider.position;
    final liveLocation = pos == null
        ? null
        : LatLng(pos.latitude, pos.longitude);
    // GPS heading is noise below walking speed, so only show the arrow once
    // actually moving; otherwise the marker falls back to a plain dot.
    final liveHeading = pos != null && pos.speed > _headingSpeedThresholdMps
        ? pos.heading
        : null;
    return Stack(
      children: [
        RouteMap(
          profile: profile,
          liveLocation: liveLocation,
          liveHeading: liveHeading,
          // Read-only here: riding is when the rider most needs to see their
          // water stops and checkpoints coming up, but not when they should be
          // editing them.
          controlPoints: context.watch<ControlPointsProvider>().pointsFor(
            context.read<LiveTrackingProvider>().ride.id,
          ),
          showBasemap: widget.showBasemap,
          followLocation: _following,
          onUserPannedAway: () {
            if (_following) setState(() => _following = false);
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Only shown once the rider has panned off themselves — while
                  // the map is still following, there's nothing to recenter to.
                  if (!_following && liveLocation != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecenterButton(
                          onTap: () => setState(() => _following = true),
                        ),
                      ),
                    ),
                  _StatusCard(provider: provider),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cheerful gradient pill that snaps the map back to the rider and re-engages
/// auto-follow. Appears bottom-right over the map only after the rider has
/// panned away.
class _RecenterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecenterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: _headerGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: _brandBlue.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Recenter',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pulsing "LIVE" badge for the app bar — a gentle heartbeat on the dot
/// so the header feels alive while tracking. Purely decorative. [color] is
/// the app bar's foreground color (black or white, per theme); the red dot
/// stays red regardless so "recording" still reads as urgent on either.
class _LivePulse extends StatefulWidget {
  final Color color;
  const _LivePulse({required this.color});

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.25).animate(_controller),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFFF5252),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating card over the bottom of the map — a hero distance-from-start
/// readout with a gradient bike badge, plus a Strava-style GPS status pill
/// (icon + short phrase) and a small warning badge when off route instead of
/// spelling out the distance off.
class _StatusCard extends StatelessWidget {
  final LiveTrackingProvider provider;
  const _StatusCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final offRoute = (provider.offRouteMeters ?? 0) > 60;
    final hasFix = provider.position != null;

    final String gpsText;
    final Color gpsColor;
    final IconData gpsIcon;
    if (!hasFix) {
      gpsText = provider.gpsMessage ?? 'Acquiring GPS signal…';
      gpsColor = Colors.amber.shade800;
      gpsIcon = Icons.location_searching;
    } else if (provider.gpsMessage != null) {
      gpsText = provider.gpsMessage!;
      gpsColor = theme.colorScheme.error;
      gpsIcon = Icons.gps_off;
    } else {
      gpsText = 'GPS locked';
      gpsColor = Colors.green.shade700;
      gpsIcon = Icons.gps_fixed;
    }

    return Center(
      // Shrink-wraps to its content (mainAxisSize.min) so the happy compact
      // state stays a neat centered pill; the GPS label is Flexible so a long
      // status message ellipsizes instead of overflowing.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _headerGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _brandBlue.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.directions_bike,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (provider.distanceFromStartKm ?? 0).toStringAsFixed(1),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'km',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'from start',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Container(
              width: 1,
              height: 34,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: gpsColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(gpsIcon, size: 15, color: gpsColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        gpsText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: gpsColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (offRoute) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error
                      .withValues(alpha: isDark ? 0.22 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded,
                    size: 18, color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
