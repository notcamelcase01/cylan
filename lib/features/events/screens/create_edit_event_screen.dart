import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/event.dart';
import '../../../core/models/ride.dart';
import '../../weather/screens/weather_screen.dart';
import '../providers/events_cache_provider.dart';
import '../widgets/add_ride_sheet.dart';
import '../widgets/route_suggestions_panel.dart';

/// Create a new event, or edit an existing one when [existing] is passed. One
/// form for both — the only differences are the pre-filled fields, the title,
/// and whether it POSTs or PATCHes. Pops the saved [Event] back to the caller.
///
/// No dedicated provider: the form owns its controllers and calls [ApiClient]
/// directly (like the app's other one-shot dialogs), then invalidates the
/// shared [EventsCacheProvider] so the list reflects the change.
class CreateEditEventScreen extends StatefulWidget {
  final Event? existing;
  const CreateEditEventScreen({super.key, this.existing});

  @override
  State<CreateEditEventScreen> createState() => _CreateEditEventScreenState();
}

class _CreateEditEventScreenState extends State<CreateEditEventScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _assemblyController = TextEditingController();
  final _feeController = TextEditingController();
  final _maxSubsController = TextEditingController();
  final _remarksController = TextEditingController();

  /// One controller per external-link row. Grows/shrinks as the rider adds or
  /// removes links, so multiple links are actually enterable (the old single
  /// multiline field wasn't obvious).
  final List<TextEditingController> _linkControllers = [];

  String _visibility = 'PRIVATE';
  String _status = 'DRAFT';
  String _currency = 'INR';
  DateTime? _startDate;

  int? _rideId;
  String? _rideLabel;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameController.text = e.name;
      _descriptionController.text = e.description ?? '';
      _contactNumberController.text = e.contactNumber ?? '';
      _contactEmailController.text = e.contactEmail ?? '';
      // Only prefill an assembly point the user actually set — a ride-derived
      // value is resolved server-side and would otherwise get "promoted" to a
      // user-set override the moment they save.
      if (e.assemblyPointSource == 'USER_SET') {
        _assemblyController.text = e.assemblyPoint;
      }
      _feeController.text = _trimFee(e.entryFee);
      _maxSubsController.text = e.maxSubscribers?.toString() ?? '';
      _remarksController.text = e.remarksTos ?? '';
      for (final link in e.externalLinks ?? const []) {
        _linkControllers.add(TextEditingController(text: link));
      }
      _visibility = e.visibility;
      _status = e.status;
      _currency = e.currency;
      _startDate = e.startDate;
      if (e.ride != null) {
        _rideId = e.ride!.id;
        _rideLabel =
            '${e.ride!.name} · ${e.ride!.distanceKm.toStringAsFixed(1)} km';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contactNumberController.dispose();
    _contactEmailController.dispose();
    _assemblyController.dispose();
    _feeController.dispose();
    _maxSubsController.dispose();
    _remarksController.dispose();
    for (final c in _linkControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _trimFee(double fee) =>
      fee == fee.roundToDouble() ? fee.round().toString() : fee.toString();

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final base = _startDate ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    setState(() {
      _startDate = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 8,
        time?.minute ?? 0,
      );
    });
  }

  /// Whether the route weather forecast can cover [start]. The server forecasts
  /// only within roughly ±8 days; the upper bound is trimmed to 7 to leave room
  /// for the finish window we seed (start + 3h) to stay inside the limit.
  bool _weatherAvailableFor(DateTime start) {
    final now = DateTime.now();
    return start.isAfter(now.subtract(const Duration(days: 8))) &&
        start.isBefore(now.add(const Duration(days: 7)));
  }

  /// Loads the full attached ride (the weather screen needs its route profile
  /// for the map) and opens the forecast seeded to the event's day.
  Future<void> _openWeatherFor(DateTime start) async {
    final rideId = _rideId;
    if (rideId == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final ride = await ApiClient.instance.getRide(rideId);
      if (!mounted) return;
      navigator.pop(); // dismiss the loading spinner
      navigator.push(
        MaterialPageRoute(
          builder: (_) => WeatherScreen(
            ride: ride,
            initialStart: start,
            initialFinish: start.add(const Duration(hours: 3)),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't load the route for weather.")),
      );
    }
  }

  Future<void> _attachRide() async {
    final ride = await showAddRideSheet(context);
    if (ride == null || !mounted) return;
    _setAttachedRide(ride);
  }

  void _setAttachedRide(Ride ride) {
    setState(() {
      _rideId = ride.id;
      _rideLabel = '${ride.name} · ${ride.distanceKm.toStringAsFixed(1)} km';
    });
  }

  Map<String, dynamic> _buildData() {
    final name = _nameController.text.trim();
    final contactEmail = _contactEmailController.text.trim();
    final links = _linkControllers
        .map((c) => c.text.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return {
      if (name.isNotEmpty) 'name': name,
      // Always sent (even null) so editing can clear the attached ride / cap;
      // on create, null is just "none", the same as the server default.
      'ride': _rideId,
      'description': _descriptionController.text.trim(),
      'visibility': _visibility,
      'status': _status,
      'contact_number': _contactNumberController.text.trim(),
      // Omit when blank so a public event without a typed email inherits the
      // account email (sending "" would instead opt out of a contact email).
      if (contactEmail.isNotEmpty) 'contact_email': contactEmail,
      'start_date': _startDate!.toIso8601String(),
      'assembly_point': _assemblyController.text.trim(),
      'entry_fee': double.tryParse(_feeController.text.trim()) ?? 0,
      'currency': _currency,
      'remarks_tos': _remarksController.text.trim(),
      'external_links': links,
      'max_subscribers': int.tryParse(_maxSubsController.text.trim()),
    };
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      setState(() => _error = 'Pick a start date and time.');
      return;
    }
    if (_visibility == 'PUBLIC' &&
        _contactNumberController.text.trim().isEmpty) {
      setState(() => _error = 'A contact number is required for public events.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = _buildData();
      final event = _isEdit
          ? await ApiClient.instance.updateEvent(widget.existing!.id, data)
          : await ApiClient.instance.createEvent(data);
      if (!mounted) return;
      context.read<EventsCacheProvider>().invalidate();
      Navigator.pop(context, event);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPublic = _visibility == 'PUBLIC';
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit event' : 'New event')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Event name',
                  hintText: 'Defaults to "MyEvent"',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              _sectionLabel('When'),
              _StartDateField(
                startDate: _startDate,
                onTap: _pickStartDate,
              ),
              if (_startDate != null &&
                  _rideId != null &&
                  _weatherAvailableFor(_startDate!)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _openWeatherFor(_startDate!),
                    icon: const Icon(Icons.cloud_outlined, size: 18),
                    label: const Text('Check weather'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _sectionLabel('Route (optional)'),
              _RideField(
                label: _rideLabel,
                onAttach: _attachRide,
                onClear: _rideLabel == null
                    ? null
                    : () => setState(() {
                          _rideId = null;
                          _rideLabel = null;
                        }),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _assemblyController,
                decoration: const InputDecoration(
                  labelText: 'Assembly point',
                  helperText: 'Defaults to the ride start. Your own value wins '
                      'and won\'t be overwritten later.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              RouteSuggestionsPanel(onRouteForked: _setAttachedRide),
              const SizedBox(height: 16),
              _sectionLabel('Details'),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              _sectionLabel('Visibility & status'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'PRIVATE',
                    label: Text('Private'),
                    icon: Icon(Icons.lock_outline),
                  ),
                  ButtonSegment(
                    value: 'PUBLIC',
                    label: Text('Public'),
                    icon: Icon(Icons.public),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (s) =>
                    setState(() => _visibility = s.first),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in kEventStatuses)
                    DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              if (_status == 'DRAFT')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Riders can only subscribe once the event is Published.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              _sectionLabel('Contact${isPublic ? '' : ' (public events)'}'),
              TextFormField(
                controller: _contactNumberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText:
                      'Contact number${isPublic ? ' *' : ''}',
                  helperText: isPublic
                      ? 'Required for public events'
                      : 'Used only if you make the event public',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Contact email',
                  helperText: 'Public events. Blank uses your account email.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel('Entry fee'),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fee',
                        helperText: '0 = free',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        helperText: ' ',
                      ),
                      items: [
                        for (final c in kEventCurrencies)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) =>
                          setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionLabel('Capacity'),
              TextFormField(
                controller: _maxSubsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max subscribers',
                  helperText: 'Leave blank for unlimited',
                ),
              ),
              const SizedBox(height: 16),
              _sectionLabel('More (optional)'),
              _buildLinksEditor(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarksController,
                decoration:
                    const InputDecoration(labelText: 'Remarks / terms'),
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Create event'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinksEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _linkControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _linkControllers[i],
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Link ${i + 1}',
                      hintText: 'https://…',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove link',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _linkControllers.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
                () => _linkControllers.add(TextEditingController())),
            icon: const Icon(Icons.add_link, size: 18),
            label: Text(_linkControllers.isEmpty
                ? 'Add an external link'
                : 'Add another link'),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  static String _statusLabel(String s) => switch (s) {
        'DRAFT' => 'Draft',
        'PUBLISHED' => 'Published',
        'CANCELLED' => 'Cancelled',
        'COMPLETED' => 'Completed',
        _ => s,
      };
}

class _StartDateField extends StatelessWidget {
  final DateTime? startDate;
  final VoidCallback onTap;
  const _StartDateField({required this.startDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = startDate == null
        ? 'Pick a date & time'
        : DateFormat('EEE, d MMM yyyy · h:mm a').format(startDate!);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _RideField extends StatelessWidget {
  final String? label;
  final VoidCallback onAttach;
  final VoidCallback? onClear;
  const _RideField({
    required this.label,
    required this.onAttach,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return OutlinedButton.icon(
        onPressed: onAttach,
        icon: const Icon(Icons.add_road, size: 18),
        label: const Align(
          alignment: Alignment.centerLeft,
          child: Text('Attach a ride'),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_bike),
        title: Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onAttach, child: const Text('Change')),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}
