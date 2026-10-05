import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_widgets.dart';

TaskDetail task({String? dueDate, String status = 'on_heap'}) =>
    TaskDetail.fromJson({
      'id': '00000000-0000-4000-8000-000000000001',
      'title': 'Ranked task',
      'status': status,
      'created_at': '2026-10-03T12:34:56.000000Z',
      'updated_at': '2026-10-03T12:34:56.000000Z',
      'priority': status == 'inbox' ? null : 3,
      'duration_minutes': status == 'inbox' ? null : 30,
      'externally_blocked': false,
      'project_id': null,
      'on_heap_since': status == 'inbox' ? null : '2026-10-03T12:34:56.000000Z',
      'due_date': dueDate,
    });

void main() {
  testWidgets(
    'Heap row shows actual due date without changing saved priority',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      expect(task(dueDate: '2026-10-05').dueDate, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: TaskRow(
              task: task(dueDate: '2026-10-05'),
              onHeap: true,
              onOpen: () {},
              onComplete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Monday, October 5, 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('P3 Normal'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(RegExp('Due Monday, October 5, 2026')),
            )
            .getSemanticsData()
            .label,
        contains('Monday, October 5, 2026'),
      );
      expect(
        tester.getSize(
          find.byKey(
            const Key('completion-00000000-0000-4000-8000-000000000001'),
          ),
        ),
        const Size(48, 48),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskRow(
              task: task(status: 'completed', dueDate: '2026-10-05'),
              onHeap: true,
              onOpen: () {},
              onComplete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Monday, October 5, 2026'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Monday, October 5, 2026')).style!.color,
        const Color(0xFF68716C),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.calendar_today)).color,
        const Color(0xFF68716C),
      );
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(RegExp('Due Monday, October 5, 2026')),
            )
            .getSemanticsData()
            .label,
        contains('Monday, October 5, 2026'),
      );
      semantics.dispose();
    },
  );

  testWidgets('wide Heap row fits due-date metadata', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task(dueDate: '2026-10-05'),
            onHeap: true,
            onOpen: () {},
            onComplete: () {},
          ),
        ),
      ),
    );
    expect(find.text('Monday, October 5, 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox optionally shows its actual due date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task(dueDate: '2026-10-05', status: 'inbox'),
            onHeap: false,
            onOpen: () {},
            onComplete: () {},
          ),
        ),
      ),
    );
    expect(find.text('Monday, October 5, 2026'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
  });

  testWidgets('undated Heap row omits calendar metadata', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task(),
            onHeap: true,
            onOpen: () {},
            onComplete: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.calendar_today), findsNothing);
  });
}
