import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/ride.dart';
import '../models/strava_route.dart';
import '../models/user.dart';
import '../models/weather_point.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = 'https://cyclingngin.duckdns.org/api';

  // Ordinary requests should never hang indefinitely on a bad connection
  // (captive portal, dead wifi); uploads get longer since a 10 MB file can
  // take a while on a slow link.
  static const _requestTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 90);

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  String? _token;

  Future<String?> get token async =>
      _token ??= await _storage.read(key: _tokenKey);

  Future<bool> get isLoggedIn async => (await token) != null;

  Future<Map<String, String>> _headers({bool json = true}) async {
    final t = await token;
    return {
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Token $t',
    };
  }

  /// Runs an HTTP call, applies a timeout, and converts any transport-level
  /// failure (no connection, DNS failure, dropped socket, timeout) into an
  /// [ApiException]. Without this, those errors aren't [ApiException] and
  /// slip past every `on ApiException catch` in the app, leaving a screen
  /// stuck with a stopped spinner and no message shown.
  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _requestTimeout,
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The request timed out. Check your connection and try again.');
    } on SocketException {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    } on http.ClientException {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Same as [_send] but for a [http.MultipartRequest] (file upload), which
  /// returns a [http.StreamedResponse] instead of a plain [http.Response].
  Future<http.StreamedResponse> _sendMultipart(
    http.MultipartRequest request, {
    Duration timeout = _uploadTimeout,
  }) async {
    try {
      return await request.send().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The upload timed out. Check your connection and try again.');
    } on SocketException {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    } on http.ClientException {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  Never _throwForResponse(http.BaseResponse response, String body) {
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected server error (${response.statusCode}).');
    }
    if (decoded.containsKey('detail')) {
      throw ApiException(decoded['detail'] as String);
    }
    final fieldErrors = <String, List<String>>{};
    decoded.forEach((key, value) {
      if (value is List) {
        fieldErrors[key] = value.map((e) => e.toString()).toList();
      }
    });
    final message = fieldErrors.values.expand((v) => v).join('\n');
    throw ApiException(
      message.isEmpty ? 'Request failed (${response.statusCode}).' : message,
      fieldErrors: fieldErrors,
    );
  }

  Future<String> login(String username, String password) async {
    final response = await _send(() => http.post(
      Uri.parse('$baseUrl/auth/token/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ));
    if (response.statusCode != 200) {
      _throwForResponse(response, response.body);
    }
    final t =
        (jsonDecode(response.body) as Map<String, dynamic>)['token'] as String;
    _token = t;
    await _storage.write(key: _tokenKey, value: t);
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
    final response = await _send(() => http.post(
      Uri.parse('$baseUrl/auth/signup/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
      }),
    ));
    if (response.statusCode != 201) _throwForResponse(response, response.body);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    _token = decoded['token'] as String;
    await _storage.write(key: _tokenKey, value: _token!);
    return AppUser.fromJson(decoded);
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<AppUser> me() async {
    final response = await _send(() async => http.get(
      Uri.parse('$baseUrl/auth/me/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return AppUser.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Updates the rider's optional profile fields (name / email).
  Future<AppUser> updateProfile({String? name, String? email}) async {
    final response = await _send(() async => http.patch(
      Uri.parse('$baseUrl/auth/me/'),
      headers: await _headers(),
      body: jsonEncode({
        'name': ?name,
        'email': ?email,
      }),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return AppUser.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RidePage> listRides({String? pageUrl}) async {
    final uri = Uri.parse(pageUrl ?? '$baseUrl/rides/');
    final response = await _send(() async => http.get(uri, headers: await _headers()));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return RidePage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Ride> getRide(int id) async {
    final response = await _send(() async => http.get(
      Uri.parse('$baseUrl/rides/$id/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return Ride.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Ride> uploadRide({required String filePath, String? name}) async {
    final uri = Uri.parse('$baseUrl/rides/');
    final request = http.MultipartRequest('POST', uri);
    final t = await token;
    if (t != null) request.headers['Authorization'] = 'Token $t';
    if (name != null && name.isNotEmpty) request.fields['name'] = name;
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await _sendMultipart(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) _throwForResponse(streamed, body);
    return Ride.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<Ride> renameRide(int id, String name) async {
    final response = await _send(() async => http.patch(
      Uri.parse('$baseUrl/rides/$id/'),
      headers: await _headers(),
      body: jsonEncode({'name': name}),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return Ride.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Recomputes the ride's elevation/gradient profile with a new smoothing
  /// window (50-500 m): wider flattens more GPS noise, narrower preserves
  /// more detail (and more noise).
  Future<Ride> setSmoothing(int id, int windowM) async {
    final response = await _send(() async => http.post(
      Uri.parse('$baseUrl/rides/$id/smoothing/'),
      headers: await _headers(),
      body: jsonEncode({'window_m': windowM}),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return Ride.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteRide(int id) async {
    final response = await _send(() async => http.delete(
      Uri.parse('$baseUrl/rides/$id/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 204) _throwForResponse(response, response.body);
  }

  Future<List<WeatherPoint>> getWeather(
    int id, {
    required DateTime start,
    required DateTime finish,
  }) async {
    String iso(DateTime dt) => dt.toIso8601String().split('.').first;
    final uri = Uri.parse(
      '$baseUrl/rides/$id/weather/',
    ).replace(queryParameters: {'start': iso(start), 'finish': iso(finish)});
    final response = await _send(() async => http.get(uri, headers: await _headers()));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Strava ----------------------------------------------------------------

  /// Returns the browser consent URL to open. Its signed `state` carries the
  /// user id so the web callback can link Strava without a web session.
  Future<String> stravaAuthorizeUrl() async {
    final response = await _send(() async => http.post(
      Uri.parse('$baseUrl/strava/authorize/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return (jsonDecode(response.body) as Map<String, dynamic>)['authorize_url']
        as String;
  }

  Future<bool> stravaConnected() async {
    final response = await _send(() async => http.get(
      Uri.parse('$baseUrl/strava/status/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return (jsonDecode(response.body) as Map<String, dynamic>)['connected']
        as bool;
  }

  Future<List<StravaRoute>> stravaRoutes() async {
    final response = await _send(() async => http.get(
      Uri.parse('$baseUrl/strava/routes/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => StravaRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Imports the chosen routes. Returns the imported [Ride]s; per-route
  /// failures are reported in [StravaImportResult.failures].
  Future<StravaImportResult> stravaImport(
    List<StravaRoute> routes, {
    bool disconnect = true,
  }) async {
    final response = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/strava/import/'),
        headers: await _headers(),
        body: jsonEncode({
          'routes': [
            for (final r in routes) {'id': r.id, 'name': r.name},
          ],
          'disconnect': disconnect,
        }),
      ),
      // A batch import can take longer than a plain request if several
      // routes are fetched from Strava and re-parsed server-side.
      timeout: _uploadTimeout,
    );
    if (response.statusCode != 200) _throwForResponse(response, response.body);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
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
    final response = await _send(() async => http.post(
      Uri.parse('$baseUrl/strava/disconnect/'),
      headers: await _headers(),
    ));
    if (response.statusCode != 204) _throwForResponse(response, response.body);
  }
}

class StravaImportResult {
  final List<Ride> imported;
  final List<String> failures;
  const StravaImportResult({required this.imported, required this.failures});
}
