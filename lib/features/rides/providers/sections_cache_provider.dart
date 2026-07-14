import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride_section.dart';

/// App-level cache of a ride's notable climbs/descents, keyed by ride id.
///
/// Sections are computed once at import and stable across smoothing changes, so
/// they only ever need fetching once per ride. Registered once above the
/// navigator (see `main.dart`) so a fetch made on the ride detail survives
/// navigating into a section and back, and so the offline-save flow can read
/// the already-fetched sections without a second request.
class SectionsCacheProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  final Map<int, List<RideSection>> _sections = {};
  final Map<int, bool> _loading = {};
  final Map<int, String?> _errors = {};

  List<RideSection>? sectionsFor(int rideId) => _sections[rideId];
  bool isLoading(int rideId) => _loading[rideId] ?? false;
  String? errorFor(int rideId) => _errors[rideId];
  bool hasFetched(int rideId) => _sections.containsKey(rideId);

  /// Fetches (once) the ride's notable sections. A no-op if already fetched or
  /// a fetch is in flight, so it's safe to call every time the detail opens.
  Future<void> fetch(int rideId, {bool force = false}) async {
    if (!force && (hasFetched(rideId) || isLoading(rideId))) return;
    _loading[rideId] = true;
    _errors[rideId] = null;
    notifyListeners();
    try {
      _sections[rideId] = await _api.getSections(rideId);
    } on ApiException catch (e) {
      _errors[rideId] = e.message;
    } finally {
      _loading[rideId] = false;
      notifyListeners();
    }
  }
}
