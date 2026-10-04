import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/task_lists_page.dart';

import 'project_fakes.dart';
import 'task_flow_fakes.dart';

void expectSelectedTasks(WidgetTester tester) {
  final node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Tasks$')));
  expect(
    node,
    isSemantics(
      label: 'Tasks',
      isButton: true,
      isSelected: true,
      hasTapAction: true,
    ),
  );
  for (
    var ancestor = node.parent;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    expect(
      ancestor.getSemanticsData().flagsCollection.isSelected,
      isNot(ui.Tristate.isTrue),
      reason: 'Tasks selection must not bubble to the app ancestor.',
    );
  }
}

void main() {
  for (final layout in [(360.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'Tasks selected state belongs to its actionable node at ${layout.$1}/${layout.$2}',
      (tester) async {
        tester.view.physicalSize = Size(layout.$1, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final source = FakeInbox();
          final inbox = InboxController(source);
          final organization = FakeOrganization();
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.$2)),
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
          expectSelectedTasks(tester);
          await tester.ensureVisible(find.byKey(const Key('on-heap-tab')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('on-heap-tab')));
          await tester.pumpAndSettle();
          expectSelectedTasks(tester);
          expect(
            tester.getSemantics(find.byKey(const Key('on-heap-tab'))),
            isSemantics(label: 'Heap', isButton: true, isSelected: true),
          );
          expect(find.text('Nothing on the heap yet.'), findsOneWidget);
          await tester.tap(find.byKey(const Key('tasks-toolbar')));
          await tester.pumpAndSettle();
          expectSelectedTasks(tester);
          expect(source.lists, 1);
          expect(organization.lists, 1);
          await tester.pumpWidget(const SizedBox());
          inbox.dispose();
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
