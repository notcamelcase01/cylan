import 'package:flutter/material.dart';

/// A small badge for a ride's curated-suggestion opt-in status
/// (`PENDING` / `COMPLETED` — `NONE` is never shown, callers gate on
/// [Ride.isSuggested] first). Styled like `EventStatusChip`
/// (`features/events/widgets/event_status_chip.dart`).
class SuggestionStatusChip extends StatelessWidget {
  final String status;
  const SuggestionStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg, String label, IconData icon) = switch (status) {
      'COMPLETED' => (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
          'Public',
          Icons.public,
        ),
      'PENDING' => (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          'Pending review',
          Icons.hourglass_top,
        ),
      _ => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest, status, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
