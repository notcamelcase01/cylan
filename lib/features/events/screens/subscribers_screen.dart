import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/subscription.dart';

/// The creator-only roster for one event. Loads once from
/// `GET /events/{id}/subscribers/`; the server returns the whole list (not
/// paginated) with the cap context, so this is a plain fetch-and-show.
class SubscribersScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  const SubscribersScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends State<SubscribersScreen> {
  EventRoster? _roster;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roster =
          await ApiClient.instance.getEventSubscribers(widget.eventId);
      if (!mounted) return;
      setState(() => _roster = roster);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load the roster.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscribers')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    final roster = _roster!;
    final cap = roster.maxSubscribers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.groups_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                cap == null
                    ? '${roster.count} joined'
                    : '${roster.count} / $cap joined',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (roster.subscribers.isEmpty)
          const Expanded(
            child: Center(child: Text('No one has subscribed yet.')),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: roster.subscribers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final s = roster.subscribers[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        s.username.isNotEmpty
                            ? s.username[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(s.username,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Joined ${DateFormat('d MMM yyyy').format(s.joinedAt.toLocal())}',
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
