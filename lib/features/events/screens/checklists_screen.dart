import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/checklist.dart';
import '../providers/checklists_cache_provider.dart';

/// The rider's reusable checklist library — create, rename, delete lists, and
/// add / tick off / remove items. Backed by the shared
/// [ChecklistsCacheProvider], so any change here is live in the "pick a
/// checklist" sheet at subscribe time too. Ticking an item is shared across
/// every event a checklist is attached to (they're reused by reference).
class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChecklistsCacheProvider>().fetch();
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong.')),
        );
      }
    }
  }

  Future<void> _createChecklist() async {
    final name = await _promptText(
      title: 'New checklist',
      label: 'Name',
    );
    if (name == null || name.isEmpty) return;
    await _guard(
        () => context.read<ChecklistsCacheProvider>().create(name));
  }

  Future<void> _renameChecklist(Checklist checklist) async {
    final name = await _promptText(
      title: 'Rename checklist',
      label: 'Name',
      initial: checklist.name,
    );
    if (name == null || name.isEmpty || name == checklist.name) return;
    await _guard(() =>
        context.read<ChecklistsCacheProvider>().rename(checklist.id, name));
  }

  Future<void> _deleteChecklist(Checklist checklist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete checklist?'),
        content: Text('"${checklist.name}" will be removed from your library '
            'and detached from any events using it.'),
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
    if (confirmed != true) return;
    await _guard(
        () => context.read<ChecklistsCacheProvider>().remove(checklist.id));
  }

  Future<void> _addItem(Checklist checklist) async {
    final text = await _promptText(title: 'Add item', label: 'Item');
    if (text == null || text.isEmpty) return;
    await _guard(() => context
        .read<ChecklistsCacheProvider>()
        .addItem(checklist.id, text: text));
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChecklistsCacheProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('My checklists')),
      floatingActionButton: FloatingActionButton.extended(
        // Own tag so it never collides with (or "flies" from) the tab FABs
        // still mounted underneath this pushed route.
        heroTag: 'checklists_fab',
        onPressed: _createChecklist,
        icon: const Icon(Icons.add),
        label: const Text('New checklist'),
      ),
      body: _body(provider),
    );
  }

  Widget _body(ChecklistsCacheProvider provider) {
    if (provider.loading && !provider.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && !provider.loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => provider.fetch(force: true),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final checklists = provider.checklists;
    if (checklists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No checklists yet. Create one to reuse across events.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => provider.fetch(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: checklists.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final checklist = checklists[i];
          return _ChecklistCard(
            checklist: checklist,
            onRename: () => _renameChecklist(checklist),
            onDelete: () => _deleteChecklist(checklist),
            onAddItem: () => _addItem(checklist),
            onToggleItem: (item, value) => _guard(() => context
                .read<ChecklistsCacheProvider>()
                .updateItem(checklist.id, item.id, isDone: value)),
            onDeleteItem: (item) => _guard(() => context
                .read<ChecklistsCacheProvider>()
                .removeItem(checklist.id, item.id)),
          );
        },
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final Checklist checklist;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddItem;
  final void Function(ChecklistItem item, bool value) onToggleItem;
  final void Function(ChecklistItem item) onDeleteItem;

  const _ChecklistCard({
    required this.checklist,
    required this.onRename,
    required this.onDelete,
    required this.onAddItem,
    required this.onToggleItem,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(checklist.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${checklist.itemCount} '
              '${checklist.itemCount == 1 ? 'item' : 'items'}'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') onRename();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final item in checklist.items)
              CheckboxListTile(
                value: item.isDone,
                onChanged: (v) => onToggleItem(item, v ?? false),
                title: Text(item.text),
                subtitle: item.isMandatory
                    ? const Text('Mandatory')
                    : null,
                secondary: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Remove item',
                  onPressed: () => onDeleteItem(item),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add item'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
