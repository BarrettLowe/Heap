import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final taskJson = <String, Object?>{
    'id': 'd4be2fc9-49b7-46a6-9981-1f063eed03ea',
    'title': 'Fix driveway washout',
    'status': 'inbox',
    'created_at': '2026-10-03T12:34:56.123456Z',
    'updated_at': '2026-10-03T12:34:56.123456Z',
    'priority': null,
    'duration_minutes': null,
    'externally_blocked': false,
    'project_id': null,
    'due_date': null,
  };

  test('GET uses the contract path and parses immutable inbox tasks', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/inbox');
      return http.Response(
        jsonEncode({
          'items': [taskJson],
        }),
        200,
      );
    });
    final result = await HeapApi(
      client: client,
      baseUri: Uri.parse('http://localhost:8000'),
    ).listInbox();
    expect(result.single.title, 'Fix driveway washout');
    expect(result.single.createdAt.isUtc, isTrue);
    expect(() => result.add(result.single), throwsUnsupportedError);
    client.close();
  });

  test(
    'inbox transport failure logs details but keeps a generic error',
    () async {
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = originalDebugPrint);

      final transportError = http.ClientException('TLS handshake failed');
      final client = MockClient((_) async => throw transportError);
      addTearDown(client.close);
      final api = HeapApi(
        client: client,
        baseUri: Uri.parse('https://server.test'),
      );

      await expectLater(
        api.listInbox(),
        throwsA(
          isA<HeapApiException>().having(
            (error) => error.message,
            'message',
            'Could not reach the server.',
          ),
        ),
      );
      expect(messages, ['HeapApi.listInbox failed: $transportError']);
    },
  );

  test('POST sends trimmed title as JSON and parses the saved task', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/tasks');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {'title': 'Fix driveway washout'});
      final captureJson = Map<String, Object?>.from(taskJson)
        ..removeWhere(
          (key, _) => {
            'priority',
            'duration_minutes',
            'externally_blocked',
            'project_id',
            'due_date',
          }.contains(key),
        );
      return http.Response(jsonEncode(captureJson), 201);
    });
    final result = await HeapApi(
      client: client,
      baseUri: Uri.parse('http://localhost:8000'),
    ).capture('Fix driveway washout');
    expect(result.id, taskJson['id']);
    client.close();
  });

  test(
    'task timestamps accept valid zero microseconds without normalizing dates',
    () {
      final task = InboxTask.fromJson({
        ...taskJson,
        'created_at': '2026-10-03T12:34:56.000000Z',
        'updated_at': '2026-10-03T12:34:56.123000Z',
      });
      expect(task.createdAt.microsecond, 0);
      expect(task.updatedAt.millisecond, 123);
      expect(
        () => InboxTask.fromJson({
          ...taskJson,
          'created_at': '2026-02-30T12:34:56.123456Z',
        }),
        throwsFormatException,
      );
    },
  );

  test('HTTP validation error is a known failure', () async {
    final client = MockClient(
      (_) async => http.Response('{"error":{"code":"invalid_request"}}', 422),
    );
    final api = HeapApi(client: client, baseUri: Uri.parse('http://localhost'));
    await expectLater(
      api.capture('bad'),
      throwsA(
        isA<HeapApiException>().having(
          (error) => error.unknownOutcome,
          'unknownOutcome',
          isFalse,
        ),
      ),
    );
    client.close();
  });

  test(
    'server error and malformed success are unknown write outcomes',
    () async {
      for (final response in [
        http.Response('server failure', 500),
        http.Response('{"wrong":"shape"}', 201),
        http.Response(jsonEncode({...taskJson, 'status': 'on_heap'}), 201),
        http.Response(jsonEncode({...taskJson, 'id': 'NOT-A-UUID'}), 201),
        http.Response(
          jsonEncode({...taskJson, 'created_at': '2026-10-03'}),
          201,
        ),
      ]) {
        final client = MockClient((_) async => response);
        final api = HeapApi(
          client: client,
          baseUri: Uri.parse('http://localhost'),
        );
        await expectLater(
          api.capture('task'),
          throwsA(
            isA<HeapApiException>().having(
              (error) => error.unknownOutcome,
              'unknownOutcome',
              isTrue,
            ),
          ),
        );
        client.close();
      }
    },
  );

  test('request timeout covers response completion', () async {
    final client = MockClient(
      (_) => Future<http.Response>.delayed(
        const Duration(milliseconds: 50),
        () => http.Response('{"items":[]}', 200),
      ),
    );
    final api = HeapApi(
      client: client,
      baseUri: Uri.parse('http://localhost'),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(api.listInbox(), throwsA(isA<HeapApiException>()));
    client.close();
  });

  test('timeout includes a response body that never finishes', () async {
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((_, _) async {
      return http.StreamedResponse(body.stream, 201);
    });
    final api = HeapApi(
      client: client,
      baseUri: Uri.parse('http://localhost'),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      api.capture('task'),
      throwsA(
        isA<HeapApiException>().having(
          (error) => error.unknownOutcome,
          'unknownOutcome',
          isTrue,
        ),
      ),
    );
    await body.close();
    client.close();
  });

  test('POST timeout is an unknown write outcome', () async {
    final client = MockClient(
      (_) => Future<http.Response>.delayed(
        const Duration(milliseconds: 50),
        () => http.Response('{}', 201),
      ),
    );
    final api = HeapApi(
      client: client,
      baseUri: Uri.parse('http://localhost'),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      api.capture('task'),
      throwsA(
        isA<HeapApiException>().having(
          (error) => error.unknownOutcome,
          'unknownOutcome',
          isTrue,
        ),
      ),
    );
    client.close();
  });

  test('base URL accepts only plain HTTP(S) origins', () {
    expect(parseApiBaseUri(null), isNull);
    expect(parseApiBaseUri('not a url'), isNull);
    expect(parseApiBaseUri('ftp://server.test'), isNull);
    expect(parseApiBaseUri('http://'), isNull);
    expect(parseApiBaseUri('http://:8000'), isNull);
    expect(parseApiBaseUri('http://server.test:70000'), isNull);
    expect(parseApiBaseUri('https://user@server.test'), isNull);
    expect(parseApiBaseUri('https://server.test/path'), isNull);
    expect(parseApiBaseUri('https://server.test?x=1'), isNull);
    expect(parseApiBaseUri('https://server.test#fragment'), isNull);
    expect(
      parseApiBaseUri('https://server.test/'),
      Uri.parse('https://server.test'),
    );
  });
}
