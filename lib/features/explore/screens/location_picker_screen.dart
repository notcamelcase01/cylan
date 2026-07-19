import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Full-screen map for picking an arbitrary point: tap anywhere to drop a
/// pin, then confirm. Pops with the picked [LatLng], or `null` if the rider
/// backs out without confirming.
///
/// Deliberately not tied to GPS or a curated city list (unlike
/// `RouteSuggestionsPanel`'s "near me" / city-picker) — this is for
/// [ExploreScreen]'s "any place" search, so the rider can drop a pin anywhere
/// in the world, not just where they're standing.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // A wide starting view rather than any single region — the rider pans/zooms
  // to wherever they actually want, so there's no "right" default beyond
  // "show enough of the world to get started".
  static const _initialCenter = LatLng(20.0, 0.0);
  static const _initialZoom = 2.0;
  static const _minZoom = 2.0;
  static const _maxZoom = 18.0;

  late MapController _mapController;
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() => _picked = point);
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a place'),
        actions: [
          TextButton(
            onPressed: picked == null
                ? null
                : () => Navigator.of(context).pop(picked),
            child: const Text('Use this place'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onTap: _onTap,
              interactionOptions: const InteractionOptions(
                flags: ~InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.notcamelcase.cylan',
                minZoom: _minZoom,
                maxZoom: _maxZoom,
              ),
              if (picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: picked,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_pin,
                          size: 40, color: Colors.red),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Text(
                  picked == null
                      ? 'Tap anywhere on the map to drop a pin'
                      : '${picked.latitude.toStringAsFixed(4)}, '
                          '${picked.longitude.toStringAsFixed(4)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
