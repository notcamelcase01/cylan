import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../providers/weather_cache_provider.dart';
import '../widgets/route_map.dart';

class WeatherScreen extends StatefulWidget {
  final Ride ride;

  const WeatherScreen({super.key, required this.ride});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  late DateTime _start;
  late DateTime _finish;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour + 1);
    _finish = _start.add(const Duration(hours: 3));
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _start : _finish;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 8)),
      lastDate: DateTime.now().add(const Duration(days: 8)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = picked;
        if (_finish.isBefore(_start)) {
          _finish = _start.add(const Duration(hours: 3));
        }
      } else {
        _finish = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<WeatherCacheProvider>();
    final rideId = widget.ride.id;
    final points = cache.pointsFor(rideId) ?? const [];
    final isLoading = cache.isLoading(rideId);
    final error = cache.errorFor(rideId);
    final hasFetched = cache.hasFetched(rideId);
    final dateFmt = DateFormat('MMM d, HH:mm');
    final profile = widget.ride.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather along route'),
        actions: [
          if (hasFetched)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset forecast',
              onPressed: () =>
                  context.read<WeatherCacheProvider>().reset(rideId),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDateTime(isStart: true),
                        child: Text('Start: ${dateFmt.format(_start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDateTime(isStart: false),
                        child: Text('Finish: ${dateFmt.format(_finish)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLoading
                        ? null
                        : () => context.read<WeatherCacheProvider>().fetch(
                            rideId,
                            start: _start,
                            finish: _finish),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Get forecast'),
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(error,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          // Route map with temperature/wind bubbles once a forecast is loaded.
          if (profile != null && profile.latitude.isNotEmpty && points.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 200,
                  child: RouteMap(profile: profile, weatherPoints: points),
                ),
              ),
            ),
          Expanded(
            child: !hasFetched
                ? Center(
                    child: Text('Pick a start/finish time and fetch the forecast',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)))
                : points.isEmpty
                    ? const Center(child: Text('No forecast points'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: points.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = points[index];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Text(p.icon,
                                  style: const TextStyle(fontSize: 28)),
                              title: Text(
                                  '${p.distanceKm.toStringAsFixed(1)} km · ${p.condition}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${dateFmt.format(p.eta)} · '
                                '${p.temperatureC?.toStringAsFixed(0) ?? '–'}°C '
                                '(feels ${p.feelsLikeC?.toStringAsFixed(0) ?? '–'}°C) · '
                                'wind ${p.windKmh?.toStringAsFixed(0) ?? '–'} km/h ${p.windDirection} · '
                                '${p.precipitationMm?.toStringAsFixed(1) ?? '0'} mm',
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
