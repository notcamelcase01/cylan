/// A single item on a [Checklist]. [isMandatory] is only the owner's own
/// labelling — there's no cross-user enforcement — and [isDone] is shared
/// across every event the parent checklist is attached to (checklists are
/// reused by reference, not copied).
class ChecklistItem {
  final int id;
  final String text;
  final bool isMandatory;
  final bool isDone;

  const ChecklistItem({
    required this.id,
    required this.text,
    required this.isMandatory,
    required this.isDone,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as int,
        text: json['text'] as String,
        isMandatory: json['is_mandatory'] as bool? ?? false,
        isDone: json['is_done'] as bool? ?? false,
      );

  ChecklistItem copyWith({String? text, bool? isMandatory, bool? isDone}) =>
      ChecklistItem(
        id: id,
        text: text ?? this.text,
        isMandatory: isMandatory ?? this.isMandatory,
        isDone: isDone ?? this.isDone,
      );
}

/// A user-owned, reusable checklist (`/api/checklists/`). It belongs to the
/// rider's personal library, not to any one event — the same checklist can be
/// attached to any number of subscriptions, and ticking an item off is visible
/// on all of them (same underlying row).
class Checklist {
  final int id;
  final String name;
  final DateTime createdAt;

  /// The items, present when the checklist is fetched with its detail (list
  /// and detail endpoints both embed them); empty if it has none.
  final List<ChecklistItem> items;
  final int itemCount;

  const Checklist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
    required this.itemCount,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return Checklist(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: items,
      // item_count is a server field, but fall back to the embedded list's
      // length if a payload ever omits it.
      itemCount: json['item_count'] as int? ?? items.length,
    );
  }

  /// Returns a copy with a new [items] list, keeping [itemCount] in sync with
  /// it — used when the cache mutates a single item locally after the server
  /// confirms the change.
  Checklist withItems(List<ChecklistItem> newItems) => Checklist(
        id: id,
        name: name,
        createdAt: createdAt,
        items: newItems,
        itemCount: newItems.length,
      );

  Checklist copyWith({String? name}) => Checklist(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        items: items,
        itemCount: itemCount,
      );
}

class ChecklistPage {
  final int count;
  final String? next;
  final String? previous;
  final List<Checklist> results;

  ChecklistPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory ChecklistPage.fromJson(Map<String, dynamic> json) => ChecklistPage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => Checklist.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
