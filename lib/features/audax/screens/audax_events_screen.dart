import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/audax_event.dart';
import '../providers/audax_events_provider.dart';

/// Browse the public Audax India brevet calendar. The server only ever
/// answers for a single calendar month at a time (defaults to the current
/// one) — this screen mirrors that: a month stepper instead of a range
/// picker, plus optional upcoming/city/state/category filters.
class AudaxEventsScreen extends StatelessWidget {
  const AudaxEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AudaxEventsProvider()..loadFirst(),
      child: const _AudaxEventsView(),
    );
  }
}

class _AudaxEventsView extends StatefulWidget {
  const _AudaxEventsView();

  @override
  State<_AudaxEventsView> createState() => _AudaxEventsViewState();
}

class _AudaxEventsViewState extends State<_AudaxEventsView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<AudaxEventsProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth(AudaxEventsProvider provider) async {
    var dialogMonth = provider.selectedMonth;
    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final years = [
            for (var y = DateTime.now().year - 1; y <= DateTime.now().year + 2; y++) y,
          ];
          return AlertDialog(
            title: const Text('Select month'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: dialogMonth.month,
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(DateFormat.MMMM().format(DateTime(2000, m))),
                        ),
                    ],
                    onChanged: (m) => setDialogState(
                      () => dialogMonth = DateTime(dialogMonth.year, m!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: dialogMonth.year,
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) => setDialogState(
                      () => dialogMonth = DateTime(y!, dialogMonth.month),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, dialogMonth),
                child: const Text('Go'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      context.read<AudaxEventsProvider>().setMonth(result);
    }
  }

  Future<void> _openFilters(AudaxEventsProvider provider) async {
    final result = await showModalBottomSheet<_AudaxFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FiltersSheet(
        initial: _AudaxFilters(
          upcomingOnly: provider.upcomingOnly,
          city: provider.city,
          state: provider.state,
          category: provider.category,
        ),
      ),
    );
    if (result != null && mounted) {
      context.read<AudaxEventsProvider>().applyFilters(
            upcomingOnly: result.upcomingOnly,
            city: result.city,
            state: result.state,
            category: result.category,
          );
    }
  }

  void _showLaunchError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUrl(String url, String failureMessage) async {
    final launched =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched) _showLaunchError(failureMessage);
  }

  Future<void> _callClub(String number) async {
    final launched = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!launched) _showLaunchError("Couldn't start a call.");
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudaxEventsProvider>();
    final hasFilters = provider.upcomingOnly ||
        provider.city != null ||
        provider.state != null ||
        provider.category != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audax Events'),
        actions: [
          IconButton(
            icon: Icon(hasFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'Filters',
            onPressed: () => _openFilters(provider),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _MonthStepper(
            month: provider.selectedMonth,
            onPrev: () => provider.setMonth(
              DateTime(provider.selectedMonth.year, provider.selectedMonth.month - 1),
            ),
            onNext: () => provider.setMonth(
              DateTime(provider.selectedMonth.year, provider.selectedMonth.month + 1),
            ),
            onTap: () => _pickMonth(provider),
          ),
        ),
      ),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, AudaxEventsProvider provider) {
    final monthLabel = DateFormat('MMMM yyyy').format(provider.selectedMonth);

    if (provider.isLoading && provider.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(provider.error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: provider.loadFirst, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (provider.events.isEmpty) {
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
              child: Icon(Icons.event_busy_outlined,
                  size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No audax events for $monthLabel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Try another month or clear your filters',
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: provider.events.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= provider.events.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final event = provider.events[index];
          return _AudaxEventCard(
            event: event,
            onTap: event.audaxPageUrl == null
                ? null
                : () => _openUrl(event.audaxPageUrl!, "Couldn't open the event page."),
            onOpenRouteMap: event.routeMapUrl == null
                ? null
                : () => _openUrl(event.routeMapUrl!, "Couldn't open the route map."),
            onCall: event.clubContactNumber == null
                ? null
                : () => _callClub(event.clubContactNumber!),
          );
        },
      ),
    );
  }
}

/// `<` month name/year `>` row shown under the app bar. Tapping the label
/// opens a month/year picker; the arrows step one month at a time. There is
/// deliberately no range picker here — the server only ever answers for one
/// month, so the UI never offers more than that.
class _MonthStepper extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;

  const _MonthStepper({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: onPrev,
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _AudaxFilters {
  final bool upcomingOnly;
  final String? city;
  final String? state;
  final String? category;

  const _AudaxFilters({
    required this.upcomingOnly,
    required this.city,
    required this.state,
    required this.category,
  });
}

const _brevetCategories = ['200', '300', '400', '600', '1000'];

/// Bottom sheet for the upcoming/city/state/category filters. Returns the
/// chosen [_AudaxFilters] via `Navigator.pop`, or `null` if dismissed.
class _FiltersSheet extends StatefulWidget {
  final _AudaxFilters initial;
  const _FiltersSheet({required this.initial});

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late bool _upcomingOnly = widget.initial.upcomingOnly;
  String? _category;
  late final _cityController = TextEditingController(text: widget.initial.city);
  late final _stateController = TextEditingController(text: widget.initial.state);

  @override
  void initState() {
    super.initState();
    _category = widget.initial.category;
  }

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter events',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Upcoming only'),
              subtitle: const Text("Hide this month's events that already passed"),
              value: _upcomingOnly,
              onChanged: (v) => setState(() => _upcomingOnly = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'City', hintText: 'e.g. Mumbai'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stateController,
              decoration:
                  const InputDecoration(labelText: 'State', hintText: 'e.g. Maharashtra'),
            ),
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
                for (final c in _brevetCategories)
                  ChoiceChip(
                    label: Text('$c km'),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = _category == c ? null : c),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _AudaxFilters(
                          upcomingOnly: false, city: null, state: null, category: null),
                    ),
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _AudaxFilters(
                        upcomingOnly: _upcomingOnly,
                        city: _cityController.text.trim(),
                        state: _stateController.text.trim(),
                        category: _category,
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One event row: club, date, start point, fee, registration deadline. Any
/// missing field shows a placeholder rather than being hidden, matching the
/// API's guidance (only `audax_id`/`event_date` are guaranteed non-null).
class _AudaxEventCard extends StatelessWidget {
  final AudaxEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onOpenRouteMap;
  final VoidCallback? onCall;

  const _AudaxEventCard({
    required this.event,
    required this.onTap,
    required this.onOpenRouteMap,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEE, MMM d, yyyy');
    final feeFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.club ?? 'Unnamed club',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onOpenRouteMap != null)
                    IconButton(
                      icon: const Icon(Icons.map_outlined),
                      tooltip: 'Route map',
                      visualDensity: VisualDensity.compact,
                      onPressed: onOpenRouteMap,
                    ),
                  if (onCall != null)
                    IconButton(
                      icon: const Icon(Icons.call_outlined),
                      tooltip: 'Call organizer',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCall,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              _InfoRow(icon: Icons.event_outlined, label: dateFmt.format(event.eventDate)),
              const SizedBox(height: 4),
              _InfoRow(icon: Icons.place_outlined, label: event.startPoint ?? 'TBA'),
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.payments_outlined,
                label: event.eventFee == null ? 'TBA' : feeFmt.format(event.eventFee),
              ),
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.how_to_reg_outlined,
                label: event.registrationCloseDate == null
                    ? 'Registration closes: TBA'
                    : 'Registration closes ${dateFmt.format(event.registrationCloseDate!)}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ),
      ],
    );
  }
}
