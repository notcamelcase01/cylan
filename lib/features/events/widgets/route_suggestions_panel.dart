import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../../core/models/route_suggestion.dart';
import '../../tracking/services/location_service.dart';

/// A discovery panel shown on the create-event screen: curated route ideas near
/// the rider, to help them plan. Primary path is a 25 km radius match from the
/// device location; if location is denied or unavailable it falls back to a
/// city dropdown, exactly as the backend's two suggestion modes are designed
/// (`EVENTPLAN.md` §7.4).
///
/// A suggestion is a staff-curated ride the rider doesn't own, so it can't be
/// attached to an event directly. "Use this route" **forks** it — copies it
/// into the rider's own library (`POST /rides/{id}/fork/`) — and hands the
/// resulting [Ride] back via [onRouteForked] so the form can attach it like any
/// other ride.
class RouteSuggestionsPanel extends StatefulWidget {
  final ValueChanged<Ride>? onRouteForked;
  const RouteSuggestionsPanel({super.key, this.onRouteForked});

  @override
  State<RouteSuggestionsPanel> createState() => _RouteSuggestionsPanelState();
}

enum _Phase { idle, loading, loaded, error }

class _RouteSuggestionsPanelState extends State<RouteSuggestionsPanel> {
  final _api = ApiClient.instance;
  final _location = LocationService();

  _Phase _phase = _Phase.idle;
  String? _error;
  SuggestionsResult? _result;

  /// City fallback state, revealed when location isn't available.
  bool _showCityPicker = false;
  List<String> _cities = [];
  bool _citiesLoading = false;
  String? _selectedCity;

  /// The suggestion currently being forked, so its card can show a spinner and
  /// the others stay disabled while one fork is in flight.
  int? _forkingId;

  Future<void> _use(RouteSuggestion suggestion) async {
    setState(() => _forkingId = suggestion.id);
    try {
      final ride = await _api.forkRide(suggestion.id);
      if (!mounted) return;
      widget.onRouteForked?.call(ride);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${ride.name}" — attached to the event.')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't add that route.")),
        );
      }
    } finally {
      if (mounted) setState(() => _forkingId = null);
    }
  }

  Future<void> _findNearMe() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      await _location.ensureReady();
      // A time limit is essential: on a device with no GPS fix (indoors, a
      // simulator with no location set) getCurrentPosition never returns, which
      // is exactly the "infinite loading" this panel showed. A timeout drops us
      // into the city fallback instead of spinning forever.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final result = await _api.getRouteSuggestions(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.loaded;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    } catch (e) {
      // Permission denied, location services off, or a timed-out fix all
      // dead-end the radius path — fall back to the city picker rather than
      // leaving the panel loading.
      if (!mounted) return;
      setState(() {
        _error = e is LocationPermissionDenied
            ? e.message
            : "Couldn't get your location. Pick a city instead.";
        _phase = _Phase.error;
      });
      _revealCityPicker();
    }
  }

  Future<void> _revealCityPicker() async {
    setState(() {
      _showCityPicker = true;
      _citiesLoading = _cities.isEmpty;
    });
    if (_cities.isNotEmpty) return;
    try {
      final cities = await _api.getSuggestionLocations();
      if (!mounted) return;
      setState(() => _cities = cities);
    } catch (_) {
      // The city list is a convenience; leave it empty on failure and let the
      // rider retry "near me" instead.
    } finally {
      if (mounted) setState(() => _citiesLoading = false);
    }
  }

  Future<void> _findInCity(String city) async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
      _selectedCity = city;
    });
    try {
      final result = await _api.getRouteSuggestions(city: city);
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.loaded;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't get route suggestions.";
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.explore_outlined,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Route ideas near you',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Curated routes near you. "Use this route" adds a copy to your rides '
            'and attaches it to the event.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ..._buildBody(theme),
        ],
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme) {
    return [
      if (_phase == _Phase.idle && !_showCityPicker)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _findNearMe,
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Find routes near me'),
          ),
        ),
      if (_phase == _Phase.loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ),
      if (_showCityPicker) ..._buildCityPicker(theme),
      if (_phase == _Phase.loaded && _result != null) ..._buildResults(theme),
      if (_phase != _Phase.loading &&
          !_showCityPicker &&
          _phase != _Phase.idle)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _revealCityPicker,
            icon: const Icon(Icons.location_city, size: 18),
            label: const Text('Pick a city instead'),
          ),
        ),
    ];
  }

  List<Widget> _buildCityPicker(ThemeData theme) {
    return [
      if (_citiesLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_cities.isEmpty)
        Text(
          'No cities with curated routes yet.',
          style: theme.textTheme.bodySmall,
        )
      else
        DropdownButtonFormField<String>(
          initialValue: _selectedCity,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'City'),
          items: [
            for (final c in _cities)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (city) {
            if (city != null) _findInCity(city);
          },
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            setState(() {
              _showCityPicker = false;
              if (_phase == _Phase.error) _phase = _Phase.idle;
            });
          },
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Use my location instead'),
        ),
      ),
    ];
  }

  List<Widget> _buildResults(ThemeData theme) {
    final suggestions = _result!.suggestions;
    if (suggestions.isEmpty) {
      return [
        Text(
          _result!.mode == 'radius'
              ? 'No curated routes within 25 km. Try picking a city.'
              : 'No curated routes in that city yet.',
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    final forking = _forkingId != null;
    return [
      for (final s in suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SuggestionCard(
            suggestion: s,
            busy: _forkingId == s.id,
            // While one fork is in flight, don't let a second start.
            onUse: forking ? null : () => _use(s),
          ),
        ),
    ];
  }
}

class _SuggestionCard extends StatelessWidget {
  final RouteSuggestion suggestion;
  final bool busy;
  final VoidCallback? onUse;
  const _SuggestionCard({
    required this.suggestion,
    required this.busy,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = suggestion;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _meta(theme, Icons.straighten,
                  '${s.distanceKm.toStringAsFixed(1)} km'),
              _meta(theme, Icons.terrain, s.terrainLabel),
              if (s.location != null && s.location!.isNotEmpty)
                _meta(theme, Icons.place_outlined, s.location!),
              if (s.distanceFromUserKm != null)
                _meta(theme, Icons.near_me,
                    '${s.distanceFromUserKm!.toStringAsFixed(1)} km away'),
            ],
          ),
          if (s.elevationRemarks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.elevationRemarks,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onUse,
              icon: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: const Text('Use this route'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String label) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
