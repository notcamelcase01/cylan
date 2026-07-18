import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/audax_event.dart';
import '../models/checklist.dart';
import '../models/event.dart';
import '../models/ride.dart';
import '../models/ride_section.dart';
import '../models/route_suggestion.dart';
import '../models/strava_route.dart';
import '../models/subscription.dart';
import '../models/user.dart';
import '../models/weather_point.dart';
import 'api_exception.dart';

/// The one place the app talks to the network. Everything above this line
/// deals in models and [ApiException] and knows nothing about HTTP — Dio is an
/// implementation detail that stops here, which is why the progress callback
/// on [uploadRide] is a plain function type rather than Dio's `ProgressCallback`.
class ApiClient {
  ApiClient._({HttpClientAdapter? adapter}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
      // Status codes are turned into messages by [_throwForResponse], which
      // needs the decoded error body to do it — so let every response through
      // rather than letting Dio throw before we've read it.
      validateStatus: (_) => true,
    ));
    if (adapter != null) _dio.httpClientAdapter = adapter;
    // Auth as an interceptor rather than at each call site: it's one rule
    // ("send the token if we have one"), and 25 endpoints shouldn't each have
    // to remember it.
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        if (options.extra[_anonymous] != true) {
          final t = await token;
          if (t != null) options.headers['Authorization'] = 'Token $t';
        }
        handler.next(options);
      }),
    );
  }

  static final ApiClient instance = ApiClient._();

  /// A client whose transport answers from [adapter] instead of the network,
  /// wired up otherwise exactly like [instance] — same timeouts, same auth
  /// interceptor, same status handling — so a test exercises the real thing.
  /// Separate from [instance] so cases can't leak into each other.
  @visibleForTesting
  factory ApiClient.forTests(HttpClientAdapter adapter) =>
      ApiClient._(adapter: adapter);

  static const String baseUrl = 'https://cyclingngin.duckdns.org/api';

  // Ordinary requests should never hang indefinitely on a bad connection
  // (captive portal, dead wifi); uploads get longer since a 10 MB file can
  // take a while on a slow link.
  static const _requestTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 90);

  /// Marks a request that must go out with **no** `Authorization` header.
  ///
  /// Not merely an optimisation: DRF authenticates before it checks
  /// permissions, so presenting a stale token to a public endpoint (the audax
  /// calendar) turns a perfectly good 200 into a 401. Login/signup are where a
  /// token is obtained, not presented.
  static const _anonymous = 'anonymous';
  static Options get _anonymousOptions =>
      Options(extra: const {_anonymous: true});

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  late final Dio _dio;
  String? _token;

  /// The stored token, or null when there isn't one — *including* when the
  /// keystore refuses to hand it over.
  ///
  /// Secure storage runs on real devices, and real devices fail: an Android
  /// keystore restored from backup can no longer decrypt its own entries, and
  /// iOS declines keychain access before first unlock. Letting that escape
  /// strands every caller — [AuthProvider.tryAutoLogin] in particular never
  /// reaches an assignment to `status`, leaving the gate on its spinner with no
  /// retry and no way out but reinstalling.
  ///
  /// A token we can't read is, functionally, no token: answering null lands the
  /// rider on the login screen, where signing in writes a fresh one.
  Future<String?> get token async {
    if (_token != null) return _token;
    try {
      return _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Keeps [value] for this session and tries to persist it. Persistence is
  /// best-effort for the reasons in [token]: a token we can't write just means
  /// this session won't survive a restart, which is no reason to fail the
  /// login that just succeeded.
  Future<void> _storeToken(String value) async {
    _token = value;
    try {
      await _storage.write(key: _tokenKey, value: value);
    } catch (_) {
      // Nothing to tell the rider — they are logged in.
    }
  }

  Future<bool> get isLoggedIn async => (await token) != null;

  /// Runs a Dio call and converts any transport-level failure (no connection,
  /// DNS failure, dropped socket, timeout) into an [ApiException]. Without
  /// this, those errors arrive as [DioException] and slip past every
  /// `on ApiException catch` in the app, leaving a screen stuck with a stopped
  /// spinner and no message shown.
  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  /// Note every branch leaves [ApiException.statusCode] null — by definition
  /// none of these reached the server, which is exactly what callers read that
  /// field to find out.
  ApiException _asApiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        // An upload is the only thing that sends a FormData body, and it gets
        // its own wording to match its much longer budget.
        return ApiException(e.requestOptions.data is FormData
            ? 'The upload timed out. Check your connection and try again.'
            : 'The request timed out. Check your connection and try again.');
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return ApiException(
            'Could not reach the server. Check your connection and try again.');
      case DioExceptionType.cancel:
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        if (e.error is SocketException) {
          return ApiException(
              'Could not reach the server. Check your connection and try again.');
        }
        return ApiException('Something went wrong. Please try again.');
    }
  }

  /// Throws an [ApiException] built from the body unless the response carries
  /// [expected].
  void _ensure(Response<dynamic> response, int expected) {
    if (response.statusCode != expected) _throwForResponse(response);
  }

  Never _throwForResponse(Response<dynamic> response) {
    final status = response.statusCode;
    final data = response.data;
    // A non-JSON body means something upstream broke (a proxy's HTML error
    // page, say) — there's no field detail to mine, so report the bare code.
    if (data is! Map) {
      throw ApiException('Unexpected server error ($status).',
          statusCode: status);
    }
    final decoded = data.cast<String, dynamic>();
    if (decoded.containsKey('detail')) {
      throw ApiException(decoded['detail'].toString(), statusCode: status);
    }
    final fieldErrors = <String, List<String>>{};
    decoded.forEach((key, value) {
      if (value is List) {
        fieldErrors[key] = value.map((e) => e.toString()).toList();
      }
    });
    final message = fieldErrors.values.expand((v) => v).join('\n');
    throw ApiException(
      message.isEmpty ? 'Request failed ($status).' : message,
      fieldErrors: fieldErrors,
      statusCode: status,
    );
  }

  /// Whether the API is reachable right now. Any HTTP response counts — this
  /// tests the path to the server, not the health of an endpoint — so only a
  /// transport failure or [timeout] answers false.
  Future<bool> reachable({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      await _dio.head<void>(baseUrl, options: _anonymousOptions).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> login(String username, String password) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/auth/token/',
          data: {'username': username, 'password': password},
          options: _anonymousOptions,
        ));
    _ensure(response, 200);
    final t = (response.data as Map<String, dynamic>)['token'] as String;
    await _storeToken(t);
    return t;
  }

  /// Creates an account and stores the returned token. `name`/`email` are
  /// optional and can be filled in later via [updateProfile].
  Future<AppUser> signup({
    required String username,
    required String password,
    String? name,
    String? email,
  }) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/auth/signup/',
          data: {
            'username': username,
            'password': password,
            if (name != null && name.isNotEmpty) 'name': name,
            if (email != null && email.isNotEmpty) 'email': email,
          },
          options: _anonymousOptions,
        ));
    _ensure(response, 201);
    final decoded = response.data as Map<String, dynamic>;
    await _storeToken(decoded['token'] as String);
    return AppUser.fromJson(decoded);
  }

  /// Drops the token from memory and, best-effort, from disk.
  ///
  /// A delete that throws must not strand the caller mid-logout (the profile
  /// screen awaits this before navigating), so the failure is swallowed — at
  /// the cost that a keystore this broken may still hold the old entry. It
  /// can't be presented, though: [token] answers null when a read fails, which
  /// is the same storage that just failed to delete.
  Future<void> logout() async {
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // See above — nothing useful to do, and nothing worth blocking on.
    }
  }

  Future<AppUser> me() async {
    final response = await _send(() => _dio.get<dynamic>('/auth/me/'));
    _ensure(response, 200);
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates the rider's optional profile fields (name / email).
  Future<AppUser> updateProfile({String? name, String? email}) async {
    final response = await _send(() => _dio.patch<dynamic>(
          '/auth/me/',
          data: {'name': ?name, 'email': ?email},
        ));
    _ensure(response, 200);
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  /// [pageUrl] is an absolute `next`/`previous` URL from a prior page; Dio
  /// leaves an absolute path alone rather than pasting it onto [baseUrl].
  Future<RidePage> listRides({String? pageUrl}) async {
    final response = await _send(() => _dio.get<dynamic>(pageUrl ?? '/rides/'));
    _ensure(response, 200);
    return RidePage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Ride> getRide(int id) async {
    final response = await _send(() => _dio.get<dynamic>('/rides/$id/'));
    _ensure(response, 200);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads a route file.
  ///
  /// [onProgress] reports `(bytesSent, totalBytes)` as it goes, so a rider
  /// pushing a multi-megabyte ride over cellular can watch it move rather than
  /// stare at a spinner for up to [_uploadTimeout]. `totalBytes` is -1 when the
  /// length isn't known up front.
  Future<Ride> uploadRide({
    required String filePath,
    String? name,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      if (name != null && name.isNotEmpty) 'name': name,
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _send(() => _dio.post<dynamic>(
          '/rides/',
          data: formData,
          options: Options(
            sendTimeout: _uploadTimeout,
            receiveTimeout: _uploadTimeout,
          ),
          onSendProgress: onProgress,
        ));
    _ensure(response, 201);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  /// Imports a ride from a Google Maps directions link (the checkpoints a
  /// rider plotted) rather than a file. India only — the server rejects
  /// anything else with a displayable [ApiException]. Synchronous, like
  /// [uploadRide]: resolving the link, routing, and per-point elevation
  /// lookups can take a few seconds, hence the same longer timeout.
  Future<Ride> importFromGoogleMaps({required String url, String? name}) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/rides/google-maps/',
          data: {
            'url': url,
            if (name != null && name.isNotEmpty) 'name': name,
          },
          options: Options(
            sendTimeout: _uploadTimeout,
            receiveTimeout: _uploadTimeout,
          ),
        ));
    _ensure(response, 201);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  /// Copies a curated suggestion (a ride you don't own) into your own library,
  /// returning your new [Ride]. Only completed suggestions can be forked; the
  /// copy is an ordinary ride you can then attach to an event, exactly like an
  /// uploaded one. `400` if it isn't a completed suggestion or you already own
  /// it.
  Future<Ride> forkRide(int id) async {
    final response = await _send(() => _dio.post<dynamic>('/rides/$id/fork/'));
    _ensure(response, 201);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Ride> renameRide(int id, String name) async {
    final response = await _send(
        () => _dio.patch<dynamic>('/rides/$id/', data: {'name': name}));
    _ensure(response, 200);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  /// Recomputes the ride's elevation/gradient profile with a new smoothing
  /// window (50-500 m): wider flattens more GPS noise, narrower preserves
  /// more detail (and more noise).
  Future<Ride> setSmoothing(int id, int windowM) async {
    final response = await _send(() =>
        _dio.post<dynamic>('/rides/$id/smoothing/', data: {'window_m': windowM}));
    _ensure(response, 200);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRide(int id) async {
    final response = await _send(() => _dio.delete<dynamic>('/rides/$id/'));
    _ensure(response, 204);
  }

  Future<List<WeatherPoint>> getWeather(
    int id, {
    required DateTime start,
    required DateTime finish,
  }) async {
    String iso(DateTime dt) => dt.toIso8601String().split('.').first;
    final response = await _send(() => _dio.get<dynamic>(
          '/rides/$id/weather/',
          queryParameters: {'start': iso(start), 'finish': iso(finish)},
        ));
    _ensure(response, 200);
    return (response.data as List<dynamic>)
        .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The ride's notable climbs and descents, detected and classified on the
  /// server. Each is self-contained (carries its own coordinates); the app
  /// only displays them. Returns an empty list for a ride with none.
  Future<List<RideSection>> getSections(int id) async {
    final response =
        await _send(() => _dio.get<dynamic>('/rides/$id/sections/'));
    _ensure(response, 200);
    final decoded = response.data as Map<String, dynamic>;
    return (decoded['sections'] as List<dynamic>? ?? [])
        .map((e) => RideSection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Strava ----------------------------------------------------------------

  /// Returns the browser consent URL to open. Its signed `state` carries the
  /// user id so the web callback can link Strava without a web session.
  Future<String> stravaAuthorizeUrl() async {
    final response = await _send(() => _dio.post<dynamic>('/strava/authorize/'));
    _ensure(response, 200);
    return (response.data as Map<String, dynamic>)['authorize_url'] as String;
  }

  Future<bool> stravaConnected() async {
    final response = await _send(() => _dio.get<dynamic>('/strava/status/'));
    _ensure(response, 200);
    return (response.data as Map<String, dynamic>)['connected'] as bool;
  }

  Future<List<StravaRoute>> stravaRoutes() async {
    final response = await _send(() => _dio.get<dynamic>('/strava/routes/'));
    _ensure(response, 200);
    return (response.data as List<dynamic>)
        .map((e) => StravaRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Imports the chosen routes. Returns the imported [Ride]s; per-route
  /// failures are reported in [StravaImportResult.failures].
  Future<StravaImportResult> stravaImport(
    List<StravaRoute> routes, {
    bool disconnect = true,
  }) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/strava/import/',
          data: {
            'routes': [
              for (final r in routes) {'id': r.id, 'name': r.name},
            ],
            'disconnect': disconnect,
          },
          // A batch import can take longer than a plain request if several
          // routes are fetched from Strava and re-parsed server-side.
          options: Options(receiveTimeout: _uploadTimeout),
        ));
    _ensure(response, 200);
    final decoded = response.data as Map<String, dynamic>;
    return StravaImportResult(
      imported: (decoded['imported'] as List<dynamic>)
          .map((e) => Ride.fromJson(e as Map<String, dynamic>))
          .toList(),
      failures: (decoded['failed'] as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['error'].toString())
          .toList(),
    );
  }

  Future<void> stravaDisconnect() async {
    final response = await _send(() => _dio.post<dynamic>('/strava/disconnect/'));
    _ensure(response, 204);
  }

  // --- Audax events ------------------------------------------------------

  /// Public brevet calendar, always scoped to a single month (defaults to the
  /// current one when [month]/[year] are omitted). Sent anonymously — the
  /// endpoint is `AllowAny`, and see [_anonymous] for why a token would
  /// actively hurt. Pass [pageUrl] (a `next`/`previous` URL from a prior page,
  /// which already carries whatever filters were sent) to page through results
  /// without resending the other filter params.
  Future<AudaxEventPage> listAudaxEvents({
    String? pageUrl,
    int? month,
    int? year,
    bool? upcoming,
    String? city,
    String? state,
    String? category,
  }) async {
    final response = await _send(() => pageUrl != null
        ? _dio.get<dynamic>(pageUrl, options: _anonymousOptions)
        : _dio.get<dynamic>(
            '/audax-events/',
            queryParameters: {
              if (month != null) 'month': '$month',
              if (year != null) 'year': '$year',
              if (upcoming != null) 'upcoming': '$upcoming',
              if (city != null && city.isNotEmpty) 'city': city,
              if (state != null && state.isNotEmpty) 'state': state,
              if (category != null && category.isNotEmpty) 'category': category,
            },
            options: _anonymousOptions,
          ));
    _ensure(response, 200);
    return AudaxEventPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Category/state/city values currently in use, computed live from the same
  /// data the list endpoint reads — build filter UI from this rather than
  /// hardcoding a list. Not paginated, no query params, no auth needed.
  Future<AudaxEventFilters> getAudaxEventFilters() async {
    final response = await _send(() =>
        _dio.get<dynamic>('/audax-events/filters/', options: _anonymousOptions));
    _ensure(response, 200);
    return AudaxEventFilters.fromJson(response.data as Map<String, dynamic>);
  }

  // --- Events (app-native, user-created) ---------------------------------

  /// Events visible to the caller (own events of any status/visibility, plus
  /// everyone's PUBLIC+PUBLISHED), newest first. [pageUrl] pages through a
  /// prior `next`/`previous`; the filter args are ignored when it's given
  /// (the URL already carries them). [mine] limits to the caller's own.
  Future<EventPage> listEvents({
    String? pageUrl,
    bool? mine,
    String? status,
    String? visibility,
    String? q,
    String? location,
    bool? upcoming,
  }) async {
    final response = await _send(() => pageUrl != null
        ? _dio.get<dynamic>(pageUrl)
        : _dio.get<dynamic>(
            '/events/',
            queryParameters: {
              if (mine == true) 'mine': 'true',
              if (status != null && status.isNotEmpty) 'status': status,
              if (visibility != null && visibility.isNotEmpty)
                'visibility': visibility,
              if (q != null && q.isNotEmpty) 'q': q,
              if (location != null && location.isNotEmpty) 'location': location,
              if (upcoming == true) 'upcoming': 'true',
            },
          ));
    _ensure(response, 200);
    return EventPage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Event> getEvent(int id) async {
    final response = await _send(() => _dio.get<dynamic>('/events/$id/'));
    _ensure(response, 200);
    return Event.fromJson(response.data as Map<String, dynamic>);
  }

  /// Creates an event from a body the caller assembles (all fields optional
  /// except `start_date`). A raw map rather than typed params because several
  /// fields carry meaning in their explicit value — `entry_fee: 0` = free,
  /// `max_subscribers: null` = unlimited — that the form fills in directly.
  /// Returns the full [Event] detail (`201`).
  Future<Event> createEvent(Map<String, dynamic> data) async {
    final response =
        await _send(() => _dio.post<dynamic>('/events/', data: data));
    _ensure(response, 201);
    return Event.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates an event (creator only). PATCH semantics: only the keys present
  /// in [data] change, so the caller sends exactly what it means to set —
  /// including an explicit `null` to clear the attached ride or the subscriber
  /// cap. Returns the updated [Event] detail.
  Future<Event> updateEvent(int id, Map<String, dynamic> data) async {
    final response =
        await _send(() => _dio.patch<dynamic>('/events/$id/', data: data));
    _ensure(response, 200);
    return Event.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteEvent(int id) async {
    final response = await _send(() => _dio.delete<dynamic>('/events/$id/'));
    _ensure(response, 204);
  }

  /// Subscribes to a published event, optionally attaching a checklist: an
  /// existing one by [checklistId], or a brand-new one from [newChecklistName]
  /// + [newChecklistItems] (created server-side in the same call). Pass none of
  /// them to subscribe without a checklist. Returns the new [Subscription]
  /// (`201`).
  Future<Subscription> subscribeToEvent(
    int eventId, {
    int? checklistId,
    String? newChecklistName,
    List<({String text, bool isMandatory})>? newChecklistItems,
  }) async {
    final Map<String, dynamic> body;
    if (checklistId != null) {
      body = {'checklist_id': checklistId};
    } else if (newChecklistName != null) {
      body = {
        'new_checklist': {
          'name': newChecklistName,
          'items': [
            for (final it in newChecklistItems ?? const [])
              {'text': it.text, 'is_mandatory': it.isMandatory},
          ],
        },
      };
    } else {
      body = const {};
    }
    final response = await _send(
        () => _dio.post<dynamic>('/events/$eventId/subscribe/', data: body));
    _ensure(response, 201);
    return Subscription.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> unsubscribeFromEvent(int eventId) async {
    final response = await _send(
        () => _dio.delete<dynamic>('/events/$eventId/subscribe/'));
    _ensure(response, 204);
  }

  /// Copies the event's attached route into the caller's own library and
  /// returns the new [Ride] (full detail). The voluntary counterpart to the
  /// old copy-on-subscribe (which no longer happens): any viewer of the event
  /// may call it, and it's idempotent — an existing copy of this event's ride
  /// is returned rather than duplicated. `400` if the event has no route, or
  /// the caller already owns the source ride.
  Future<Ride> copyEventRide(int eventId) async {
    final response =
        await _send(() => _dio.post<dynamic>('/events/$eventId/copy-ride/'));
    _ensure(response, 201);
    return Ride.fromJson(response.data as Map<String, dynamic>);
  }

  /// The creator-only roster for an event. `403` (surfaced as an
  /// [ApiException]) if the caller isn't the creator.
  Future<EventRoster> getEventSubscribers(int eventId) async {
    final response =
        await _send(() => _dio.get<dynamic>('/events/$eventId/subscribers/'));
    _ensure(response, 200);
    return EventRoster.fromJson(response.data as Map<String, dynamic>);
  }

  // --- Event waiver document (public events, S3 presigned upload) ---------

  /// Asks the server for a presigned S3 POST so the client can upload the
  /// event's waiver PDF straight to S3 (the bytes never touch our backend).
  /// Creator + public events only.
  Future<EventDocumentPresign> presignEventDocument(int eventId) async {
    final response = await _send(
        () => _dio.post<dynamic>('/events/$eventId/document/presign/'));
    _ensure(response, 200);
    return EventDocumentPresign.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads [filePath] directly to S3 using a presign from
  /// [presignEventDocument]. Goes to S3's host, not our API, so it uses a bare
  /// Dio with no `baseUrl` and no auth interceptor. S3's presigned POST
  /// requires the policy [EventDocumentPresign.fields] *before* the file part,
  /// and answers `204` with no body on success.
  Future<void> uploadEventDocument(
    EventDocumentPresign presign,
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      ...presign.fields,
      'file': await MultipartFile.fromFile(filePath),
    });
    final s3 = Dio(BaseOptions(
      sendTimeout: _uploadTimeout,
      receiveTimeout: _uploadTimeout,
      validateStatus: (_) => true,
    ));
    try {
      final response = await _send(() => s3.post<dynamic>(
            presign.url,
            data: formData,
            onSendProgress: onProgress,
          ));
      // S3 returns 204 (no redirect) when the presign's success_action_status
      // isn't overridden, which the backend leaves at its default.
      if (response.statusCode != 204 && response.statusCode != 201) {
        throw ApiException(
          'The upload was rejected by storage (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } finally {
      s3.close();
    }
  }

  /// Tells the backend the S3 upload finished so it records the key on the
  /// event. Returns the updated [Event] detail.
  Future<Event> confirmEventDocument(int eventId) async {
    final response =
        await _send(() => _dio.post<dynamic>('/events/$eventId/document/'));
    _ensure(response, 200);
    return Event.fromJson(response.data as Map<String, dynamic>);
  }

  /// A short-lived (5 min) presigned URL to read the event's waiver PDF —
  /// fetch on demand each time, don't cache it. `404` if there's none.
  Future<String> getEventDocumentUrl(int eventId) async {
    final response =
        await _send(() => _dio.get<dynamic>('/events/$eventId/document/'));
    _ensure(response, 200);
    return (response.data as Map<String, dynamic>)['url'] as String;
  }

  Future<void> deleteEventDocument(int eventId) async {
    final response =
        await _send(() => _dio.delete<dynamic>('/events/$eventId/document/'));
    _ensure(response, 204);
  }

  // --- Route suggestions (for event creation) ----------------------------

  /// Curated routes to suggest. Provide [lat] & [lng] together for the primary
  /// 25 km radius match, or [city] for the dropdown fallback (one or the
  /// other). [SuggestionsResult.mode] says which path answered.
  Future<SuggestionsResult> getRouteSuggestions({
    double? lat,
    double? lng,
    String? city,
    int? limit,
  }) async {
    final response = await _send(() => _dio.get<dynamic>(
          '/events/suggestions/',
          queryParameters: {
            'lat': ?lat,
            'lng': ?lng,
            if (city != null && city.isNotEmpty) 'city': city,
            'limit': ?limit,
          },
        ));
    _ensure(response, 200);
    return SuggestionsResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Distinct city labels among curated rides — the fallback dropdown options
  /// when geolocation isn't available.
  Future<List<String>> getSuggestionLocations() async {
    final response =
        await _send(() => _dio.get<dynamic>('/events/suggestions/locations/'));
    _ensure(response, 200);
    return ((response.data as Map<String, dynamic>)['locations'] as List<dynamic>)
        .map((e) => e.toString())
        .toList();
  }

  /// Opts one of the caller's rides into the curated-suggestion pool (moves it
  /// to staff review). Returns the ride's new `public_suggestion_status`
  /// (`202`). `409` if it's already approved.
  Future<String> suggestRidePublic(int rideId, String description) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/rides/$rideId/suggest/',
          data: {'description': description},
        ));
    _ensure(response, 202);
    return (response.data as Map<String, dynamic>)['public_suggestion_status']
        .toString();
  }

  // --- Checklists (the rider's reusable library) -------------------------

  /// One page of the rider's checklists. [pageUrl] pages through a prior
  /// `next`. The library is usually small; [fetchAllChecklists] wraps this to
  /// pull every page.
  Future<ChecklistPage> listChecklists({String? pageUrl}) async {
    final response =
        await _send(() => _dio.get<dynamic>(pageUrl ?? '/checklists/'));
    _ensure(response, 200);
    return ChecklistPage.fromJson(response.data as Map<String, dynamic>);
  }

  /// Every checklist the rider owns, paging through until the list ends —
  /// the library is personal and small, so the picker/library screens want it
  /// whole rather than paginated.
  Future<List<Checklist>> fetchAllChecklists() async {
    final all = <Checklist>[];
    String? pageUrl;
    do {
      final page = await listChecklists(pageUrl: pageUrl);
      all.addAll(page.results);
      pageUrl = page.next;
    } while (pageUrl != null);
    return all;
  }

  /// Creates a checklist, optionally seeded with [items]. Returns it (`201`).
  Future<Checklist> createChecklist(
    String name, {
    List<({String text, bool isMandatory})>? items,
  }) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/checklists/',
          data: {
            'name': name,
            if (items != null)
              'items': [
                for (final it in items)
                  {'text': it.text, 'is_mandatory': it.isMandatory},
              ],
          },
        ));
    _ensure(response, 201);
    return Checklist.fromJson(response.data as Map<String, dynamic>);
  }

  /// Renames a checklist and/or replaces its whole item set (sending [items]
  /// is replace-all, matching the server). Returns the updated checklist.
  Future<Checklist> updateChecklist(
    int id, {
    String? name,
    List<({String text, bool isMandatory, bool isDone})>? items,
  }) async {
    final response = await _send(() => _dio.patch<dynamic>(
          '/checklists/$id/',
          data: {
            'name': ?name,
            if (items != null)
              'items': [
                for (final it in items)
                  {
                    'text': it.text,
                    'is_mandatory': it.isMandatory,
                    'is_done': it.isDone,
                  },
              ],
          },
        ));
    _ensure(response, 200);
    return Checklist.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteChecklist(int id) async {
    final response = await _send(() => _dio.delete<dynamic>('/checklists/$id/'));
    _ensure(response, 204);
  }

  /// Adds one item to a checklist. Returns the created item (`201`).
  Future<ChecklistItem> addChecklistItem(
    int checklistId, {
    required String text,
    bool isMandatory = false,
    bool isDone = false,
  }) async {
    final response = await _send(() => _dio.post<dynamic>(
          '/checklists/$checklistId/items/',
          data: {
            'text': text,
            'is_mandatory': isMandatory,
            'is_done': isDone,
          },
        ));
    _ensure(response, 201);
    return ChecklistItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Edits one item — e.g. ticking it off ([isDone]). Because a checklist is
  /// reused by reference, this shows on every event it's attached to. Returns
  /// the updated item.
  Future<ChecklistItem> updateChecklistItem(
    int itemId, {
    String? text,
    bool? isMandatory,
    bool? isDone,
  }) async {
    final response = await _send(() => _dio.patch<dynamic>(
          '/checklist-items/$itemId/',
          data: {
            'text': ?text,
            'is_mandatory': ?isMandatory,
            'is_done': ?isDone,
          },
        ));
    _ensure(response, 200);
    return ChecklistItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteChecklistItem(int itemId) async {
    final response =
        await _send(() => _dio.delete<dynamic>('/checklist-items/$itemId/'));
    _ensure(response, 204);
  }

  // --- Subscriptions -----------------------------------------------------

  /// One page of the rider's subscriptions, each with its embedded event and
  /// chosen checklist. [pageUrl] pages through a prior `next`.
  Future<SubscriptionPage> listMySubscriptions({String? pageUrl}) async {
    final response =
        await _send(() => _dio.get<dynamic>(pageUrl ?? '/subscriptions/'));
    _ensure(response, 200);
    return SubscriptionPage.fromJson(response.data as Map<String, dynamic>);
  }
}

class StravaImportResult {
  final List<Ride> imported;
  final List<String> failures;
  const StravaImportResult({required this.imported, required this.failures});
}

/// Presigned-POST parameters for uploading an event's waiver PDF straight to
/// S3 ([ApiClient.presignEventDocument]). [fields] are S3's policy fields that
/// must be sent as multipart parts *before* the file; [key] is the object key
/// the backend records on confirm.
class EventDocumentPresign {
  final String url;
  final Map<String, String> fields;
  final String key;

  const EventDocumentPresign({
    required this.url,
    required this.fields,
    required this.key,
  });

  factory EventDocumentPresign.fromJson(Map<String, dynamic> json) =>
      EventDocumentPresign(
        url: json['url'] as String,
        fields: (json['fields'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v.toString())),
        key: json['key'] as String,
      );
}
