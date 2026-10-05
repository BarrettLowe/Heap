import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/heap_style.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_widgets.dart';
import 'package:heap_app/task_lists_page.dart';

import 'project_fakes.dart';
import 'task_flow_fakes.dart';

void main() {
  testWidgets('completion exposes a semantic tap only while enabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var writes = 0;
    Future<void> host({bool pending = false, bool uncertain = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskRow(
              task: detail(priority: 2, duration: 30),
              onHeap: true,
              onOpen: () {},
              onComplete: () => writes++,
              completionPending: pending,
              completionUncertain: uncertain,
            ),
          ),
        ),
      );
    }

    await host();
    final node = tester.getSemantics(
      find.bySemanticsLabel('Complete Existing task'),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    expect(writes, 1);
    await host(pending: true);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Complete Existing task'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await host(uncertain: true);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Complete Existing task'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('completed priority fill is grey, preserving its full label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PriorityPill(priority: 2, neutral: true)),
      ),
    );
    final fill = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect((fill.decoration as BoxDecoration).color, const Color(0xFFE5E8E5));
    expect(find.text('P2 Important'), findsOneWidget);
  });

  testWidgets(
    'unchanged explicit check keeps warning and lock; matching check confirms without another PUT',
    (tester) async {
      final item = detail(priority: 2, duration: 30);
      var remote = item;
      final inbox = InboxController(FakeInbox());
      final org = FakeOrganization();
      org.onList = () async => [item];
      org.onGet = (_) async => remote;
      org.onCompletion = (_, {required completed}) async =>
          throw const HeapApiException('timeout', unknownOutcome: true);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListsPage(
            inbox: inbox,
            organization: org,
            projects: FakeProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('completion-$taskId')));
      await tester.pumpAndSettle();
      final check = find.byKey(Key('check-completion-$taskId'));
      expect(check, findsOneWidget);
      expect(org.gets, 0, reason: 'recovery requires a deliberate check');
      expect(
        find.textContaining('earlier request may still finish'),
        findsOneWidget,
      );
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(org.gets, 1);
      expect(
        find.textContaining('earlier request may still finish'),
        findsOneWidget,
      );
      expect(
        tester.widget<InkWell>(find.byKey(Key('completion-$taskId'))).onTap,
        isNull,
      );
      remote = TaskDetail.fromJson(
        detailJson(
          status: 'completed',
          priority: 2,
          duration: 30,
          since: '2026-10-03T12:34:56.000000Z',
        ),
      );
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(org.gets, 2);
      expect(org.completionWrites, 1);
      expect(
        org.lists,
        1,
        reason: 'matching task GET does not reload the list',
      );
      expect(
        find.textContaining('earlier request may still finish'),
        findsNothing,
      );
      expect(find.byIcon(Icons.check), findsWidgets);
      expect(
        tester.widget<InkWell>(find.byKey(Key('completion-$taskId'))).onTap,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );

  testWidgets(
    'heap completion is separate, confirmed, retained, and refreshed authoritatively',
    (tester) async {
      final item = detail(priority: 2, duration: 30, waiting: true);
      final inboxService = FakeInbox();
      final inbox = InboxController(inboxService);
      final org = FakeOrganization();
      var listItems = [item];
      org.onList = () async => listItems;
      org.onCompletion = (original, {required completed}) async => detail(
        id: original.id,
        title: original.title,
        status: completed ? 'completed' : 'on_heap',
        priority: original.priority,
        duration: original.durationMinutes,
        waiting: original.externallyBlocked,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListsPage(
            inbox: inbox,
            organization: org,
            projects: FakeProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('completion-$taskId')), findsOneWidget);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('completion-$taskId')));
      await tester.pumpAndSettle();
      expect(org.completionWrites, 1);
      expect(org.lists, 1, reason: 'completion does not reload automatically');
      expect(
        find.textContaining('Awaiting external dependencies'),
        findsOneWidget,
      );
      expect(find.text('P2 Important'), findsOneWidget);
      expect(find.text('Edit task'), findsNothing);
      await tester.tap(find.text('Existing task'));
      await tester.pumpAndSettle();
      expect(
        find.text('Edit task'),
        findsNothing,
        reason: 'completed body is not editable',
      );
      expect(org.gets, 1, reason: 'completed body did not open another editor');
      listItems = [];
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('completion-$taskId')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );

  testWidgets(
    'unfinished body still opens editor and narrow completed rows fit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = detail(
        title: List.filled(14, 'Long task').join(' '),
        priority: 2,
        duration: 30,
      );
      final inbox = InboxController(FakeInbox());
      final org = FakeOrganization()..onList = () async => [item];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: TaskListsPage(
            inbox: inbox,
            organization: org,
            projects: FakeProjects(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('on-heap-tab')));
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(Key('completion-$taskId'))),
        const Size(48, 48),
      );
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
}
