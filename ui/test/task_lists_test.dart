import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/on_heap_controller.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_lists_page.dart';

import 'project_fakes.dart';
import 'task_flow_fakes.dart';

Future<void> host(
  WidgetTester tester,
  InboxController inbox,
  FakeOrganization org, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TaskListsPage(
        projects: FakeProjects(),
        inbox: inbox,
        organization: org,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> duration30(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('editor-duration')));
  await tester.tap(find.byKey(const Key('editor-duration')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('30 min').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'narrow 2x rows/selector/toolbar and wide capped lists remain scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeInbox()
        ..items = [
          detail(
            title: List.filled(20, 'Long task title').join(' '),
            waiting: true,
          ),
        ];
      final inbox = InboxController(service);
      await host(tester, inbox, FakeOrganization(), scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Soon'), findsNWidgets(2));
      expect(
        tester.getCenter(find.byKey(const Key('projects-toolbar'))).dy,
        greaterThan(tester.getCenter(find.byKey(const Key('soon-today'))).dy),
      );
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SegmentedButton<bool>)).width,
        lessThanOrEqualTo(792),
      );
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'reconciled matching qualification updates lists without repeating PUT',
    (tester) async {
      var remote = detail(priority: 2);
      final service = FakeInbox()
        ..onList = () async => remote.status == 'inbox' ? [remote] : [];
      final inbox = InboxController(service);
      final org = FakeOrganization()..onGet = (_) async => remote;
      org.onList = () async => remote.status == 'on_heap' ? [remote] : [];
      org.onSave = (submission) async {
        remote = detail(priority: 2, duration: 30);
        throw const HeapApiException('Dropped', unknownOutcome: true);
      };
      await host(tester, inbox, org);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      await duration30(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reload-saved-task')));
      await tester.tap(find.byKey(const Key('reload-saved-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('return-confirmed')));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsNothing);
      expect(find.text('30 min'), findsOneWidget);
      expect(inbox.tasks, isEmpty);
      expect(org.puts, 1);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  test(
    'confirmed transitions invalidate old reads and update both destinations',
    () async {
      final service = FakeInbox()..items = [detail()];
      final org = FakeOrganization();
      final inbox = InboxController(service);
      final heap = OnHeapController(org);
      await inbox.load();
      await heap.load();
      final oldInbox = Completer<List<InboxTask>>();
      final oldHeap = Completer<List<TaskDetail>>();
      service.onList = () => oldInbox.future;
      org.onList = () => oldHeap.future;
      final readInbox = inbox.load();
      final readHeap = heap.load();
      final moved = detail(priority: 2, duration: 30, waiting: true);
      inbox.applyConfirmed(moved);
      heap.applyConfirmed(moved);
      oldInbox.complete([detail()]);
      oldHeap.complete([]);
      await Future.wait([readInbox, readHeap]);
      expect(inbox.tasks, isEmpty);
      expect(heap.tasks.single.externallyBlocked, true);
      expect(heap.stale, true);
      inbox.applyConfirmed(detail());
      heap.applyConfirmed(detail());
      expect(inbox.tasks.single.id, taskId);
      expect(heap.tasks, isEmpty);
      inbox.dispose();
      heap.dispose();
    },
  );
  test(
    'confirmed heap merges are ID-unique in age order, not priority order',
    () {
      final heap = OnHeapController(FakeOrganization());
      final low = detail(
        id: '00000000-0000-0000-0000-000000000001',
        priority: 5,
        duration: 240,
      );
      final later = detail(
        priority: 1,
        duration: 5,
        updated: '2026-10-04T12:34:56.000000Z',
      );
      heap.applyConfirmed(later);
      heap.applyConfirmed(low);
      heap.applyConfirmed(later);
      expect(heap.tasks.map((t) => t.id), [low.id, later.id]);
      heap.dispose();
    },
  );
  testWidgets(
    'real inner selector loads On the heap lazily and preserves capture draft',
    (tester) async {
      final service = FakeInbox();
      final inbox = InboxController(service);
      final org = FakeOrganization();
      await host(tester, inbox, org);
      expect(org.lists, 0);
      await tester.tap(find.byKey(const Key('open-capture')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-title')), 'Draft');
      await tester.tap(find.byKey(const Key('close-capture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      expect(org.lists, 1);
      expect(find.byKey(const Key('empty-on-heap')), findsOneWidget);
      await tester.tap(find.byKey(const Key('go-to-inbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-capture')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-title')))
            .controller!
            .text,
        'Draft',
      );
      expect(service.lists, 1);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'automatic qualifying Save navigates before failed refresh and keeps stale success',
    (tester) async {
      final service = FakeInbox()..items = [detail(priority: 2)];
      final inbox = InboxController(service);
      final org = FakeOrganization()..onGet = (_) async => detail(priority: 2);
      org.onList = () => throw const HeapApiException('Disconnected');
      await host(tester, inbox, org);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      await duration30(tester);
      service.onList = () => throw const HeapApiException('Disconnected');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsNothing);
      expect(find.text('30 min'), findsOneWidget);
      expect(
        find.text('Saved, but lists could not be refreshed.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Showing previously loaded tasks. This list may be out of date.',
        ),
        findsOneWidget,
      );
      expect(org.puts, 1);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'clearing requirements returns to Inbox; restoring them automatically returns On the heap',
    (tester) async {
      var remote = detail(priority: 2, duration: 30, waiting: true);
      final service = FakeInbox()
        ..onList = () async => remote.status == 'inbox' ? [remote] : [];
      final inbox = InboxController(service);
      final org = FakeOrganization()..onGet = (_) async => remote;
      org.onList = () async => remote.status == 'on_heap' ? [remote] : [];
      org.onSave = (submission) async {
        remote = detail(
          title: submission.draft.title,
          priority: submission.draft.priority,
          duration: submission.draft.durationMinutes,
          waiting: submission.draft.externallyBlocked,
        );
        return remote;
      };
      await host(tester, inbox, org);
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-priority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unset').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Saving will return this task to the inbox.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(remote.status, 'inbox');
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-priority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P2 Important').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(remote.status, 'on_heap');
      expect(remote.externallyBlocked, true);
      expect(org.puts, 2);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'future toolbar groups are readable unavailable no-ops; Tasks reveals selector without GET',
    (tester) async {
      final service = FakeInbox()
        ..items = List.generate(
          15,
          (i) => detail(
            id: '00000000-0000-0000-0000-${i.toRadixString(16).padLeft(12, '0')}',
            title: 'Task $i',
          ),
        );
      final inbox = InboxController(service);
      final org = FakeOrganization();
      await host(tester, inbox, org);
      for (final label in ['Today', 'Settings']) {
        final semantics = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == '$label. Coming later. Unavailable.',
          ),
        );
        expect(semantics.properties.enabled, false);
        await tester.tap(find.byKey(Key('soon-${label.toLowerCase()}')));
        await tester.pumpAndSettle();
      }
      expect(service.lists, 1);
      expect(org.lists, 0);
      expect(org.gets, 0);
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tasks-toolbar')));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(service.lists, 1);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'delayed post-Save GETs never steal newer capture focus or text',
    (tester) async {
      final service = FakeInbox()..items = [detail()];
      final inbox = InboxController(service);
      final org = FakeOrganization();
      await host(tester, inbox, org);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      final readInbox = Completer<List<InboxTask>>();
      final readHeap = Completer<List<TaskDetail>>();
      service.onList = () => readInbox.future;
      org.onList = () => readHeap.future;
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(org.puts, 1);
      expect(org.lists, 1);
      await tester.tap(find.byKey(const Key('open-capture')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const Key('task-title')),
        'New capture draft',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('task-title')),
      );
      expect(field.focusNode!.hasFocus, true);
      readInbox.complete([detail()]);
      readHeap.complete([]);
      await tester.pumpAndSettle();
      expect(field.focusNode!.hasFocus, true);
      expect(field.controller!.text, 'New capture draft');
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'delayed post-Save GETs never replay row focus after newer editor navigation',
    (tester) async {
      final service = FakeInbox()..items = [detail()];
      final inbox = InboxController(service);
      final org = FakeOrganization();
      await host(tester, inbox, org);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      final readInbox = Completer<List<InboxTask>>();
      final readHeap = Completer<List<TaskDetail>>();
      service.onList = () => readInbox.future;
      org.onList = () => readHeap.future;
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(org.puts, 1);
      expect(org.lists, 1);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Existing task',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const Key('editor-title')),
        'New editor draft',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('editor-title')),
          matching: find.byType(TextField),
        ),
      );
      readInbox.complete([detail()]);
      readHeap.complete([]);
      await tester.pumpAndSettle();
      expect(field.focusNode!.hasFocus, true);
      expect(field.controller!.text, 'New editor draft');
      expect(org.gets, 2);
      expect(org.puts, 1);
      expect(find.text('Edit task'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
}
