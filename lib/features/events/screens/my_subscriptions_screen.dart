import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/subscription.dart';
import 'event_detail_screen.dart';

/// The rider's own subscriptions (`GET /api/subscriptions/`), each with its
/// event and the checklist they attached. Tapping one opens the event; the
/// checklist's ticked-item progress is shown inline as a quick reference.
class MySubscriptionsScreen extends StatefulWidget {
  const MySubscriptionsScreen({super.key});

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen> {
  final _api = ApiClient.instance;
  final _scrollController = ScrollController();
  final _subs = <Subscription>[];
  String? _nextUrl;
  bool _loading = true;
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
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listMySubscriptions();
      if (!mounted) return;
      setState(() {
        _subs
          ..clear()
          ..addAll(page.results);
        _nextUrl = page.next;
        _hasFetched = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your subscriptions.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_nextUrl == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.listMySubscriptions(pageUrl: _nextUrl);
      if (!mounted) return;
      setState(() {
        _subs.addAll(page.results);
        _nextUrl = page.next;
      });
    } catch (_) {
      // Keep what's loaded; scrolling retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My subscriptions')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && !_hasFetched) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_hasFetched && _subs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            "You haven't subscribed to any events yet.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _subs.length + (_nextUrl != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= _subs.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _SubscriptionCard(subscription: _subs[i]);
        },
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final Subscription subscription;
  const _SubscriptionCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final event = subscription.event;
    final checklist = subscription.checklist;
    final done = checklist?.items.where((i) => i.isDone).length ?? 0;
    final total = checklist?.items.length ?? 0;

    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: event.id, initial: event),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.event_available_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(event.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEE, d MMM yyyy · h:mm a')
                          .format(event.startDate.toLocal()),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (checklist != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          total == 0
                              ? 'Checklist: ${checklist.name}'
                              : 'Checklist: ${checklist.name} · $done/$total done',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
