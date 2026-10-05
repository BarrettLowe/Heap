import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const taskId = 'd4be2fc9-49b7-46a6-9981-1f063eed03ea';
const token = '2026-10-03T12:34:56.123456Z';

Map<String, Object?> taskJson(String status) => {
  'id': taskId,
  'title': 'Existing task',
  'status': status,
  'created_at': token,
  'updated_at': '2026-10-04T12:34:56.123456Z',
  'priority': 2,
  'duration_minutes': 30,
  'externally_blocked': true,
  'project_id': null,
  'due_date': null,
  'on_heap_since': token,
};

TaskDetail original() =>
    TaskDetail.fromJson({...taskJson('on_heap'), 'updated_at': token});

void main() {
  test(
    'completion sends exact versioned request and validates preserved fields',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/tasks/$taskId/completion');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'completed': true,
          'expected_updated_at': token,
        });
        return http.Response(jsonEncode(taskJson('completed')), 200);
      });
      final saved = await HeapApi(
        client: client,
        baseUri: Uri.parse('http://localhost'),
      ).setCompletion(original(), completed: true);
      expect(saved.status, 'completed');
      expect(saved.onHeapSince, original().onHeapSince);
      expect(saved.title, original().title);
      expect(saved.priority, original().priority);
      expect(saved.durationMinutes, original().durationMinutes);
      expect(saved.externallyBlocked, original().externallyBlocked);
      client.close();
    },
  );

  test(
    'completion rejects wrong result and classifies unknown outcomes',
    () async {
      for (final response in [
        http.Response(jsonEncode(taskJson('on_heap')), 200),
        http.Response(
          jsonEncode({...taskJson('completed'), 'title': 'Changed'}),
          200,
        ),
        http.Response(
          jsonEncode({...taskJson('completed'), 'due_date': '2026-10-05'}),
          200,
        ),
        http.Response('server error', 500),
        http.Response('{}', 200),
      ]) {
        final client = MockClient((_) async => response);
        final api = HeapApi(
          client: client,
          baseUri: Uri.parse('http://localhost'),
        );
        await expectLater(
          api.setCompletion(original(), completed: true),
          throwsA(isA<HeapApiException>()),
        );
        client.close();
      }
    },
  );

  test('undo requires on-heap response with original age', () async {
    final client = MockClient((request) async {
      expect(jsonDecode(request.body), {
        'completed': false,
        'expected_updated_at': '2026-10-04T12:34:56.123456Z',
      });
      return http.Response(jsonEncode(taskJson('on_heap')), 200);
    });
    final saved =
        await HeapApi(
          client: client,
          baseUri: Uri.parse('http://localhost'),
        ).setCompletion(
          TaskDetail.fromJson(taskJson('completed')),
          completed: false,
        );
    expect(saved.status, 'on_heap');
    expect(saved.onHeapSince, original().onHeapSince);
    client.close();
  });
}
