import 'package:flutter/material.dart';

import '../../../core/models/ride_profile.dart';
import '../../../core/models/ride_section.dart';
import '../../../core/models/weather_point.dart';
import '../screens/section_detail_screen.dart';

/// The ride's notable climbs and descents as a tappable list. Tapping a row
/// opens the [SectionDetailScreen] for that section, zoomed in on the map with
/// the weather that falls on it. Shared by the online and offline ride details;
/// [showBasemap] is `false` offline (no OSM tiles).
///
/// Renders nothing when there are no sections, so callers can drop it in
/// unconditionally.
class NotableSectionsCard extends StatelessWidget {
  final List<RideSection> sections;
  final RideProfile profile;
  final List<WeatherPoint> weather;
  final bool showBasemap;

  const NotableSectionsCard({
    super.key,
    required this.sections,
    required this.profile,
    this.weather = const [],
    this.showBasemap = true,
  });

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Notable sections',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${sections.length}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Climbs and descents worth knowing about. Tap one to see it on the '
          'map with the weather on it.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        for (final section in sections) ...[
          _SectionTile(
            section: section,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SectionDetailScreen(
                  section: section,
                  profile: profile,
                  weather: weather,
                  showBasemap: showBasemap,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final RideSection section;
  final VoidCallback onTap;
  const _SectionTile({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Text(section.icon, style: const TextStyle(fontSize: 28)),
        title: Text(section.label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${section.startKm.toStringAsFixed(1)}–'
          '${section.endKm.toStringAsFixed(1)} km · '
          '${section.distanceKm.toStringAsFixed(1)} km · '
          '${section.avgGradientPct.toStringAsFixed(1)}% avg'
          '${!section.isClimb && section.sharpTurns > 0 ? ' · ${section.sharpTurns} sharp turns' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
