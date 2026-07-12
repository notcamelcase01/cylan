import 'package:flutter/material.dart';

/// A soft, theme-aware gradient wash used behind the entry screens (landing,
/// login). Subtle enough to stay out of the way of content, but gives the app
/// a bit more depth than a flat surface.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.16),
              scheme.surface,
            ),
            scheme.surface,
            Color.alphaBlend(
              scheme.tertiary.withValues(alpha: 0.08),
              scheme.surface,
            ),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}
