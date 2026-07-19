import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/ride.dart';
import '../../../core/providers/theme_provider.dart';
import '../../audax/screens/audax_events_screen.dart';
import '../../auth/screens/profile_screen.dart';
import '../../weather/providers/weather_cache_provider.dart';
import '../providers/rides_provider.dart';
import 'offline_rides_screen.dart';
import 'ride_detail_screen.dart';
import 'strava_import_screen.dart';

/// The Rides tab. Its [RidesProvider] is app-level (see `main.dart`), not
/// created here, so a ride copied in from an event's route can refresh this
/// list and it survives tab switches. This screen owns the *session* lifecycle:
/// it reloads page 1 on mount, and the shell (hence this screen) is rebuilt on
/// each sign-in, so a fresh login never shows the previous rider's rides.
class RidesListScreen extends StatefulWidget {
  const RidesListScreen({super.key});

  @override
  State<RidesListScreen> createState() => _RidesListScreenState();
}

class _RidesListScreenState extends State<RidesListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  static const _searchDebounce = Duration(milliseconds: 350);
  Timer? _searchTimer;

  bool _uploading = false;
  bool _importingGoogleMaps = false;

  bool get _busy => _uploading || _importingGoogleMaps;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<RidesProvider>().loadMore();
      }
    });
    // Reload page 1 for this session. Post-frame because loadFirst notifies
    // synchronously, which can't happen during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RidesProvider>().loadFirst();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer =
        Timer(_searchDebounce, () => context.read<RidesProvider>().setQuery(value));
  }

  Future<void> _showImportOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload a file'),
              subtitle: const Text('GPX, FIT or KML from your device'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Color(0xFFFC4C02)),
              title: const Text('Import from Strava'),
              subtitle: const Text('Bring in your saved Strava routes'),
              onTap: () => Navigator.pop(context, 'strava'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined, color: Color(0xFF4285F4)),
              title: const Text('Import from Google Maps'),
              subtitle: const Text('Paste a Maps directions link · beta'),
              onTap: () => Navigator.pop(context, 'google_maps'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'file') {
      _pickAndUpload();
    } else if (choice == 'strava') {
      _importFromStrava();
    } else if (choice == 'google_maps') {
      _importFromGoogleMaps();
    }
  }

  void _openOffline() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OfflineRidesScreen()),
    );
  }

  void _openAudaxEvents() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AudaxEventsScreen()),
    );
  }

  Future<void> _importFromStrava() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StravaImportScreen()),
    );
    if (imported == true && mounted) {
      context.read<RidesProvider>().refresh();
    }
  }

  Future<void> _importFromGoogleMaps() async {
    final input = await showDialog<_GoogleMapsImportInput>(
      context: context,
      builder: (context) => const _GoogleMapsImportDialog(),
    );
    if (input == null || !mounted) return;

    setState(() => _importingGoogleMaps = true);
    try {
      final ride = await context
          .read<RidesProvider>()
          .importFromGoogleMaps(url: input.url, name: input.name);
      if (!mounted) return;

      final error = context.read<RidesProvider>().error;
      if (ride == null && error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => _importingGoogleMaps = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'fit', 'kml'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final ride = await context.read<RidesProvider>().upload(filePath: path);
      if (!mounted) return;

      final error = context.read<RidesProvider>().error;
      if (ride == null && error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      // However this ended, the flag has to come back down: it disables the
      // FAB, which is the only way to start another upload.
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 'Add ride' normally; a percentage once a file upload reports progress;
  /// 'Importing…' for the (progressless) Google Maps import. The bare
  /// 'Uploading…' covers the gap before the first upload report and files
  /// whose size isn't known — the ring is indeterminate in exactly those
  /// cases too.
  String _fabLabel(double? progress) {
    if (_importingGoogleMaps) return 'Importing…';
    if (!_uploading) return 'Add ride';
    if (progress == null) return 'Uploading…';
    return 'Uploading ${(progress * 100).round()}%';
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

  /// Blocks the swipe-to-delete for a public ride (the server 400s on it —
  /// `{"detail": "Only private rides can be deleted."}` — a ride attached to a
  /// public event can't be deleted, even by its owner) with an explanation
  /// instead of letting the card slide away and snap back unexplained.
  Future<void> _explainPublicRideCantBeDeleted(Ride ride) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Can't delete a public ride"),
        content: Text(
          '"${ride.name}" is attached to a public event, so it can\'t be '
          'deleted while public. Make the event private, detach the ride '
          'from it, or delete the event, then try again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(Ride ride) async {
    if (ride.isPublic) {
      await _explainPublicRideCantBeDeleted(ride);
      return false;
    }
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
        // Sort is the only action that acts on this list, so it's the only one
        // that earns a slot; navigation and the theme toggle live in the
        // overflow, where they at least get readable labels.
        actions: [
          PopupMenuButton<RideSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort rides',
            initialValue: ridesProvider.sort,
            onSelected: (value) =>
                context.read<RidesProvider>().setSort(value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: RideSort.newest, child: Text('Newest first')),
              PopupMenuItem(value: RideSort.nameAsc, child: Text('Name (A–Z)')),
              PopupMenuItem(
                  value: RideSort.distanceAsc,
                  child: Text('Distance (shortest first)')),
              PopupMenuItem(
                  value: RideSort.distanceDesc,
                  child: Text('Distance (longest first)')),
            ],
          ),
          Consumer<ThemeProvider>(
            builder: (context, theme, _) => PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                switch (value) {
                  case 'audax':
                    _openAudaxEvents();
                  case 'offline':
                    _openOffline();
                  case 'theme':
                    theme.cycle();
                  case 'profile':
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'audax',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_outlined),
                    title: Text('Audax events'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'offline',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_for_offline_outlined),
                    title: Text('Offline rides'),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'theme',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(theme.icon),
                    title: Text('Theme: ${theme.label}'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.account_circle_outlined),
                    title: Text('Profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _buildBody(context, ridesProvider, weatherCache),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _showImportOptions,
        tooltip: 'Add a ride',
        // While uploading, the ring fills with the bytes actually sent, so a
        // big file over a slow link visibly moves instead of spinning blankly.
        // It stays indeterminate until the first progress report lands (and
        // for a file of unknown length, and for the Google Maps import, which
        // reports no progress at all).
        icon: _busy
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  value: _importingGoogleMaps ? null : ridesProvider.uploadProgress,
                ),
              )
            : const Icon(Icons.add),
        label: Text(_fabLabel(ridesProvider.uploadProgress)),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, RidesProvider provider, WeatherCacheProvider weatherCache) {
    // Show the search field once the rider has rides, or has a query active (so
    // an empty result stays clearable). Hidden for a brand-new, empty library,
    // where the "No rides yet" prompt carries the screen.
    final showSearch = provider.rides.isNotEmpty || provider.hasQuery;
    return Column(
      children: [
        if (showSearch)
          _SearchField(
              controller: _searchController, onChanged: _onSearchChanged),
        Expanded(child: _content(context, provider, weatherCache)),
      ],
    );
  }

  Widget _content(
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
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('View offline rides'),
              onPressed: _openOffline,
            ),
          ],
        ),
      );
    }
    if (provider.rides.isEmpty) {
      // An active search that matched nothing reads differently from an empty
      // library — don't tell a rider with 50 rides to "upload their first".
      if (provider.hasQuery) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No rides match "${provider.query}"',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _searchTimer?.cancel();
                  _searchController.clear();
                  context.read<RidesProvider>().setQuery('');
                },
                child: const Text('Clear search'),
              ),
            ],
          ),
        );
      }
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
            onDismissed: (_) {
              final ridesProvider = context.read<RidesProvider>();
              final weatherCache = context.read<WeatherCacheProvider>();
              // Captured synchronously, before the async gap below, so
              // showing the failure snackbar never touches `context` itself
              // after an `await`.
              final messenger = ScaffoldMessenger.of(context);
              ridesProvider.delete(ride.id).then((success) {
                if (!success) {
                  // Reinserted by RidesProvider.delete on failure — tell the
                  // rider why, since a swiped-away card that silently comes
                  // back otherwise looks like nothing happened. Covers the
                  // public-ride 400 slipping past `_confirmDelete` in a race
                  // (made public by another device between load and swipe),
                  // and any other server-side rejection.
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                      ridesProvider.error ?? "Couldn't delete the ride.",
                    ),
                  ));
                  return;
                }
                // The ride is gone, so its cached forecast describes nothing —
                // drop it (memory + the file on disk) instead of orphaning it.
                // Any *offline* copy is deliberately left alone: it's a
                // standalone snapshot the rider opted into, not a cache.
                // Only on confirmed success — a failed delete leaves the ride
                // in the list, and its forecast is still good.
                weatherCache.reset(ride.id);
              });
            },
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

class _GoogleMapsImportInput {
  final String url;
  final String? name;
  const _GoogleMapsImportInput({required this.url, this.name});
}

/// Collects a Maps link + optional name, showing the beta accuracy warning
/// up front so it's seen before import runs, not after something looks off.
/// Validates the link is non-empty client-side; the server is the source of
/// truth for whether it's actually a usable Maps link (bad input there comes
/// back as a displayable [ApiException], surfaced by the caller).
class _GoogleMapsImportDialog extends StatefulWidget {
  const _GoogleMapsImportDialog();

  @override
  State<_GoogleMapsImportDialog> createState() =>
      _GoogleMapsImportDialogState();
}

class _GoogleMapsImportDialogState extends State<_GoogleMapsImportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    Navigator.pop(
      context,
      _GoogleMapsImportInput(
        url: _urlController.text.trim(),
        name: name.isEmpty ? null : name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Import from Google Maps'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.science_outlined,
                        size: 20, color: theme.colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Beta: Google Maps import can produce a route that\'s '
                        'slightly inaccurate. Double-check it before you ride.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Google Maps link',
                  hintText: 'https://maps.app.goo.gl/...',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Paste a Google Maps directions link'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Ride name (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

/// Debounced name-search box for the rides list. Rebuilds on its own text
/// changes (via [AnimatedBuilder] on the controller) so the clear button
/// appears/disappears without lifting the text into screen state.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search rides',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
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
