import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/project.dart';

import 'project_fakes.dart';

void main() {
  HeapApi api(Future<http.Response> Function(http.Request) handler) => HeapApi(
    client: MockClient(handler),
    baseUri: Uri.parse('http://heap.local'),
    timeout: const Duration(milliseconds: 10),
  );
  test(
    'project transport preserves description and optional saved values',
    () async {
      final requests = <http.Request>[];
      final client = api((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.method == 'DELETE'
                ? {'deleted': true}
                : r.url.path == '/api/v1/projects' && r.method == 'GET'
                ? {
                    'items': [projectJson()],
                  }
                : projectJson(),
          ),
          r.method == 'POST' ? 201 : 200,
        );
      });
      expect((await client.listProjects()).single.name, 'Garden');
      final original = await client.getProject(projectId);
      await client.saveProject(
        ProjectDraft(name: 'Renamed', color: '#2E8EB8', icon: 'old-icon'),
        original: original,
      );
      expect(jsonDecode(requests.last.body), {
        'name': 'Renamed',
        'description': 'Keep this description',
        'color': '#2E8EB8',
        'icon': 'old-icon',
      });
      await client.saveProject(const ProjectDraft(name: 'New'));
      expect(requests.last.method, 'POST');
      expect(jsonDecode(requests.last.body)['color'], isNull);
      await client.deleteProject(projectId);
      expect(requests.last.url.path, '/api/v1/projects/$projectId');
      expect(requests.last.method, 'DELETE');
    },
  );
  test(
    'strict fields, duplicate IDs, mismatched ID and malformed reads',
    () async {
      for (final bad in [
        {...projectJson()}..remove('description'),
        {...projectJson(), 'icon': 5},
        {...projectJson(), 'color': false},
        {...projectJson(), 'name': '  '},
        {...projectJson(), 'id': '../bad'},
        {...projectJson(), 'created_at': '2026-02-30T12:34:56.000000Z'},
      ]) {
        expect(() => Project.fromJson(bad), throwsFormatException);
      }
      for (final body in [
        '{',
        jsonEncode({
          'items': [projectJson(), projectJson()],
        }),
        jsonEncode({
          'items': [null],
        }),
      ]) {
        await expectLater(
          api((_) async => http.Response(body, 200)).listProjects(),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'read is known',
              false,
            ),
          ),
        );
      }
      await expectLater(
        api(
          (_) async => http.Response(
            jsonEncode({
              ...projectJson(),
              'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            }),
            200,
          ),
        ).getProject(projectId),
        throwsA(isA<HeapApiException>()),
      );
    },
  );
  test(
    'every ambiguous write is uncertain, explicit rejection is not',
    () async {
      for (final response in [
        http.Response('{', 201),
        http.Response('{}', 500),
        http.Response('{}', 202),
      ]) {
        await expectLater(
          api((_) async => response)
              .saveProject(const ProjectDraft(name: 'New')),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'uncertain',
              true,
            ),
          ),
        );
      }
      for (final body in ['{}', '{"deleted":false}', '{"deleted":"true"}']) {
        await expectLater(
          api((_) async => http.Response(body, 200)).deleteProject(projectId),
          throwsA(
            isA<HeapApiException>().having(
              (e) => e.unknownOutcome,
              'uncertain',
              true,
            ),
          ),
        );
      }
      await expectLater(
        api((_) => Completer<http.Response>().future).deleteProject(projectId),
        throwsA(
          isA<HeapApiException>().having(
            (e) => e.unknownOutcome,
            'uncertain',
            true,
          ),
        ),
      );
      await expectLater(
        api(
          (_) async => http.Response(
            '{"error":{"fields":[{"field":"name","message":"Bad name"}]}}',
            422,
          ),
        ).saveProject(const ProjectDraft(name: 'New')),
        throwsA(
          isA<HeapApiException>()
              .having((e) => e.fieldErrors['name'], 'field error', 'Bad name')
              .having((e) => e.unknownOutcome, 'rejected', false),
        ),
      );
    },
  );
}
