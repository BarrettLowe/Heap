import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/heap_filter.dart';
import 'package:heap_app/heap_filter_pills.dart';
import 'package:heap_app/heap_style.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_lists_page.dart';
import 'package:heap_app/task_widgets.dart';

import 'project_fakes.dart';
import 'task_flow_fakes.dart';

const secondId = '00000000-0000-0000-0000-000000000001';
const thirdId = '00000000-0000-0000-0000-000000000002';

List<TaskDetail> sampleTasks() => [
  detail(title: 'Long waiting task', priority: 5, duration: 120, waiting: true),
  detail(id: secondId, title: 'Short critical task', priority: 1, duration: 15),
  detail(id: thirdId, title: 'Boundary task', priority: 2, duration: 30),
];

Future<InboxController> hostFilters(
  WidgetTester tester,
  FakeOrganization organization, {
  double scale = 1,
  FakeInbox? source,
}) async {
  final inbox = InboxController(source ?? FakeInbox());
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
        organization: organization,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('on-heap-tab')));
  await tester.tap(find.byKey(const Key('on-heap-tab')));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    inbox.dispose();
  });
  return inbox;
}

Future<void> pick(
  WidgetTester tester,
  String type,
  int value, {
  int? maximum,
}) async {
  final control = find.byKey(Key('$type-filter'));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
  if (type == 'time') {
    final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    final index = value == 0 ? 0 : durationChoices.indexOf(value);
    slider.onChanged!(
      RangeValues(
        index.toDouble(),
        (maximum == null ? 5 : durationChoices.indexOf(maximum)).toDouble(),
      ),
    );
    await tester.pump();
    await tester.tapAt(const Offset(2, 2));
  } else {
    final option = find.byKey(
      Key('$type-filter-${value == 0 ? 'any' : value}'),
    );
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
  }
  await tester.pumpAndSettle();
}

List<String> visibleTitles(WidgetTester tester) => tester
    .widgetList<TaskRow>(find.byType(TaskRow))
    .map((row) => row.task.title)
    .toList();

void main() {
  testWidgets(
    'filters are mutually exclusive, preserve order and waiting, and make no HTTP calls',
    (tester) async {
      final tasks = sampleTasks();
      final org = FakeOrganization()..onList = () async => tasks;
      final source = FakeInbox();
      await hostFilters(tester, org, source: source);
      expect(visibleTitles(tester), [
        'Long waiting task',
        'Short critical task',
        'Boundary task',
      ]);
      await pick(tester, 'time', 30);
      expect(visibleTitles(tester), ['Long waiting task', 'Boundary task']);
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      expect(find.text('Priority'), findsOneWidget);
      expect(
        tester
            .widget<TaskRow>(find.byType(TaskRow).first)
            .task
            .externallyBlocked,
        true,
      );
      await pick(tester, 'priority', 1);
      expect(visibleTitles(tester), ['Short critical task']);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Priority: P1'), findsOneWidget);
      await pick(tester, 'time', 120);
      expect(visibleTitles(tester), ['Long waiting task']);
      expect(find.text('Priority'), findsOneWidget);
      await pick(tester, 'priority', 0);
      expect(visibleTitles(tester).length, 3);
      expect(find.text('Time'), findsOneWidget);
      expect(org.lists, 1);
      expect(org.gets, 0);
      expect(org.puts, 0);
      expect(source.lists, 1);
      expect(source.posts, 0);
      expect(tasks.length, 3);
    },
  );

  testWidgets('Time range applies on outside tap and filters both endpoints', (
    tester,
  ) async {
    final org = FakeOrganization()
      ..onList = () async => [
        detail(id: secondId, title: 'Below range', priority: 1, duration: 15),
        detail(id: thirdId, title: 'Lower edge', priority: 1, duration: 30),
        detail(
          id: '00000000-0000-0000-0000-000000000003',
          title: 'Upper edge',
          priority: 1,
          duration: 60,
        ),
        detail(
          id: '00000000-0000-0000-0000-000000000004',
          title: 'Above range',
          priority: 1,
          duration: 120,
        ),
        detail(
          id: '00000000-0000-0000-0000-000000000005',
          title: 'Unknown',
          priority: 1,
        ),
      ];
    await hostFilters(tester, org);
    await pick(tester, 'time', 30, maximum: 60);
    expect(visibleTitles(tester), ['Lower edge', 'Upper edge']);
    expect(find.text('Time: 30 min–1 hour'), findsOneWidget);
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets('Clear removes an active time range and shows all tasks', (
    tester,
  ) async {
    final org = FakeOrganization()..onList = () async => sampleTasks();
    await hostFilters(tester, org);
    await pick(tester, 'time', 30);
    expect(visibleTitles(tester), ['Long waiting task', 'Boundary task']);

    await tester.tap(find.byKey(const Key('time-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('time-range-clear')));
    await tester.pumpAndSettle();

    expect(find.text('Time'), findsOneWidget);
    expect(visibleTitles(tester), [
      'Long waiting task',
      'Short critical task',
      'Boundary task',
    ]);
    expect(org.lists, 1);
  });

  testWidgets('Clear removes a legacy minimum-only time filter', (tester) async {
    HeapFilter? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeapFilterPills(
            filter: const HeapFilter.time(45),
            onChanged: (filter) => changed = filter,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('time-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('time-range-clear')));
    await tester.pumpAndSettle();

    expect(changed!.active, isFalse);
    expect(changed!.minimumMinutes, isNull);
    expect(changed!.maximumMinutes, isNull);
  });

  testWidgets('legacy minimum is preserved until the slider changes', (
    tester,
  ) async {
    HeapFilter? changed;
    const original = HeapFilter.time(45);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeapFilterPills(
            filter: original,
            onChanged: (filter) => changed = filter,
          ),
        ),
      ),
    );

    expect(find.text('Time: 45 min–4 hours'), findsOneWidget);
    await tester.tap(find.byKey(const Key('time-filter')));
    await tester.pumpAndSettle();
    expect(find.text('1 hour–4 hours'), findsOneWidget);
    await tester.tap(find.byKey(const Key('time-range-done')));
    await tester.pumpAndSettle();
    expect(changed, isNull);
    expect(find.text('Time: 45 min–4 hours'), findsOneWidget);

    await tester.tap(find.byKey(const Key('time-filter')));
    await tester.pumpAndSettle();
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
      const RangeValues(2, 5),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('time-range-done')));
    await tester.pumpAndSettle();
    expect(changed!.minimumMinutes, 30);
    expect(changed!.maximumMinutes, 240);
  });

  testWidgets(
    'each Time slider detent has a visible label in the compact popup',
    (tester) async {
      HeapFilter? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeapFilterPills(
              filter: const HeapFilter.time(30),
              onChanged: (filter) => changed = filter,
            ),
          ),
        ),
      );
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      await tester.tap(find.byKey(const Key('time-filter')));
      await tester.pumpAndSettle();
      for (final label in ['5m', '15m', '30m', '1h', '2h', '4h']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.getSize(find.byType(RangeSlider)).width, lessThan(350));
      expect(find.byKey(const Key('time-range-done')), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(2, 3),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('time-range-done')));
      await tester.pumpAndSettle();
      expect(changed!.minimumMinutes, 30);
      expect(changed!.maximumMinutes, 60);
    },
  );

  for (final dismissByBack in [false, true]) {
    testWidgets(
      'Time slider selection is not applied when dismissed by ${dismissByBack ? 'back' : 'Escape'}',
      (tester) async {
        final org = FakeOrganization()..onList = () async => sampleTasks();
        await hostFilters(tester, org);
        await tester.tap(find.byKey(const Key('time-filter')));
        await tester.pumpAndSettle();
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
          const RangeValues(2, 3),
        );
        await tester.pump();
        if (dismissByBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(find.text('Time'), findsOneWidget);
        expect(visibleTitles(tester).length, 3);
      },
    );
  }

  testWidgets(
    'Escape keeps the active filter; full Time range includes known durations',
    (tester) async {
      final org = FakeOrganization()..onList = () async => sampleTasks();
      await hostFilters(tester, org);
      await pick(tester, 'time', 30);
      await tester.tap(find.byKey(const Key('priority-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('priority-filter-5')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      expect(visibleTitles(tester), ['Long waiting task', 'Boundary task']);
      await pick(tester, 'time', 0);
      expect(visibleTitles(tester).length, 3);
      expect(org.lists, 1);
    },
  );

  testWidgets(
    'filter survives Inbox/editor/refresh but a new page starts unfiltered',
    (tester) async {
      final org = FakeOrganization();
      org.onList = () async => sampleTasks();
      org.onGet = (_) async => sampleTasks().first;
      final source = FakeInbox()..items = [detail(title: 'Inbox task')];
      final inbox = await hostFilters(tester, org, source: source);
      await pick(tester, 'time', 30);
      await tester.ensureVisible(find.byKey(const Key('inbox-tab')));
      await tester.tap(find.byKey(const Key('inbox-tab')));
      await tester.pumpAndSettle();
      expect(visibleTitles(tester), ['Inbox task']);
      expect(find.byKey(const Key('time-filter')), findsNothing);
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      await tester.ensureVisible(find.text('Long waiting task'));
      await tester.tap(find.text('Long waiting task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel editing'));
      await tester.pumpAndSettle();
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      org.onList = () async => [sampleTasks().last];
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(visibleTitles(tester), ['Boundary task']);
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      expect(org.lists, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListsPage(
            projects: FakeProjects(),
            inbox: inbox,
            organization: org,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('on-heap-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Time: 30 min–4 hours'), findsNothing);
    },
  );

  testWidgets(
    'no matches is distinct from a truly empty heap and clears locally',
    (tester) async {
      final org = FakeOrganization()..onList = () async => sampleTasks();
      await hostFilters(tester, org);
      await pick(tester, 'priority', 4);
      expect(find.text('No tasks match this filter'), findsOneWidget);
      expect(find.text('Nothing on the heap yet.'), findsNothing);
      await tester.tap(find.byKey(const Key('clear-heap-filter')));
      await tester.pumpAndSettle();
      expect(visibleTitles(tester).length, 3);
      expect(org.lists, 1);
      org.onList = () async => [];
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      await pick(tester, 'priority', 4);
      expect(find.text('Nothing on the heap yet.'), findsOneWidget);
      expect(find.text('No tasks match this filter'), findsNothing);
      expect(find.byKey(const Key('clear-heap-filter')), findsNothing);
    },
  );

  testWidgets(
    'first-load error is not a no-match state; stale filtering keeps the error and old rows',
    (tester) async {
      final org = FakeOrganization()
        ..onList = () async => throw const HeapApiException('Unavailable');
      await hostFilters(tester, org);
      await pick(tester, 'time', 30);
      expect(find.text('Could not load tasks on the heap.'), findsOneWidget);
      expect(find.text('No tasks match this filter'), findsNothing);
      expect(find.text('Nothing on the heap yet.'), findsNothing);
      org.onList = () async => sampleTasks();
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(visibleTitles(tester), ['Long waiting task', 'Boundary task']);
      org.onList = () async => throw const HeapApiException('Unavailable');
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Showing previously loaded tasks. This list may be out of date.',
        ),
        findsOneWidget,
      );
      await pick(tester, 'priority', 4);
      expect(find.text('No tasks match this filter'), findsOneWidget);
      expect(
        find.text(
          'Showing previously loaded tasks. This list may be out of date.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'confirmed Save excluded by filter keeps selection, notice and heading focus even after delayed refresh',
    (tester) async {
      var remote = detail(
        title: 'Saved filtered task',
        priority: 2,
        duration: 30,
      );
      final org = FakeOrganization();
      org.onList = () async => [remote];
      org.onGet = (_) async => remote;
      org.onSave = (submission) async => remote = detail(
        title: submission.draft.title,
        priority: submission.draft.priority,
        duration: submission.draft.durationMinutes,
      );
      await hostFilters(tester, org);
      await pick(tester, 'time', 30);
      await tester.ensureVisible(find.text('Saved filtered task'));
      await tester.tap(find.text('Saved filtered task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-duration-5')));
      await tester.pumpAndSettle();
      final delayed = Completer<List<TaskDetail>>();
      org.onList = () => delayed.future;
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Task saved to the heap. Hidden by the current filter.'),
        findsOneWidget,
      );
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      expect(find.text('No tasks match this filter'), findsOneWidget);
      expect(visibleTitles(tester), isEmpty);
      final heading = tester.widget<Focus>(
        find
            .ancestor(
              of: find.byKey(const Key('heap-heading')),
              matching: find.byType(Focus),
            )
            .first,
      );
      expect(heading.focusNode!.hasFocus, true);
      delayed.complete([remote]);
      await tester.pumpAndSettle();
      expect(find.text('Time: 30 min–4 hours'), findsOneWidget);
      expect(heading.focusNode!.hasFocus, true);
      await pick(tester, 'priority', 2);
      expect(find.text('Priority: P2'), findsOneWidget);
      expect(
        find.text('Task saved to the heap. Hidden by the current filter.'),
        findsNothing,
      );
      expect(org.puts, 1);
      expect(visibleTitles(tester), ['Saved filtered task']);
    },
  );

  for (final layout in [(360.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'filter targets, full value semantics and open menus at ${layout.$1}/${layout.$2}',
      (tester) async {
        tester.view.physicalSize = Size(layout.$1, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final org = FakeOrganization()..onList = () async => sampleTasks();
          await hostFilters(tester, org, scale: layout.$2);
          await pick(tester, 'time', 30);
          expect(
            tester.getSemantics(find.byKey(const Key('time-filter'))),
            isSemantics(
              label: 'Time filter, 30 min to 4 hours',
              isSelected: true,
              isButton: true,
              hasTapAction: true,
            ),
          );
          for (final type in ['priority']) {
            final control = find.byKey(Key('$type-filter'));
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
            expect(tester.getRect(control).right, lessThanOrEqualTo(layout.$1));
            await tester.tap(control);
            await tester.pumpAndSettle();
            for (final value
                in type == 'time'
                    ? [5, 15, 30, 60, 120, 240]
                    : [1, 2, 3, 4, 5]) {
              final item = find.byKey(Key('$type-filter-$value'));
              await tester.ensureVisible(item);
              await tester.pumpAndSettle();
              expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
              if (type == 'priority') {
                expect(
                  find.descendant(
                    of: item,
                    matching: find.byType(PriorityPill),
                  ),
                  findsOneWidget,
                );
              }
              expect(tester.takeException(), isNull);
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }
          await pick(tester, 'priority', 1);
          expect(
            tester.getSemantics(find.byKey(const Key('priority-filter'))),
            isSemantics(
              label: 'Priority filter, P1 Critical',
              isSelected: true,
              isButton: true,
              hasTapAction: true,
            ),
          );
          expect(
            tester.getSemantics(find.byKey(const Key('time-filter'))),
            isSemantics(isSelected: false),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
