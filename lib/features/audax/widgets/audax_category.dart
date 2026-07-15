import 'package:flutter/material.dart';

/// Presentation for an event's `category` (the brevet distance/type). Shared
/// by the event card's badge and the filter sheet's chips so a category reads
/// the same colour everywhere.
///
/// The category is an **opaque string** from the source calendar — new values
/// appear without an API change (`1200` and `Fleche` already did once), and
/// it's nullable. So this never parses it as a number to derive a colour:
/// known values get a curated one, anything else falls back to
/// [_unknownCategoryColor].

/// Curated colours, ordered short → long as a "heat" ramp: easy distances read
/// cool/green, the big ones run hot through orange to red, and the epics go
/// deep purple. Non-numeric types (`Fleche`) get their own distinct hue rather
/// than a place on the ramp.
const _categoryColors = <String, Color>{
  '100': Color(0xFF26A69A), // teal
  '150': Color(0xFF66BB6A), // green
  '200': Color(0xFFFFA726), // amber
  '300': Color(0xFFFB8C00), // orange
  '400': Color(0xFFF4511E), // deep orange
  '600': Color(0xFFE53935), // red
  '1000': Color(0xFF8E24AA), // purple
  '1200': Color(0xFF5E35B1), // deep purple
  'Fleche': Color(0xFFD81B60), // magenta
};

/// Warm neutral for a category we don't have a colour for — either absent
/// (`null`/blank) or one the source added after this list was written. Chosen
/// to sit alongside the ramp without pretending to be part of it.
const _unknownCategoryColor = Color(0xFF8D6E63); // warm brown

/// The seed colour for [category]; [_unknownCategoryColor] for null, blank, or
/// unrecognised values. Match is case-insensitive so `fleche` and `Fleche`
/// agree.
Color audaxCategoryColor(String? category) {
  final key = category?.trim();
  if (key == null || key.isEmpty) return _unknownCategoryColor;
  for (final entry in _categoryColors.entries) {
    if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
  }
  return _unknownCategoryColor;
}

/// Display text for [category]: numeric distances get a `km` suffix (`200` →
/// `200 km`), named types are shown as-is (`Fleche`), and a missing one reads
/// `TBA` like the card's other absent fields.
String audaxCategoryLabel(String? category) {
  final raw = category?.trim();
  if (raw == null || raw.isEmpty) return 'TBA';
  return double.tryParse(raw) == null ? raw : '$raw km';
}

/// A small colour-coded pill naming an event's category. Sized to sit inline
/// beside a title without adding a row.
class AudaxCategoryBadge extends StatelessWidget {
  final String? category;

  const AudaxCategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final seed = audaxCategoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: audaxBadgeFill(context, seed),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        audaxCategoryLabel(category),
        style: TextStyle(
          color: audaxBadgeInk(context, seed),
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Background tint for [seed] that keeps its hue readable in both themes —
/// the raw colours are tuned for light surfaces and turn muddy on dark ones.
///
/// Nothing here is category-specific: the registration badge seeds it with a
/// status colour so both pills get identical treatment.
Color audaxBadgeFill(BuildContext context, Color seed) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return seed.withValues(alpha: dark ? 0.26 : 0.15);
}

/// Foreground colour for text/icons drawn on [audaxBadgeFill]: darkened on
/// light backgrounds, lightened on dark ones, so contrast holds either way.
Color audaxBadgeInk(BuildContext context, Color seed) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final hsl = HSLColor.fromColor(seed);
  final lightness = dark
      ? (hsl.lightness + 0.30).clamp(0.0, 1.0)
      : (hsl.lightness - 0.18).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).toColor();
}
