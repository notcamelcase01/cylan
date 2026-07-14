import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/audax_event.dart';
import '../providers/audax_events_cache_provider.dart';
import '../widgets/audax_category.dart';

/// Browse the public Audax India brevet calendar. The server only ever
/// answers for a single calendar month at a time (defaults to the current
/// one) — this screen mirrors that: a month stepper instead of a range
/// picker, plus optional upcoming/city/state/category filters. Fetched
/// month/filter combos are cached for the rest of the app session in
/// [AudaxEventsCacheProvider] (registered in `main.dart`), so leaving and
/// reopening this screen doesn't re-hit the network for the same query.
class AudaxEventsScreen extends StatefulWidget {
  const AudaxEventsScreen({super.key});

  @override
  State<AudaxEventsScreen> createState() => _AudaxEventsScreenState();
}

class _AudaxEventsScreenState extends State<AudaxEventsScreen> {
  final _scrollController = ScrollController();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _upcomingOnly = false;
  String? _city;
  String? _state;
  String? _category;

  String get _key => AudaxEventsCacheProvider.keyFor(
        year: _selectedMonth.year,
        month: _selectedMonth.month,
        upcomingOnly: _upcomingOnly,
        city: _city,
        state: _state,
        category: _category,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<AudaxEventsCacheProvider>().fetchMore(_key);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AudaxEventsCacheProvider>().fetchFilters();
      _fetchCurrent();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrent({bool force = false}) {
    return context.read<AudaxEventsCacheProvider>().fetchFirst(
          _key,
          year: _selectedMonth.year,
          month: _selectedMonth.month,
          upcomingOnly: _upcomingOnly,
          city: _city,
          state: _state,
          category: _category,
          force: force,
        );
  }

  void _selectMonth(DateTime month) {
    final normalized = DateTime(month.year, month.month);
    if (normalized == _selectedMonth) return;
    setState(() => _selectedMonth = normalized);
    _fetchCurrent();
  }

  Future<void> _pickMonth() async {
    var dialogMonth = _selectedMonth;
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
    if (result != null && mounted) _selectMonth(result);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_AudaxFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FiltersSheet(
        initial: _AudaxFilters(
          upcomingOnly: _upcomingOnly,
          city: _city,
          state: _state,
          category: _category,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _upcomingOnly = result.upcomingOnly;
      _city = (result.city == null || result.city!.isEmpty) ? null : result.city;
      _state = (result.state == null || result.state!.isEmpty) ? null : result.state;
      _category = result.category;
    });
    _fetchCurrent();
  }

  Future<void> _refresh() async {
    final key = _key;
    await _fetchCurrent(force: true);
    if (!mounted) return;
    final err = context.read<AudaxEventsCacheProvider>().firstErrorFor(key);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $err')));
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

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<AudaxEventsCacheProvider>();
    final hasFilters =
        _upcomingOnly || _city != null || _state != null || _category != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audax Events'),
        actions: [
          IconButton(
            icon: Icon(hasFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'Filters',
            onPressed: _openFilters,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _MonthStepper(
            month: _selectedMonth,
            onPrev: () => _selectMonth(
              DateTime(_selectedMonth.year, _selectedMonth.month - 1),
            ),
            onNext: () => _selectMonth(
              DateTime(_selectedMonth.year, _selectedMonth.month + 1),
            ),
            onTap: _pickMonth,
          ),
        ),
      ),
      body: _buildBody(context, cache),
    );
  }

  Widget _buildBody(BuildContext context, AudaxEventsCacheProvider cache) {
    final key = _key;
    final events = cache.eventsFor(key);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    if (events == null && cache.isLoadingFirst(key)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (events == null && cache.firstErrorFor(key) != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cache.firstErrorFor(key)!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _fetchCurrent(force: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (events == null) {
      // Fetch hasn't started yet (e.g. this frame, before the post-frame
      // callback runs) — a brief transitional state.
      return const Center(child: CircularProgressIndicator());
    }
    if (events.isEmpty) {
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

    final showTrailingRow = cache.hasMore(key);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: events.length + (showTrailingRow ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= events.length) {
            final moreError = cache.moreErrorFor(key);
            if (moreError != null && !cache.isLoadingMore(key)) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      Text(moreError, style: Theme.of(context).textTheme.bodySmall),
                      TextButton(
                        onPressed: () => cache.fetchMore(key),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final event = events[index];
          return _AudaxEventCard(
            event: event,
            onTap: event.audaxPageUrl == null
                ? null
                : () => _openUrl(event.audaxPageUrl!, "Couldn't open the event page."),
            onOpenRouteMap: event.routeMapUrl == null
                ? null
                : () => _openUrl(event.routeMapUrl!, "Couldn't open the route map."),
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

/// Bottom sheet for the upcoming/city/state/category filters. Category chips
/// come from [AudaxEventsCacheProvider.filters] (fetched once per session
/// from `GET /audax-events/filters/`) rather than a hardcoded list, so new
/// categories the source calendar adds show up with no app update. Returns
/// the chosen [_AudaxFilters] via `Navigator.pop`, or `null` if dismissed.
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

  Widget _buildCategoryPicker(BuildContext context, AudaxEventsCacheProvider cache) {
    final categories = cache.filters?.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            if (cache.filtersLoading && categories == null) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (categories == null && cache.filtersError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  "Couldn't load categories: ${cache.filtersError}",
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.read<AudaxEventsCacheProvider>().fetchFilters(force: true),
                child: const Text('Retry'),
              ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Any'),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              // Same colour + label mapping as the cards' badges, so a
              // category looks the same wherever it appears.
              for (final c in categories ?? const <String>[])
                ChoiceChip(
                  label: Text(audaxCategoryLabel(c)),
                  selected: _category == c,
                  labelStyle: TextStyle(
                    color: audaxCategoryInk(context, audaxCategoryColor(c)),
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor:
                      audaxCategoryFill(context, audaxCategoryColor(c)),
                  selectedColor: audaxCategoryFill(context, audaxCategoryColor(c)),
                  side: BorderSide(
                    color: audaxCategoryColor(c).withValues(
                      alpha: _category == c ? 0.9 : 0.0,
                    ),
                    width: 1.5,
                  ),
                  onSelected: (_) => setState(() => _category = _category == c ? null : c),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<AudaxEventsCacheProvider>();
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
            _SuggestField(
              label: 'City',
              hint: 'e.g. Mumbai',
              controller: _cityController,
              options: cache.filters?.cities ?? const [],
            ),
            const SizedBox(height: 12),
            _SuggestField(
              label: 'State',
              hint: 'e.g. Maharashtra',
              controller: _stateController,
              options: cache.filters?.states ?? const [],
            ),
            const SizedBox(height: 16),
            _buildCategoryPicker(context, cache),
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

/// A text field that suggests known values as you type, without restricting
/// you to them. City/state are matched server-side as case-insensitive
/// *substrings*, so a typed value that isn't on the list is perfectly valid
/// (it just may return nothing) — hence a suggest field rather than a true
/// dropdown, which would rule that out.
///
/// [options] comes from `GET /audax-events/filters/`. If it's empty (the
/// filter list hasn't loaded, or failed), this degrades to an ordinary text
/// field with no suggestions, so filtering by hand still works offline.
class _SuggestField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final List<String> options;

  const _SuggestField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.options,
  });

  @override
  State<_SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<_SuggestField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The options overlay is sized to the field, which only LayoutBuilder can
    // tell us inside the sheet's padding.
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focusNode,
        optionsBuilder: (value) {
          if (widget.options.isEmpty) return const Iterable<String>.empty();
          final query = value.text.trim().toLowerCase();
          // Empty field → offer the whole list, so it reads as a dropdown.
          if (query.isEmpty) return widget.options;
          return widget.options.where((o) => o.toLowerCase().contains(query));
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            suffixIcon:
                widget.options.isEmpty ? null : const Icon(Icons.arrow_drop_down),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 220,
                  maxWidth: constraints.maxWidth,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(option),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One event row: category, club, date, start point, fee, registration
/// deadline, contact. Any missing field shows a placeholder rather than being
/// hidden, matching the API's guidance (only `audax_id`/`event_date` are
/// guaranteed non-null).
///
/// The category badge shares the header row with the club name rather than
/// taking a row of its own, so the card's height is unchanged. Its colour
/// also washes the card and tints the date, which is what gives the list its
/// at-a-glance, category-coded feel.
class _AudaxEventCard extends StatelessWidget {
  final AudaxEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onOpenRouteMap;

  const _AudaxEventCard({
    required this.event,
    required this.onTap,
    required this.onOpenRouteMap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final dateFmt = DateFormat('EEE, MMM d, yyyy');
    final feeFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final seed = audaxCategoryColor(event.category);
    final accent = audaxCategoryInk(context, seed);

    return Card(
      // A whisper of the category colour over the normal card surface — enough
      // to warm the list up and group like categories by eye, not enough to
      // fight the text on it.
      color: Color.alphaBlend(
        seed.withValues(alpha: dark ? 0.09 : 0.05),
        theme.colorScheme.surfaceContainerLow,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: seed.withValues(alpha: dark ? 0.32 : 0.22)),
      ),
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
                  AudaxCategoryBadge(category: event.category),
                  const SizedBox(width: 8),
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
                      color: accent,
                      onPressed: onOpenRouteMap,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // The date is the thing riders scan for, so it carries the
              // category colour and a heavier weight; the rest stays quiet.
              _InfoRow(
                icon: Icons.event_outlined,
                label: dateFmt.format(event.eventDate),
                color: accent,
                bold: true,
              ),
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
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.call_outlined,
                label: event.clubContactNumber ?? 'TBA',
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
  final Color? color;
  final bool bold;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 15, color: effective),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: effective,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
  }
}
