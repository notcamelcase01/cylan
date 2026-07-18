import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/event.dart';
import '../providers/events_cache_provider.dart';
import '../widgets/event_status_chip.dart';
import 'checklists_screen.dart';
import 'create_edit_event_screen.dart';
import 'event_detail_screen.dart';
import 'my_subscriptions_screen.dart';

/// The Events tab: browse events visible to the rider (their own of any status,
/// plus everyone's public+published), search and filter them, open one, or
/// create a new one. Paginated results are cached per filter combination in the
/// app-level [EventsCacheProvider], so switching tabs and back doesn't refetch.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  static const _searchDebounce = Duration(milliseconds: 350);
  Timer? _searchTimer;

  bool _mine = false;
  bool _upcomingOnly = false;
  String? _status;
  String _query = '';

  String get _key => EventsCacheProvider.keyFor(
        mine: _mine,
        status: _status,
        q: _query,
        upcomingOnly: _upcomingOnly,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
        context.read<EventsCacheProvider>().fetchMore(_key);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _fetch({bool force = false}) {
    context.read<EventsCacheProvider>().fetchFirst(
          _key,
          mine: _mine,
          status: _status,
          q: _query,
          upcomingOnly: _upcomingOnly,
          force: force,
        );
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      setState(() => _query = value.trim());
      _fetch();
    });
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Event>(
      MaterialPageRoute(builder: (_) => const CreateEditEventScreen()),
    );
    if (created == null || !mounted) return;
    // The create form invalidated the cache; refetch the current view and jump
    // to the new event.
    _fetch();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EventDetailScreen(eventId: created.id, initial: created),
      ),
    );
  }

  void _openEvent(Event event) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) =>
              EventDetailScreen(eventId: event.id, initial: event),
        ))
        // Coming back from detail: a subscribe/leave/edit there may have
        // changed this list, and the cache was invalidated — refetch.
        .then((_) {
      if (mounted) _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<EventsCacheProvider>();
    final events = cache.eventsFor(_key);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'checklists':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ChecklistsScreen()));
                case 'subscriptions':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MySubscriptionsScreen()));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'subscriptions',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_available_outlined),
                  title: Text('My subscriptions'),
                ),
              ),
              PopupMenuItem(
                value: 'checklists',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.checklist),
                  title: Text('My checklists'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: Column(
        children: [
          _FilterBar(
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            mine: _mine,
            upcomingOnly: _upcomingOnly,
            status: _status,
            onMineChanged: (v) {
              setState(() => _mine = v);
              _fetch();
            },
            onUpcomingChanged: (v) {
              setState(() => _upcomingOnly = v);
              _fetch();
            },
            onStatusChanged: (v) {
              setState(() => _status = v);
              _fetch();
            },
          ),
          Expanded(child: _list(cache, events)),
        ],
      ),
    );
  }

  Widget _list(EventsCacheProvider cache, List<Event>? events) {
    final firstError = cache.firstErrorFor(_key);

    if (events == null) {
      if (cache.isLoadingFirst(_key)) {
        return const Center(child: CircularProgressIndicator());
      }
      if (firstError != null) {
        return _ErrorRetry(message: firstError, onRetry: () => _fetch(force: true));
      }
      return const SizedBox.shrink();
    }

    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _fetch(force: true),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No events match. Create one with the button below.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final loadingMore = cache.isLoadingMore(_key);
    return RefreshIndicator(
      onRefresh: () async => _fetch(force: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: events.length + (loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= events.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _EventCard(
            event: events[i],
            onTap: () => _openEvent(events[i]),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool mine;
  final bool upcomingOnly;
  final String? status;
  final ValueChanged<bool> onMineChanged;
  final ValueChanged<bool> onUpcomingChanged;
  final ValueChanged<String?> onStatusChanged;

  const _FilterBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.mine,
    required this.upcomingOnly,
    required this.status,
    required this.onMineChanged,
    required this.onUpcomingChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search events',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              FilterChip(
                label: const Text('Mine'),
                selected: mine,
                onSelected: onMineChanged,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Upcoming'),
                selected: upcomingOnly,
                onSelected: onUpcomingChanged,
              ),
              const SizedBox(width: 8),
              for (final s in kEventStatuses) ...[
                FilterChip(
                  label: Text(_statusLabel(s)),
                  selected: status == s,
                  onSelected: (sel) => onStatusChanged(sel ? s : null),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'DRAFT' => 'Draft',
        'PUBLISHED' => 'Published',
        'CANCELLED' => 'Cancelled',
        'COMPLETED' => 'Completed',
        _ => s,
      };
}

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feeLabel = event.entryFee == 0
        ? 'Free'
        : '${_trimFee(event.entryFee)} ${event.currency}';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EventStatusChip(status: event.status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _meta(theme, Icons.calendar_today_outlined,
                      DateFormat('d MMM yyyy · h:mm a')
                          .format(event.startDate.toLocal())),
                  _meta(theme, Icons.person_outline, event.creator),
                  _meta(theme, Icons.payments_outlined, feeLabel),
                  _meta(
                    theme,
                    Icons.groups_outlined,
                    event.maxSubscribers == null
                        ? '${event.subscriberCount}'
                        : '${event.subscriberCount}/${event.maxSubscribers}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String label) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }

  static String _trimFee(double fee) =>
      fee == fee.roundToDouble() ? fee.round().toString() : fee.toString();
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
