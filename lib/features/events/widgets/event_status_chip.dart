import 'package:flutter/material.dart';

/// A small badge for an event's lifecycle [status] (`DRAFT` / `PUBLISHED` /
/// `CANCELLED` / `COMPLETED`). Colour keys off the machine-readable status, not
/// the label, so an unknown value still renders (neutrally) rather than
/// throwing.
class EventStatusChip extends StatelessWidget {
  final String status;
  const EventStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg, String label) = switch (status) {
      'PUBLISHED' => (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
          'Published',
        ),
      'DRAFT' => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
          'Draft',
        ),
      'CANCELLED' => (scheme.onErrorContainer, scheme.errorContainer, 'Cancelled'),
      'COMPLETED' => (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          'Completed',
        ),
      _ => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest, status),
    };
    return _Pill(fg: fg, bg: bg, label: label);
  }
}

/// A small badge for an event's [visibility] (`PRIVATE` / `PUBLIC`).
class EventVisibilityChip extends StatelessWidget {
  final String visibility;
  const EventVisibilityChip({super.key, required this.visibility});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPublic = visibility == 'PUBLIC';
    return _Pill(
      fg: scheme.onSurfaceVariant,
      bg: scheme.surfaceContainerHighest,
      label: isPublic ? 'Public' : 'Private',
      icon: isPublic ? Icons.public : Icons.lock_outline,
    );
  }
}

class _Pill extends StatelessWidget {
  final Color fg;
  final Color bg;
  final String label;
  final IconData? icon;
  const _Pill({
    required this.fg,
    required this.bg,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
