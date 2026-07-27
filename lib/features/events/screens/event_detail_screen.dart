import 'package:cylan/features/events/screens/checklists_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/event.dart';
import '../../../core/models/event_comment.dart';
import '../../../core/models/checklist.dart';
import '../../auth/providers/auth_provider.dart';
import '../../rides/screens/ride_detail_screen.dart';
import '../../rides/providers/control_points_provider.dart';
import '../providers/checklists_cache_provider.dart';
import '../providers/event_detail_provider.dart';
import '../providers/events_cache_provider.dart';
import '../widgets/checklist_picker_sheet.dart';
import '../widgets/event_control_points_card.dart';
import '../widgets/event_status_chip.dart';
import 'create_edit_event_screen.dart';
import 'subscribers_screen.dart';

/// Full detail for one event: its facts, the subscribe/leave action for
/// viewers, and creator-only edit / delete / roster / waiver-document controls.
///
/// [initial] (the summary the list already held) is shown immediately while the
/// full detail loads, so opening feels instant.
class EventDetailScreen extends StatelessWidget {
  final int eventId;
  final Event? initial;
  const EventDetailScreen({super.key, required this.eventId, this.initial});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          EventDetailProvider(eventId: eventId, initial: initial)..load(),
      child: const _EventDetailView(),
    );
  }
}

class _EventDetailView extends StatefulWidget {
  const _EventDetailView();

  @override
  State<_EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends State<_EventDetailView> {
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isCreator(Event event) {
    final me = context.read<AuthProvider>().currentUser?.username;
    return me != null && me == event.creator;
  }

  Future<void> _openUrl(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) _snack("Couldn't open the link.");
  }

  Future<void> _edit(EventDetailProvider provider, Event event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateEditEventScreen(existing: event)),
    );
    // The edit form already invalidated the list cache; refresh this screen.
    if (mounted) provider.load();
  }

  Future<void> _delete(EventDetailProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text('This permanently deletes the event.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await provider.deleteEvent();
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    context.read<EventsCacheProvider>().invalidate();
    Navigator.of(context).pop();
  }

  Future<void> _subscribe(EventDetailProvider provider) async {
    final choice = await showChecklistPicker(context);
    if (choice == null || !mounted) return;
    final error = await provider.subscribe(
      checklistId: choice.existingId,
      newChecklistName: choice.newName,
      newChecklistItems: choice.newItems,
    );
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    context.read<EventsCacheProvider>().invalidate();
    // A new checklist created inline during subscribe is now in the library —
    // refresh so it shows on the My checklists screen and the picker.
    if (choice.newName != null) {
      context.read<ChecklistsCacheProvider>().fetch(force: true);
    }
    final event = provider.event;
    if (event != null && _isCreator(event)) {
      // The creator "joins" their own event only to attach a checklist.
      _snack('Checklist added to your event.');
      return;
    }
    _snack('Subscribed.');
  }

  Future<void> _toggleChecklistItem(
    EventDetailProvider provider,
    int itemId,
    bool isDone,
  ) async {
    final error = await provider.toggleChecklistItem(itemId, isDone);
    if (error != null) _snack(error);
  }

  Future<void> _unsubscribe(EventDetailProvider provider) async {
    final error = await provider.unsubscribe();
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    context.read<EventsCacheProvider>().invalidate();
    _snack('You left the event.');
  }

  Future<void> _uploadDocument(EventDetailProvider provider) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;
    final error = await provider.uploadDocument(path);
    if (!mounted) return;
    _snack(error ?? 'Document uploaded.');
  }

  Future<void> _viewDocument(EventDetailProvider provider) async {
    try {
      final url = await provider.documentUrl();
      await _openUrl(url);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _deleteDocument(EventDetailProvider provider) async {
    final error = await provider.deleteDocument();
    if (!mounted) return;
    _snack(error ?? 'Document removed.');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventDetailProvider>();
    final event = provider.event;

    return Scaffold(
      appBar: AppBar(
        title: Text(event?.name ?? 'Event'),
        actions: [
          if (event != null && event.isDetail && _isCreator(event)) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: provider.acting ? null : () => _edit(provider, event),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: provider.acting ? null : () => _delete(provider),
            ),
          ],
        ],
      ),
      body: _body(provider, event),
    );
  }

  Widget _body(EventDetailProvider provider, Event? event) {
    if (event == null) {
      if (provider.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.loadError ?? "Couldn't load this event.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: provider.load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return _EventBody(
      event: event,
      provider: provider,
      isCreator: _isCreator(event),
      myUsername: context.read<AuthProvider>().currentUser?.username,
      onSubscribe: () => _subscribe(provider),
      onUnsubscribe: () => _unsubscribe(provider),
      onOpenUrl: _openUrl,
      onOpenRide: event.ride == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                // Non-creators are viewing someone else's (now public) route
                // to preview it — open it read-only so the owner-only
                // smoothing control (which would 404) is hidden.
                builder: (_) => RideDetailScreen(
                  rideId: event.ride!.id,
                  readOnly: !_isCreator(event),
                  // Drawn read-only on the route map so the organiser's
                  // markers reach the rider whether or not they've imported
                  // them — and suppressed once they have, since the rider's
                  // own copies are then on the map instead.
                  eventControlPoints: event.defaultControlPoints,
                  eventPointsImported: context
                      .read<ControlPointsProvider>()
                      .hasImported(event.ride!.id, event.id),
                ),
              ),
            ),
      onViewSubscribers: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SubscribersScreen(eventId: event.id, eventName: event.name),
        ),
      ),
      onUploadDocument: () => _uploadDocument(provider),
      onViewDocument: () => _viewDocument(provider),
      onDeleteDocument: () => _deleteDocument(provider),
      onToggleChecklistItem: (itemId, isDone) =>
          _toggleChecklistItem(provider, itemId, isDone),
    );
  }
}

class _EventBody extends StatelessWidget {
  final Event event;
  final EventDetailProvider provider;
  final bool isCreator;

  /// The signed-in username, for deciding which comments carry a delete
  /// action (only your own).
  final String? myUsername;
  final VoidCallback onSubscribe;
  final VoidCallback onUnsubscribe;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback? onOpenRide;
  final VoidCallback onViewSubscribers;
  final VoidCallback onUploadDocument;
  final VoidCallback onViewDocument;
  final VoidCallback onDeleteDocument;
  final void Function(int itemId, bool isDone) onToggleChecklistItem;

  const _EventBody({
    required this.event,
    required this.provider,
    required this.isCreator,
    required this.myUsername,
    required this.onSubscribe,
    required this.onUnsubscribe,
    required this.onOpenUrl,
    required this.onOpenRide,
    required this.onViewSubscribers,
    required this.onUploadDocument,
    required this.onViewDocument,
    required this.onDeleteDocument,
    required this.onToggleChecklistItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = event.entryFee;
    final feeLabel = fee == 0 ? 'Free' : '${_trimFee(fee)} ${event.currency}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EventStatusChip(status: event.status),
            EventVisibilityChip(visibility: event.visibility),
          ],
        ),
        const SizedBox(height: 16),
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          label: DateFormat(
            'EEE, d MMM yyyy · h:mm a',
          ).format(event.startDate.toLocal()),
        ),
        _AssemblyRow(event: event, onOpenUrl: onOpenUrl),
        _InfoRow(icon: Icons.person_outline, label: 'By ${event.creator}'),
        _InfoRow(icon: Icons.payments_outlined, label: feeLabel),
        _InfoRow(
          icon: Icons.groups_outlined,
          label: event.maxSubscribers == null
              ? '${event.subscriberCount} subscribed'
              : '${event.subscriberCount} / ${event.maxSubscribers} subscribed'
                    '${event.isFull ? ' · full' : ''}',
        ),
        if ((event.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('About'),
          Text(event.description!),
        ],
        if (event.ride != null) ...[
          const SizedBox(height: 16),
          _SectionTitle('Route'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.directions_bike),
              title: Text(event.ride!.name),
              subtitle: Text(
                '${event.ride!.distanceKm.toStringAsFixed(1)} km'
                '${event.ride!.location != null && event.ride!.location!.isNotEmpty ? ' · ${event.ride!.location}' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenRide,
            ),
          ),
          // Offered, never applied on its own — the rider decides whether the
          // organiser's points join their copy of this route.
          if (event.defaultControlPoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            EventControlPointsCard(
              eventId: event.id,
              rideId: event.ride!.id,
              points: event.defaultControlPoints,
            ),
          ],
        ],
        // Its own section, not folded into the route card above: the like
        // targets the *ride* (`event.ride!.id`, via the same likeRide/unlikeRide
        // the ride detail screen uses), not the event — this is just where the
        // app surfaces it. Only shown once `rideLikesCount` has loaded (only
        // fetched for public events with a ride attached — see
        // `EventDetailProvider._loadRideLikeInfo`).
        if (event.ride != null &&
            event.isPublic == true &&
            provider.rideLikesCount != null) ...[
          const SizedBox(height: 16),
          _SectionTitle('Likes'),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  provider.rideIsLiked ? Icons.favorite : Icons.favorite_border,
                  color:
                      provider.rideIsLiked ? theme.colorScheme.primary : null,
                ),
                onPressed:
                    provider.likingRide ? null : () => provider.toggleRideLike(),
              ),
              Text('${provider.rideLikesCount}', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
        if ((event.externalLinks ?? const []).isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('Links'),
          for (final link in event.externalLinks!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onOpenUrl(link),
            ),
        ],
        if (event.isPublic == true) ...[
          const SizedBox(height: 16),
          _SectionTitle('Contact'),
          if ((event.contactNumber ?? '').isNotEmpty)
            _InfoRow(icon: Icons.phone_outlined, label: event.contactNumber!),
          if ((event.contactEmail ?? '').isNotEmpty)
            _InfoRow(icon: Icons.email_outlined, label: event.contactEmail!),
          const SizedBox(height: 16),
          _DocumentSection(
            event: event,
            provider: provider,
            isCreator: isCreator,
            onUpload: onUploadDocument,
            onView: onViewDocument,
            onDelete: onDeleteDocument,
          ),
        ],
        if ((event.remarksTos ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('Remarks / terms'),
          Text(
            event.remarksTos!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (provider.myChecklist != null) ...[
          const SizedBox(height: 16),
          _SectionTitle('Your checklist'),
          _ChecklistBlock(
            checklist: provider.myChecklist!,
            onToggle: onToggleChecklistItem,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChecklistsScreen()),
              );
            },
            icon: const Icon(Icons.checklist),
            label: const Text('View all checklists'),
          ),
        ],
        const SizedBox(height: 24),
        if (isCreator) ...[
          OutlinedButton.icon(
            onPressed: onViewSubscribers,
            icon: const Icon(Icons.groups_outlined),
            label: const Text('View subscribers'),
          ),
          const SizedBox(height: 12),
        ],
        // The creator can join their own event too — the only way to attach a
        // personal checklist to it in the current model.
        _SubscribeControl(
          event: event,
          provider: provider,
          isCreator: isCreator,
          onSubscribe: onSubscribe,
          onUnsubscribe: onUnsubscribe,
        ),
        // Comments close the page as the event's open discussion area —
        // public events only (the API rejects comments on private ones).
        if (event.isPublic == true) ...[
          const SizedBox(height: 24),
          _CommentsSection(provider: provider, myUsername: myUsername),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  static String _trimFee(double fee) =>
      fee == fee.roundToDouble() ? fee.round().toString() : fee.toString();
}

class _SubscribeControl extends StatelessWidget {
  final Event event;
  final EventDetailProvider provider;
  final bool isCreator;
  final VoidCallback onSubscribe;
  final VoidCallback onUnsubscribe;

  const _SubscribeControl({
    required this.event,
    required this.provider,
    required this.isCreator,
    required this.onSubscribe,
    required this.onUnsubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (event.status != 'PUBLISHED') {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isCreator
                    ? 'Publish this event to add your own checklist.'
                    : 'Subscriptions open once this event is published.',
              ),
            ),
          ],
        ),
      );
    }
    if (event.isSubscribed == true) {
      return OutlinedButton.icon(
        onPressed: provider.acting ? null : onUnsubscribe,
        icon: const Icon(Icons.event_busy_outlined),
        label: Text(isCreator ? 'Remove my checklist' : 'Leave event'),
      );
    }
    final full = event.isFull;
    return FilledButton.icon(
      onPressed: (provider.acting || full) ? null : onSubscribe,
      icon: provider.acting
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isCreator
                  ? Icons.playlist_add_check
                  : Icons.event_available_outlined,
            ),
      label: Text(
        full
            ? 'Event is full'
            : isCreator
            ? 'Add a checklist for yourself'
            : 'Subscribe',
      ),
    );
  }
}

class _DocumentSection extends StatelessWidget {
  final Event event;
  final EventDetailProvider provider;
  final bool isCreator;
  final VoidCallback onUpload;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const _DocumentSection({
    required this.event,
    required this.provider,
    required this.isCreator,
    required this.onUpload,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasDoc = event.hasDocument;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Waiver document'),
        if (!hasDoc && !isCreator)
          const Text('No document attached.')
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasDoc ? 'A waiver PDF is attached.' : 'No document yet.',
                    ),
                  ),
                  if (provider.acting)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    if (hasDoc)
                      TextButton(onPressed: onView, child: const Text('View')),
                    if (isCreator)
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'upload') onUpload();
                          if (v == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'upload',
                            child: Text(hasDoc ? 'Replace' : 'Upload PDF'),
                          ),
                          if (hasDoc)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Remove'),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AssemblyRow extends StatelessWidget {
  final Event event;
  final Future<void> Function(String url) onOpenUrl;
  const _AssemblyRow({required this.event, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final mapUrl = event.assemblyPointMapUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.place_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(event.assemblyPoint)),
          if (mapUrl != null)
            TextButton.icon(
              onPressed: () => onOpenUrl(mapUrl),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Map'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ChecklistBlock extends StatelessWidget {
  final Checklist checklist;
  final void Function(int itemId, bool isDone) onToggle;
  const _ChecklistBlock({required this.checklist, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final done = checklist.items.where((i) => i.isDone).length;
    final total = checklist.items.length;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.checklist, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    checklist.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (total > 0)
                  Text(
                    '$done/$total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('This checklist has no items.'),
            )
          else
            for (final item in checklist.items)
              CheckboxListTile(
                value: item.isDone,
                onChanged: (v) => onToggle(item.id, v ?? false),
                title: Text(item.text),
                subtitle: item.isMandatory ? const Text('Mandatory') : null,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
        ],
      ),
    );
  }
}

/// The event's flat comment thread (public events only): the loaded comments
/// oldest→newest, a "Show more" pager, and a composer at the bottom. Anyone
/// viewing the event can post; each rider can delete only their own.
class _CommentsSection extends StatefulWidget {
  final EventDetailProvider provider;
  final String? myUsername;
  const _CommentsSection({required this.provider, required this.myUsername});

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final error = await widget.provider.postComment(text);
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    _controller.clear();
  }

  Future<void> _delete(EventComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This permanently deletes your comment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await widget.provider.deleteComment(comment.id);
    if (error != null) _snack(error);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final comments = provider.comments;
    final count = provider.commentCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(count > 0 ? 'Comments ($count)' : 'Comments'),
        if (comments.isEmpty && provider.commentsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (comments.isEmpty && provider.commentsError != null)
          Row(
            children: [
              Expanded(child: Text(provider.commentsError!)),
              TextButton(
                onPressed: provider.loadComments,
                child: const Text('Try again'),
              ),
            ],
          )
        else if (comments.isEmpty)
          Text(
            'No comments yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          for (final comment in comments)
            _CommentTile(
              comment: comment,
              isMine: comment.user == widget.myUsername,
              onDelete: () => _delete(comment),
            ),
          if (provider.hasMoreComments)
            provider.commentsLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: provider.loadMoreComments,
                    child: const Text('Show more comments'),
                  ),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a comment…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Post comment',
              onPressed: provider.postingComment ? null : _post,
              icon: provider.postingComment
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final EventComment comment;
  final bool isMine;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.isMine,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.user,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat(
                        'd MMM, h:mm a',
                      ).format(comment.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text),
              ],
            ),
          ),
          if (isMine)
            IconButton(
              tooltip: 'Delete comment',
              icon: const Icon(Icons.delete_outline, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
