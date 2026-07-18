import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/checklist.dart';

/// App-level, session cache for the rider's reusable checklist library. Unlike
/// [EventsCacheProvider] there's no per-key pagination: the library is personal
/// and small, so it's held as a single list, fetched whole once per session
/// (paging through server-side via [ApiClient.fetchAllChecklists]).
///
/// Registered above the navigator so the "pick a checklist" sheet (at subscribe
/// time) and the standalone library screen share one live copy — a rename or an
/// item toggle in one is reflected in the other. Mutations write through to the
/// API first, then update the in-memory list so the change survives without a
/// refetch.
class ChecklistsCacheProvider extends ChangeNotifier {
  ChecklistsCacheProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  List<Checklist> _checklists = [];
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  List<Checklist> get checklists => List.unmodifiable(_checklists);
  bool get loaded => _loaded;
  bool get loading => _loading;
  String? get error => _error;

  /// Fetches the whole library once per session; a no-op once loaded or while
  /// loading, so it's safe to call every time a consumer opens. Pass [force]
  /// to refetch (e.g. pull-to-refresh).
  Future<void> fetch({bool force = false}) async {
    if (!force && (_loaded || _loading)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _checklists = await _api.fetchAllChecklists();
      _loaded = true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = "Couldn't load your checklists.";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Checklist? byId(int id) {
    for (final c in _checklists) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Creates a checklist (optionally seeded with items), prepends it to the
  /// cache, and returns it. Rethrows [ApiException] so the caller can show the
  /// failure inline.
  Future<Checklist> create(
    String name, {
    List<({String text, bool isMandatory})>? items,
  }) async {
    final created = await _api.createChecklist(name, items: items);
    _checklists = [created, ..._checklists];
    notifyListeners();
    return created;
  }

  Future<void> rename(int id, String name) async {
    final updated = await _api.updateChecklist(id, name: name);
    _replace(updated);
  }

  Future<void> remove(int id) async {
    await _api.deleteChecklist(id);
    _checklists = _checklists.where((c) => c.id != id).toList();
    notifyListeners();
  }

  Future<void> addItem(
    int checklistId, {
    required String text,
    bool isMandatory = false,
  }) async {
    final item = await _api.addChecklistItem(
      checklistId,
      text: text,
      isMandatory: isMandatory,
    );
    final target = byId(checklistId);
    if (target != null) {
      _replace(target.withItems([...target.items, item]));
    }
  }

  /// Toggles/edits an item and reflects the server's returned value in the
  /// cached checklist it belongs to.
  Future<void> updateItem(
    int checklistId,
    int itemId, {
    String? text,
    bool? isMandatory,
    bool? isDone,
  }) async {
    final updated = await _api.updateChecklistItem(
      itemId,
      text: text,
      isMandatory: isMandatory,
      isDone: isDone,
    );
    final target = byId(checklistId);
    if (target != null) {
      _replace(target.withItems([
        for (final it in target.items) it.id == itemId ? updated : it,
      ]));
    }
  }

  Future<void> removeItem(int checklistId, int itemId) async {
    await _api.deleteChecklistItem(itemId);
    final target = byId(checklistId);
    if (target != null) {
      _replace(target.withItems(
        target.items.where((it) => it.id != itemId).toList(),
      ));
    }
  }

  void _replace(Checklist updated) {
    _checklists = [
      for (final c in _checklists) c.id == updated.id ? updated : c,
    ];
    notifyListeners();
  }
}
