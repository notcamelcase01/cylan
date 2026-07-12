import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../providers/auth_provider.dart';
import '../providers/rides_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/weather_cache_provider.dart';
import 'auth_gate.dart';
import 'ride_detail_screen.dart';

class RidesListScreen extends StatelessWidget {
  const RidesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RidesProvider()..loadFirst(),
      child: const _RidesListView(),
    );
  }
}

class _RidesListView extends StatefulWidget {
  const _RidesListView();

  @override
  State<_RidesListView> createState() => _RidesListViewState();
}

class _RidesListViewState extends State<_RidesListView> {
  final _scrollController = ScrollController();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<RidesProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'fit', 'kml'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;

    setState(() => _uploading = true);
    final ride = await context.read<RidesProvider>().upload(filePath: path);
    if (!mounted) return;
    setState(() => _uploading = false);

    final error = context.read<RidesProvider>().error;
    if (ride == null && error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _renameRide(Ride ride) async {
    final controller = TextEditingController(text: ride.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename ride'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != ride.name && mounted) {
      context.read<RidesProvider>().rename(ride.id, newName);
    }
  }

  Future<bool> _confirmDelete(Ride ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ride?'),
        content: Text('"${ride.name}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ridesProvider = context.watch<RidesProvider>();
    final weatherCache = context.watch<WeatherCacheProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rides'),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, theme, _) => IconButton(
              icon: Icon(theme.icon),
              tooltip: 'Theme: ${theme.label}',
              onPressed: theme.cycle,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _buildBody(context, ridesProvider, weatherCache),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploading ? null : _pickAndUpload,
        tooltip: 'Upload GPX/FIT/KML',
        child: _uploading
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, RidesProvider provider, WeatherCacheProvider weatherCache) {
    if (provider.isLoading && provider.rides.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(provider.error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: provider.loadFirst,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (provider.rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.route_outlined,
                  size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No rides yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Tap + to upload a GPX, FIT, or KML file',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: provider.rides.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= provider.rides.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final ride = provider.rides[index];
          final weather = weatherCache.summaryFor(ride.id);
          final theme = Theme.of(context);
          return Dismissible(
            key: ValueKey(ride.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(ride),
            onDismissed: (_) => context.read<RidesProvider>().delete(ride.id),
            background: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Icon(Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer),
            ),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideDetailScreen(rideId: ride.id),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.directions_bike,
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ride.name,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 2,
                              children: [
                                _MetaChip(
                                    icon: Icons.straighten,
                                    label:
                                        '${ride.distanceKm.toStringAsFixed(1)} km'),
                                _MetaChip(
                                    icon: Icons.insert_drive_file_outlined,
                                    label: ride.sourceFormat),
                                if (ride.recordedAt != null)
                                  _MetaChip(
                                      icon: Icons.event_outlined,
                                      label: DateFormat.yMMMd()
                                          .format(ride.recordedAt!)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (weather != null) ...[
                        Text(weather.icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 2),
                        Text(
                          weather.temperatureC == null
                              ? '–'
                              : '${weather.temperatureC!.round()}°',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _renameRide(ride);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: color)),
      ],
    );
  }
}
