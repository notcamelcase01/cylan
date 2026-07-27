import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/control_point.dart';
import '../../../core/models/ride_profile.dart';

/// Names and types a control point, and — unless the spot was already chosen on
/// the map — takes the distance along the route to place it at.
///
/// Both ways of adding a point end here, and both produce the same thing: a
/// point with a plain latitude/longitude. A distance typed in is converted once,
/// on save (see [RideProfile.pointAtKm]), and then forgotten — the stored point
/// never has to be re-derived from a route that may since have changed.
///
/// Pops with the finished [ControlPoint], or null if cancelled.
class ControlPointEditorSheet extends StatefulWidget {
  final RideProfile profile;

  /// The point being edited, or null when adding a new one.
  final ControlPoint? initial;

  /// A spot already chosen on the map. When set, the distance is derived from
  /// it and shown read-only instead of being asked for.
  final LatLng? fixedPosition;

  const ControlPointEditorSheet({
    super.key,
    required this.profile,
    this.initial,
    this.fixedPosition,
  });

  static Future<ControlPoint?> show(
    BuildContext context, {
    required RideProfile profile,
    ControlPoint? initial,
    LatLng? fixedPosition,
  }) =>
      showModalBottomSheet<ControlPoint>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ControlPointEditorSheet(
          profile: profile,
          initial: initial,
          fixedPosition: fixedPosition,
        ),
      );

  @override
  State<ControlPointEditorSheet> createState() =>
      _ControlPointEditorSheetState();
}

class _ControlPointEditorSheetState extends State<ControlPointEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _distance;
  late ControlPointType _type;
  String? _distanceError;

  bool get _isEditing => widget.initial != null;
  bool get _distanceIsEditable => widget.fixedPosition == null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _label = TextEditingController(text: initial?.label ?? '');
    _type = initial?.type ?? ControlPointType.checkpoint;
    _distance = TextEditingController(
      text: initial == null ? '' : initial.distanceKm.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _distance.dispose();
    super.dispose();
  }

  /// Where the finished point goes: the spot picked on the map, else the
  /// coordinate at the typed distance along the route.
  double get _resolvedDistanceKm {
    final fixed = widget.fixedPosition;
    if (fixed != null) return widget.profile.nearestDistanceKm(fixed);
    return double.parse(_distance.text.trim());
  }

  void _save() {
    final totalKm = widget.profile.totalKm;
    if (_distanceIsEditable) {
      final km = double.tryParse(_distance.text.trim());
      if (km == null) {
        setState(() => _distanceError = 'Enter a distance in km');
        return;
      }
      if (km < 0 || km > totalKm) {
        setState(() => _distanceError =
            'Must be between 0 and ${totalKm.toStringAsFixed(1)} km');
        return;
      }
    }

    final distanceKm = _resolvedDistanceKm;
    final position = widget.fixedPosition ?? widget.profile.pointAtKm(distanceKm);
    final label = _label.text.trim();
    final initial = widget.initial;

    final point = initial != null
        ? initial.copyWith(
            label: label.isEmpty ? _type.label : label,
            type: _type,
            latitude: position.latitude,
            longitude: position.longitude,
            distanceKm: distanceKm,
          )
        : ControlPoint(
            id: ControlPoint.newId(),
            // An unnamed point still needs something to show in the list, and
            // the type is the most useful thing we know about it.
            label: label.isEmpty ? _type.label : label,
            type: _type,
            latitude: position.latitude,
            longitude: position.longitude,
            distanceKm: distanceKm,
          );
    Navigator.pop(context, point);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalKm = widget.profile.totalKm;
    return Padding(
      // Lift the sheet clear of the keyboard while the distance/label fields
      // are focused.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Edit control point' : 'New control point',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Water stop at the bridge',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in ControlPointType.values)
                ChoiceChip(
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                  avatar: Icon(
                    type.icon,
                    size: 18,
                    color: _type == type ? null : type.color,
                  ),
                  label: Text(type.label),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_distanceIsEditable)
            TextField(
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Distance along route (km)',
                helperText: '0 – ${totalKm.toStringAsFixed(1)} km',
                errorText: _distanceError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_distanceError != null) {
                  setState(() => _distanceError = null);
                }
              },
            )
          else
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'At ${_resolvedDistanceKm.toStringAsFixed(1)} km, picked on the map',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _save,
                child: Text(_isEditing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
