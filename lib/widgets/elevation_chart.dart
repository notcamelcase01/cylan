import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/ride_profile.dart';

enum ProfileChartMode { elevation, gradient }

/// Elevation or gradient profile over distance. Gradient mode fills orange
/// above 0 % and blue below, mirroring the web app's gradient chart
/// (`map_overlay_charts.js`).
class ElevationChart extends StatelessWidget {
  final RideProfile profile;
  final ProfileChartMode mode;

  /// Called with the profile-array index under the user's finger while
  /// dragging/tapping the chart, and `null` once they lift off — lets the
  /// caller show a matching marker on the route map (mirrors the web app's
  /// chart/map hover linkage in map_overlay_charts.js).
  final ValueChanged<int?>? onIndexSelected;

  const ElevationChart({
    super.key,
    required this.profile,
    this.mode = ProfileChartMode.elevation,
    this.onIndexSelected,
  });

  static const _gradientAbove = Color(0xFFF97316); // orange
  static const _gradientBelow = Color(0xFF3B82F6); // blue

  @override
  Widget build(BuildContext context) {
    if (profile.distanceKm.isEmpty) {
      return const Center(child: Text('No profile data'));
    }
    final isGradient = mode == ProfileChartMode.gradient;
    final series = isGradient ? profile.gradientPct : profile.elevationM;
    if (series.isEmpty) {
      return const Center(child: Text('No profile data'));
    }
    final spots = <FlSpot>[
      for (var i = 0; i < profile.distanceKm.length && i < series.length; i++)
        FlSpot(profile.distanceKm[i], series[i]),
    ];
    final unit = isGradient ? '%' : 'm';
    final lineColor =
        isGradient ? _gradientAbove : Theme.of(context).colorScheme.primary;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${value.toStringAsFixed(0)}km',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                  '${value.toStringAsFixed(0)}$unit',
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: onIndexSelected != null,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}$unit',
                      const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
          touchCallback: onIndexSelected == null
              ? null
              : (event, response) {
                  final spots = response?.lineBarSpots;
                  if (event is FlPanEndEvent ||
                      event is FlTapUpEvent ||
                      event is FlLongPressEnd ||
                      event is FlPointerExitEvent ||
                      spots == null ||
                      spots.isEmpty) {
                    onIndexSelected!(null);
                    return;
                  }
                  onIndexSelected!(spots.first.spotIndex);
                },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2,
            color: lineColor,
            dotData: const FlDotData(show: false),
            // Elevation: soft area fill under the line.
            belowBarData: isGradient
                ? BarAreaData(
                    show: true,
                    applyCutOffY: true,
                    cutOffY: 0,
                    color: _gradientAbove.withValues(alpha: 0.4),
                  )
                : BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.15),
                  ),
            // Gradient: fill above the line up to 0 % (descents) in blue.
            aboveBarData: isGradient
                ? BarAreaData(
                    show: true,
                    applyCutOffY: true,
                    cutOffY: 0,
                    color: _gradientBelow.withValues(alpha: 0.4),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
