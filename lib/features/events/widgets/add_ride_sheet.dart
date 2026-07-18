import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../rides/screens/strava_import_screen.dart';

/// Lets the rider attach a ride to an event, offering the same four ways they
/// already get rides into the app — pick an existing one, upload a file, import
/// from Google Maps, or import from Strava — and returns the resulting [Ride]
/// (or null if they backed out).
///
/// Reuse without touching the rides feature: every path goes through the shared
/// [ApiClient] (the same calls `RidesProvider` makes under the hood), and the
/// Strava path pushes the existing [StravaImportScreen] unchanged. That screen
/// only reports "something imported" (a bare `true`), so afterwards we drop the
/// rider into the "pick an existing ride" list to choose which just-imported
/// route to attach.
Future<Ride?> showAddRideSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.format_list_bulleted),
            title: const Text('Choose from my rides'),
            subtitle: const Text('Attach a ride you already have'),
            onTap: () => Navigator.pop(context, 'existing'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Upload a file'),
            subtitle: const Text('GPX, FIT or KML from your device'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.link, color: Color(0xFFFC4C02)),
            title: const Text('Import from Strava'),
            subtitle: const Text('Bring in a saved Strava route'),
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
  if (choice == null || !context.mounted) return null;

  switch (choice) {
    case 'existing':
      return _pickExistingRide(context);
    case 'file':
      return _uploadFile(context);
    case 'google_maps':
      return _importGoogleMaps(context);
    case 'strava':
      final imported = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const StravaImportScreen()),
      );
      if (imported == true && context.mounted) {
        // The import screen doesn't say which route(s) landed, so let the rider
        // pick from their (now-updated) rides — the newest are on top.
        return _pickExistingRide(context);
      }
      return null;
  }
  return null;
}

Future<Ride?> _pickExistingRide(BuildContext context) {
  return Navigator.of(context).push<Ride>(
    MaterialPageRoute(builder: (_) => const _MyRidesPickerScreen()),
  );
}

Future<Ride?> _uploadFile(BuildContext context) async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['gpx', 'fit', 'kml'],
  );
  final path = result?.path;
  if (path == null || !context.mounted) return null;
  return _runWithProgress<Ride>(
    context,
    'Uploading…',
    (onProgress) =>
        ApiClient.instance.uploadRide(filePath: path, onProgress: onProgress),
  );
}

Future<Ride?> _importGoogleMaps(BuildContext context) async {
  final input = await showDialog<({String url, String? name})>(
    context: context,
    builder: (_) => const _GoogleMapsUrlDialog(),
  );
  if (input == null || !context.mounted) return null;
  return _runWithProgress<Ride>(
    context,
    'Importing…',
    (_) => ApiClient.instance
        .importFromGoogleMaps(url: input.url, name: input.name),
  );
}

/// Runs a long ride-producing call behind a blocking progress dialog, turning
/// an [ApiException] into a SnackBar and returning the [Ride] (or null on
/// failure/cancel). The optional progress callback drives the percentage for
/// file uploads; Google Maps import reports none, so it shows a bare spinner.
Future<T?> _runWithProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function(void Function(int, int)? onProgress) run,
) async {
  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(label: label, progress: progress),
  );

  try {
    final value = await run((sent, total) {
      progress.value = total > 0 ? sent / total : null;
    });
    if (navigator.canPop()) navigator.pop(); // dismiss the progress dialog
    return value;
  } on ApiException catch (e) {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return null;
  } catch (_) {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Something went wrong. Please try again.')),
    );
    return null;
  } finally {
    progress.dispose();
  }
}

class _ProgressDialog extends StatelessWidget {
  final String label;
  final ValueListenable<double?> progress;
  const _ProgressDialog({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, _) =>
                CircularProgressIndicator(value: value),
          ),
          const SizedBox(width: 20),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _GoogleMapsUrlDialog extends StatefulWidget {
  const _GoogleMapsUrlDialog();

  @override
  State<_GoogleMapsUrlDialog> createState() => _GoogleMapsUrlDialogState();
}

class _GoogleMapsUrlDialogState extends State<_GoogleMapsUrlDialog> {
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
    Navigator.pop(context, (
      url: _urlController.text.trim(),
      name: name.isEmpty ? null : name,
    ));
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
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer),
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
                decoration:
                    const InputDecoration(labelText: 'Ride name (optional)'),
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
        FilledButton(onPressed: _submit, child: const Text('Import')),
      ],
    );
  }
}

/// A paginated picker over the rider's own rides, popping the chosen [Ride].
class _MyRidesPickerScreen extends StatefulWidget {
  const _MyRidesPickerScreen();

  @override
  State<_MyRidesPickerScreen> createState() => _MyRidesPickerScreenState();
}

class _MyRidesPickerScreenState extends State<_MyRidesPickerScreen> {
  final _api = ApiClient.instance;
  final _scrollController = ScrollController();
  final _rides = <Ride>[];
  String? _nextUrl;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasFetched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listRides();
      if (!mounted) return;
      setState(() {
        _rides
          ..clear()
          ..addAll(page.results);
        _nextUrl = page.next;
        _hasFetched = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your rides.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_nextUrl == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.listRides(pageUrl: _nextUrl);
      if (!mounted) return;
      setState(() {
        _rides.addAll(page.results);
        _nextUrl = page.next;
      });
    } catch (_) {
      // A failed "load more" leaves the loaded rides in place; the rider can
      // scroll to retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a ride')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && !_hasFetched) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _loadFirst, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_hasFetched && _rides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'You have no rides yet. Import one from the sheet instead.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _rides.length + (_nextUrl != null ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i >= _rides.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final ride = _rides[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.directions_bike),
            title: Text(ride.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${ride.distanceKm.toStringAsFixed(1)} km · '
              '${ride.totalAscentM.round()} m ascent',
            ),
            onTap: () => Navigator.pop(context, ride),
          ),
        );
      },
    );
  }
}
