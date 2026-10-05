import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'task_flow_fakes.dart';

OrganizationSubmission command() => OrganizationSubmission(
  original: detail(),
  draft: const OrganizationDraft(
    title: '  New title  ',
    externallyBlocked: true,
    projectId: null,
  ),
);
void main() {
  test(
    'Heap rejects noncanonical or impossible local dates before requesting',
    () async {
      final client = MockClient((_) async => fail('request must not be sent'));
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      for (final date in ['2026-2-05', '2026-02-30', '2026-10-05T00:00:00']) {
        await expectLater(
          api.listOnHeap(localDate: date),
          throwsFormatException,
        );
      }
      client.close();
    },
  );

  test('unexpected successful write status is uncertain rather than safe to resubmit', () async {
    for (final capture in [true, false]) {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode(detailJson()), capture ? 200 : 201),
      );
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      await expectLater(
        capture ? api.capture('Title') : api.saveOrganization(command()),
        throwsA(
          isA<HeapApiException>().having(
            (error) => error.unknownOutcome,
            'unknown',
            true,
          ),
        ),
      );
      client.close();
    }
  });
  test(
    'duplicate Inbox IDs are invalid responses, not duplicate keyed rows',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [detailJson(), detailJson()],
          }),
          200,
        ),
      );
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      await expectLater(api.listInbox(), throwsA(isA<HeapApiException>()));
      client.close();
    },
  );
  test(
    'known-ID detail and heap paths decode required nullable metadata and flag',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/v1/heap') {
          expect(request.url.queryParameters, {'local_date': '2026-10-05'});
          return http.Response(
            jsonEncode({
              'items': [detailJson(priority: 2, duration: 30, waiting: true)],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/v1/tasks/$taskId');
        return http.Response(jsonEncode(detailJson()), 200);
      });
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      final task = await api.getTask(taskId);
      expect(task.priority, isNull);
      expect(task.externallyBlocked, false);
      expect(task.updatedAtToken, '2026-10-03T12:34:56.000000Z');
      final list = await api.listOnHeap(localDate: '2026-10-05');
      expect(list.single.status, 'on_heap');
      expect(list.single.onHeapSince, DateTime.utc(2026, 10, 3, 12, 34, 56));
      expect(list.single.externallyBlocked, true);
      expect(() => list.clear(), throwsUnsupportedError);
      client.close();
    },
  );
  test('PUT sends all fields including nulls/true and exact canonical token, no move key', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/tasks/$taskId/organization');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {
        'title': 'New title',
        'priority': null,
        'duration_minutes': null,
        'externally_blocked': true,
        'project_id': null,
        'due_date': null,
        'expected_updated_at': '2026-10-03T12:34:56.000000Z',
      });
      return http.Response(
        jsonEncode(detailJson(title: 'New title', waiting: true)),
        200,
      );
    });
    final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
    expect((await api.saveOrganization(command())).externallyBlocked, true);
    client.close();
  });
  for (final projectId in [null, assignedProjectId]) {
    test(
      'fresh project association $projectId is preserved in unchanged and edited PUT',
      () async {
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(detailJson(projectId: projectId)),
              200,
            );
          }
          expect(request.method, 'PUT');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('project_id'), true);
          expect(body['project_id'], projectId);
          return http.Response(
            jsonEncode(
              detailJson(
                projectId: projectId,
                title: body['title'] as String,
                waiting: body['externally_blocked'] as bool,
              ),
            ),
            200,
          );
        });
        final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
        final original = await api.getTask(taskId);
        expect(original.projectId, projectId);
        final unchanged = await api.saveOrganization(
          OrganizationSubmission(
            original: original,
            draft: OrganizationDraft.fromTask(original),
          ),
        );
        expect(unchanged.projectId, projectId);
        final changed = await api.saveOrganization(
          OrganizationSubmission(
            original: unchanged,
            draft: OrganizationDraft(
              title: 'Edited title',
              externallyBlocked: true,
              projectId: projectId,
            ),
          ),
        );
        expect(changed.projectId, projectId);
        client.close();
      },
    );
  }
  test('detail rejects missing metadata, wrong flag types and inconsistent qualification', () {
    for (final field in [
      'priority',
      'duration_minutes',
      'on_heap_since',
      'externally_blocked',
      'project_id',
    ]) {
      final json = detailJson()..remove(field);
      expect(() => TaskDetail.fromJson(json), throwsFormatException);
    }
    for (final changes in <Map<String, Object?>>[
      {'project_id': true},
      {'project_id': 1},
      {'project_id': ''},
      {'project_id': '../project'},
      {'project_id': 'not-a-uuid'},
      {'priority': true},
      {'priority': 1.5},
      {'priority': '2'},
      {'priority': 6},
      {'duration_minutes': 10},
      {'externally_blocked': null},
      {'externally_blocked': 0},
      {'externally_blocked': 'false'},
      {'status': 'other'},
      {'updated_at': '2026-10-03'},
      {'on_heap_since': '2026-02-30T12:34:56.000000Z'},
      {'status': 'on_heap'},
      {'priority': 2, 'duration_minutes': 30},
      {'on_heap_since': '2026-10-03T12:34:56.000000Z'},
    ]) {
      expect(
        () => TaskDetail.fromJson({...detailJson(), ...changes}),
        throwsFormatException,
      );
    }
    expect(
      TaskDetail.fromJson(detailJson(status: 'completed')).status,
      'completed',
    );
    expect(
      formatUtcTimestamp(DateTime.utc(2026, 10, 3)),
      '2026-10-03T00:00:00.000000Z',
    );
  });
  test(
    'wrong-ID and malformed success are unknown writes, not confirmed saves',
    () async {
      for (final body in [
        'not JSON',
        jsonEncode(detailJson(id: '00000000-0000-0000-0000-000000000001')),
        jsonEncode({...detailJson(), 'externally_blocked': null}),
        jsonEncode(detailJson()..remove('project_id')),
        jsonEncode({...detailJson(), 'project_id': false}),
      ]) {
        final client = MockClient((_) async => http.Response(body, 200));
        final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
        await expectLater(
          api.saveOrganization(command()),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'unknown',
              true,
            ),
          ),
        );
        await expectLater(
          api.getTask(taskId),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'unknown',
              false,
            ),
          ),
        );
        client.close();
      }
    },
  );
  test('organization errors expose status, code and relevant waiting/title field errors', () async {
    for (final status in [404, 409, 422, 415, 500]) {
      final code = status == 409
          ? 'task_conflict'
          : status == 422
          ? 'invalid_request'
          : 'not_found';
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': code,
              'message': 'Do not match message.',
              'fields': [
                {
                  'field': 'externally_blocked',
                  'message': 'Must be a boolean.',
                },
              ],
            },
          }),
          status,
        ),
      );
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      await expectLater(
        api.saveOrganization(command()),
        throwsA(
          isA<HeapApiException>()
              .having((e) => e.unknownOutcome, 'unknown', status == 500)
              .having((e) => e.code, 'code', status == 500 ? null : code),
        ),
      );
      if (status == 422) {
        await expectLater(
          api.getTask(taskId),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.fieldErrors['externally_blocked'],
              'flag error',
              'Must be a boolean.',
            ),
          ),
        );
      }
      client.close();
    }
  });
  test(
    'PUT and detail GET time out through unfinished response bodies',
    () async {
      for (final write in [false, true]) {
        final body = StreamController<List<int>>();
        final client = MockClient.streaming(
          (_, _) async => http.StreamedResponse(body.stream, 200),
        );
        final api = HeapApi(
          client: client,
          baseUri: Uri.parse('http://test'),
          timeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          write ? api.saveOrganization(command()) : api.getTask(taskId),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'unknown',
              write,
            ),
          ),
        );
        await body.close();
        client.close();
      }
    },
  );
  test('heap rejects incorrect statuses and duplicate IDs', () async {
    for (final items in [
      [detailJson()],
      [
        detailJson(priority: 2, duration: 30),
        detailJson(priority: 2, duration: 30),
      ],
    ]) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'items': items}), 200),
      );
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      await expectLater(
        api.listOnHeap(localDate: '2026-10-05'),
        throwsA(isA<HeapApiException>()),
      );
      client.close();
    }
  });
  test(
    'bulk Inbox metadata is required, not guessed from capture defaults',
    () async {
      for (final field in [
        'priority',
        'duration_minutes',
        'externally_blocked',
      ]) {
        final json = detailJson()..remove(field);
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [json],
            }),
            200,
          ),
        );
        final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
        await expectLater(api.listInbox(), throwsA(isA<HeapApiException>()));
        client.close();
      }
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [detailJson(priority: 2, waiting: true)],
          }),
          200,
        ),
      );
      final api = HeapApi(client: client, baseUri: Uri.parse('http://test'));
      final list = await api.listInbox();
      expect(list.single.priority, 2);
      expect(list.single.durationMinutes, isNull);
      expect(list.single.externallyBlocked, true);
      client.close();
    },
  );
}
