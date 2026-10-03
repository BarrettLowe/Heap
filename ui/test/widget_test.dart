import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'server response, not local placeholder data, renders empty inbox',
    (tester) async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/inbox');
        return http.Response('{"items":[]}', 200);
      });
      await tester.pumpWidget(
        HeapApp(
          api: HeapApi(client: client, baseUri: Uri.parse('http://test')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Heap'), findsOneWidget);
      expect(find.byKey(const Key('empty-inbox')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets(
    'refresh stays enabled and unknown saves require warned resubmission',
    (tester) async {
      final task = <String, String>{
        'id': 'd4be2fc9-49b7-46a6-9981-1f063eed03ea',
        'title': 'Possible duplicate',
        'status': 'inbox',
        'created_at': '2026-10-03T12:34:56.123456Z',
        'updated_at': '2026-10-03T12:34:56.123456Z',
      };
      var saved = false;
      var postCount = 0;
      var getCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          getCount++;
          return http.Response(
            jsonEncode({
              'items': saved ? [task] : [],
            }),
            200,
          );
        }
        postCount++;
        if (postCount == 1) return http.Response('server failure', 500);
        saved = true;
        return http.Response(jsonEncode(task), 201);
      });
      await tester.pumpWidget(
        HeapApp(
          api: HeapApi(client: client, baseUri: Uri.parse('http://test')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byKey(const Key('refresh'))).onPressed,
        isNotNull,
      );
      await tester.enterText(
        find.byKey(const Key('task-title')),
        'Possible duplicate',
      );
      await tester.tap(find.byKey(const Key('capture')));
      await tester.pumpAndSettle();
      expect(postCount, 1);
      expect(getCount, 1);
      expect(
        find.textContaining('Refresh the inbox before submitting again'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('capture'))).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(getCount, 2);
      expect(find.textContaining('may create a duplicate'), findsOneWidget);
      await tester.tap(find.text('Submit again (may duplicate)'));
      await tester.pumpAndSettle();
      expect(postCount, 2);
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.textContaining('may create a duplicate'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('capture posts to the server and only then shows the task', (
    tester,
  ) async {
    final task = <String, String>{
      'id': 'd4be2fc9-49b7-46a6-9981-1f063eed03ea',
      'title': 'Fix driveway washout',
      'status': 'inbox',
      'created_at': '2026-10-03T12:34:56.123456Z',
      'updated_at': '2026-10-03T12:34:56.123456Z',
    };
    var saved = false;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'items': saved ? [task] : [],
          }),
          200,
        );
      }
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'title': 'Fix driveway washout'});
      saved = true;
      return http.Response(jsonEncode(task), 201);
    });
    await tester.pumpWidget(
      HeapApp(
        api: HeapApi(client: client, baseUri: Uri.parse('http://test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title')),
      '  Fix driveway washout  ',
    );
    await tester.tap(find.byKey(const Key('capture')));
    await tester.pumpAndSettle();
    expect(find.text('Fix driveway washout'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-title')))
          .controller!
          .text,
      '',
    );
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
}
