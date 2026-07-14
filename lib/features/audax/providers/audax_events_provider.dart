import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/audax_event.dart';

/// Drives the Audax events calendar screen. The server enforces a strict
/// one-month-per-request policy (see `GET /audax-events/`), so this provider
/// only ever holds a single selected month/year — never a range — and always
/// starts on the current month.
class AudaxEventsProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  List<AudaxEvent> _events = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool upcomingOnly = false;
  String? city;
  String? state;
  String? category;

  List<AudaxEvent> get events => _events;
  bool get hasMore => _nextUrl != null;
  DateTime get selectedMonth => _selectedMonth;

  Future<void> loadFirst() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listAudaxEvents(
        month: _selectedMonth.month,
        year: _selectedMonth.year,
        upcoming: upcomingOnly ? true : null,
        city: city,
        state: state,
        category: category,
      );
      _events = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || isLoadingMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _api.listAudaxEvents(pageUrl: _nextUrl);
      _events = [..._events, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();

  Future<void> setMonth(DateTime month) async {
    final normalized = DateTime(month.year, month.month);
    if (normalized == _selectedMonth) return;
    _selectedMonth = normalized;
    await loadFirst();
  }

  /// Applies the upcoming/city/state/category filters together as one fresh
  /// page-1 fetch, rather than one request per changed field.
  Future<void> applyFilters({
    required bool upcomingOnly,
    String? city,
    String? state,
    String? category,
  }) async {
    this.upcomingOnly = upcomingOnly;
    this.city = (city == null || city.isEmpty) ? null : city;
    this.state = (state == null || state.isEmpty) ? null : state;
    this.category = (category == null || category.isEmpty) ? null : category;
    await loadFirst();
  }
}
