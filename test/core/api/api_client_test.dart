import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cylan/core/api/api_client.dart';
import 'package:cylan/core/api/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers requests from memory instead of the network, recording what it was
/// asked for. Swapping the adapter (rather than faking [ApiClient] itself)
/// means the real [BaseOptions], the real auth interceptor and the real status
/// handling all still run — which is the whole point, since that's the code
/// under test.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, Object? body, this.throwing})
      : body = body ?? const <String, dynamic>{};

  final int status;
  final Object body;

  /// When set, the transport fails with this instead of answering — standing
  /// in for a dead connection or a socket that never replies.
  final DioException? throwing;

  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (throwing != null) throw throwing!;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The auth interceptor reads the token from secure storage, which has no
    // platform channel under `flutter test`.
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok123'});
  });

  group('auth interceptor', () {
    test('attaches the stored token to an authenticated endpoint', () async {
      final adapter = _FakeAdapter(body: {'id': 1, 'username': 'ana'});
      await ApiClient.forTests(adapter).me();

      expect(adapter.requests.single.headers['Authorization'], 'Token tok123');
    });

    test('sends no token to the public audax calendar', () async {
      final adapter = _FakeAdapter(
        body: {'count': 0, 'next': null, 'previous': null, 'results': []},
      );
      await ApiClient.forTests(adapter).listAudaxEvents(month: 7, year: 2026);

      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse,
          reason: 'DRF authenticates before it checks permissions, so a stale '
              'token would turn this AllowAny endpoint into a 401');
    });

    test('sends no token when logging in', () async {
      final adapter = _FakeAdapter(body: {'token': 'new-token'});
      await ApiClient.forTests(adapter).login('ana', 'hunter2');

      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse,
          reason: 'login is where a token is obtained, not presented');
    });
  });

  group('error mapping', () {
    test('a 401 detail body carries its status code through', () async {
      // The exact shape DRF returns for a rejected token, per the API docs.
      final adapter = _FakeAdapter(status: 401, body: {'detail': 'Invalid token.'});

      await expectLater(
        ApiClient.forTests(adapter).me(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Invalid token.')
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('field validation errors are collected and joined', () async {
      final adapter = _FakeAdapter(status: 400, body: {
        'username': ['This field is required.'],
        'password': ['Too short.'],
      });

      try {
        await ApiClient.forTests(adapter).signup(username: '', password: '');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.fieldErrors, {
          'username': ['This field is required.'],
          'password': ['Too short.'],
        });
        expect(e.message, contains('This field is required.'));
        expect(e.message, contains('Too short.'));
      }
    });

    test('a transport failure becomes an ApiException with no status code',
        () async {
      final adapter = _FakeAdapter(
        throwing: DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'no route to host',
          error: const SocketException('no route to host'),
        ),
      );

      try {
        await ApiClient.forTests(adapter).me();
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.message, contains('Could not reach the server'));
        expect(e.statusCode, isNull,
            reason: 'a null status is how callers tell "never reached the '
                'server" from "the server rejected you"');
      }
    });

    test('a non-JSON body reports the bare status rather than throwing',
        () async {
      // Shouldn't happen — the API guarantees JSON on every path — but a proxy
      // or CDN can still interpose an HTML error page.
      final adapter = _FakeAdapter(status: 502, body: '<html>bad gateway</html>');

      try {
        await ApiClient.forTests(adapter).me();
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.message, contains('502'));
        expect(e.statusCode, 502);
      }
    });
  });

  group('requests', () {
    test('a relative path joins onto baseUrl without mangling it', () async {
      // baseUrl ends in `/api` with no trailing slash and every path starts
      // with one — get that join wrong and all 25 endpoints break at once.
      final adapter = _FakeAdapter(body: {'id': 1, 'username': 'ana'});
      await ApiClient.forTests(adapter).me();

      expect(adapter.requests.single.uri.toString(),
          'https://cyclingngin.duckdns.org/api/auth/me/');
    });

    test('query parameters are sent, not dropped', () async {
      final adapter = _FakeAdapter(
        body: {'count': 0, 'next': null, 'previous': null, 'results': []},
      );
      await ApiClient.forTests(adapter)
          .listAudaxEvents(month: 7, year: 2026, city: 'Pune');

      final uri = adapter.requests.single.uri;
      expect(uri.path, '/api/audax-events/');
      expect(uri.queryParameters,
          containsPair('month', '7'));
      expect(uri.queryParameters, containsPair('year', '2026'));
      expect(uri.queryParameters, containsPair('city', 'Pune'));
    });

    test('an absolute page URL is used as-is, not pasted onto baseUrl',
        () async {
      final adapter = _FakeAdapter(
        body: {'count': 0, 'next': null, 'previous': null, 'results': []},
      );
      await ApiClient.forTests(adapter)
          .listRides(pageUrl: 'https://cyclingngin.duckdns.org/api/rides/?page=3');

      expect(adapter.requests.single.uri.toString(),
          'https://cyclingngin.duckdns.org/api/rides/?page=3');
    });
  });
}
