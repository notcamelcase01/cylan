import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/checklists_cache_provider.dart';

/// What the rider chose to attach when subscribing. Exactly one of the three
/// shapes the subscribe endpoint accepts: reuse an existing list ([existingId]),
/// create a fresh one ([newName] + [newItems]), or nothing (all null).
class ChecklistChoice {
  final int? existingId;
  final String? newName;
  final List<({String text, bool isMandatory})>? newItems;

  const ChecklistChoice.existing(this.existingId)
      : newName = null,
        newItems = null;

  const ChecklistChoice.fresh(this.newName, this.newItems) : existingId = null;

  const ChecklistChoice.none()
      : existingId = null,
        newName = null,
        newItems = null;
}

/// Asks the rider how to attach a checklist while subscribing. Returns their
/// [ChecklistChoice], or null if they backed out (so the caller can abort the
/// subscribe rather than joining with no checklist by accident).
Future<ChecklistChoice?> showChecklistPicker(BuildContext context) async {
  // Make sure the library is loaded so "reuse" has something to show.
  context.read<ChecklistsCacheProvider>().fetch();

  return showModalBottomSheet<ChecklistChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _PickerBody(),
  );
}

class _PickerBody extends StatelessWidget {
  const _PickerBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChecklistsCacheProvider>();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Attach a checklist',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Optional — pack list for this event. Reuse one and its ticked '
                'items stay in sync across events.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('No checklist'),
                onTap: () => Navigator.pop(
                    context, const ChecklistChoice.none()),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create a new one'),
                onTap: () async {
                  final made = await Navigator.of(context).push<ChecklistChoice>(
                    MaterialPageRoute(builder: (_) => const _NewChecklistScreen()),
                  );
                  if (made != null && context.mounted) {
                    Navigator.pop(context, made);
                  }
                },
              ),
              const Divider(),
              Text(
                'Reuse from your library',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              if (provider.loading && !provider.loaded)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.checklists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No saved checklists yet.'),
                )
              else
                for (final c in provider.checklists)
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: Text(c.name),
                    subtitle: Text('${c.itemCount} '
                        '${c.itemCount == 1 ? 'item' : 'items'}'),
                    onTap: () => Navigator.pop(
                        context, ChecklistChoice.existing(c.id)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds a brand-new checklist inline (name + items) at subscribe time,
/// returning it as a [ChecklistChoice.fresh]. The list is created server-side
/// as part of the subscribe call, not here.
class _NewChecklistScreen extends StatefulWidget {
  const _NewChecklistScreen();

  @override
  State<_NewChecklistScreen> createState() => _NewChecklistScreenState();
}

class _NewChecklistScreenState extends State<_NewChecklistScreen> {
  final _nameController = TextEditingController();
  final _items = <({String text, bool isMandatory})>[];
  final _itemController = TextEditingController();
  bool _nextMandatory = false;

  @override
  void dispose() {
    _nameController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _itemController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add((text: text, isMandatory: _nextMandatory));
      _itemController.clear();
      _nextMandatory = false;
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the checklist a name.')),
      );
      return;
    }
    Navigator.pop(
      context,
      ChecklistChoice.fresh(name, List.of(_items)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New checklist'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Done')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Checklist name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            Text('Items', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (int i = 0; i < _items.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.drag_indicator),
                title: Text(_items[i].text),
                subtitle:
                    _items[i].isMandatory ? const Text('Mandatory') : null,
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() => _items.removeAt(i)),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _itemController,
              decoration: InputDecoration(
                labelText: 'Add an item',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addItem,
                ),
              ),
              onSubmitted: (_) => _addItem(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark next item mandatory'),
              value: _nextMandatory,
              onChanged: (v) => setState(() => _nextMandatory = v),
            ),
          ],
        ),
      ),
    );
  }
}
