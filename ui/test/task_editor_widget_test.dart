import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_editor_page.dart';
import 'package:heap_app/project_widgets.dart';

import 'task_flow_fakes.dart';
import 'project_fakes.dart';

Future<void> openEditor(
  WidgetTester tester,
  FakeOrganization org, {
  FakeProjects? projects,
  VoidCallback? onLeave,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<TaskDetail>(
              MaterialPageRoute(
                builder: (_) => TaskEditorPage(
                  id: taskId,
                  service: org,
                  projects:
                      projects ??
                      (FakeProjects()
                        ..items = [project(id: assignedProjectId)]),
                  sourceOnHeap: false,
                  onUncertainLeave: onLeave ?? () {},
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> revealTap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final projectId in [null, assignedProjectId]) {
    testWidgets(
      'task editor shows project picker and preserves association $projectId',
      (tester) async {
        final org = FakeOrganization()
          ..onGet = (_) async => detail(projectId: projectId);
        await openEditor(tester, org);
        await tester.pumpAndSettle();
        expect(find.text('Project'), findsOneWidget);
        expect(
          find.text(projectId == null ? 'No project' : 'Garden'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('editor-title')),
          'Edited task',
        );
        await revealTap(tester, find.byKey(const Key('editor-save')));
        expect(org.lastSubmission!.toJson().containsKey('project_id'), true);
        expect(org.lastSubmission!.toJson()['project_id'], projectId);
      },
    );
  }
  testWidgets('project can be reassigned or cleared and is submitted', (
    tester,
  ) async {
    final org = FakeOrganization()
      ..onGet = (_) async => detail(projectId: assignedProjectId);
    final projects = FakeProjects()
      ..items = [
        project(id: assignedProjectId, name: 'Garden'),
        project(id: reassignedProjectId, name: 'Work'),
      ];
    await openEditor(tester, org, projects: projects);
    await tester.pumpAndSettle();
    await revealTap(
      tester,
      find.byKey(const ValueKey('editor-project-$assignedProjectId')),
    );
    expect(find.text('Work'), findsOneWidget);
    expect(find.byType(ProjectSwatch), findsNWidgets(3));
    expect(find.byIcon(projectGlyph('leaf')), findsAtLeastNWidgets(2));
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(org.puts, 0);
    await revealTap(tester, find.byKey(const Key('editor-save')));
    expect(org.lastSubmission!.draft.projectId, reassignedProjectId);

    await openEditor(tester, org, projects: projects);
    await tester.pumpAndSettle();
    await revealTap(
      tester,
      find.byKey(const ValueKey('editor-project-$assignedProjectId')),
    );
    await tester.tap(find.text('No project').last);
    await tester.pumpAndSettle();
    await revealTap(tester, find.byKey(const Key('editor-save')));
    expect(org.lastSubmission!.draft.projectId, isNull);
  });
  testWidgets(
    'project-list failure keeps current project selectable and unchanged',
    (tester) async {
      final org = FakeOrganization()
        ..onGet = (_) async => detail(projectId: assignedProjectId);
      final projects = FakeProjects()
        ..onList = () => Future.error(const HeapApiException('Offline'));
      await openEditor(tester, org, projects: projects);
      await tester.pumpAndSettle();
      expect(find.text('Could not load projects.'), findsOneWidget);
      expect(find.text('Current project'), findsOneWidget);
      projects
        ..onList = null
        ..items = [project(id: assignedProjectId)];
      await revealTap(tester, find.byKey(const Key('editor-projects-retry')));
      expect(find.text('Garden'), findsOneWidget);
      await revealTap(tester, find.byKey(const Key('editor-save')));
      expect(org.lastSubmission!.draft.projectId, assignedProjectId);
    },
  );
  testWidgets('disposed editor ignores pending detail completion', (
    tester,
  ) async {
    final pending = Completer<TaskDetail>();
    final org = FakeOrganization()..onGet = (_) => pending.future;
    await openEditor(tester, org);
    expect(find.text('Loading task…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    pending.complete(detail());
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'wide editor caps fields and exposes selectable nullable options',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final org = FakeOrganization()
        ..onGet = (_) async => detail(priority: 2, duration: 30);
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('editor-title'))).width, 592);
      await revealTap(tester, find.byKey(const Key('editor-duration')));
      await tester.tap(find.text('Unknown').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Saving will return this task to the inbox.'),
        findsOneWidget,
      );
      await revealTap(tester, find.byKey(const Key('editor-save')));
      expect(org.lastSubmission!.draft.durationMinutes, isNull);
    },
  );
  testWidgets(
    'fresh unavailable detail never edits list data; retry loads real fields',
    (tester) async {
      final org = FakeOrganization()
        ..onGet = (_) => throw const HeapApiException('Offline');
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-title')), findsNothing);
      org.onGet = (_) async => detail(title: 'Fresh server title');
      await revealTap(tester, find.byKey(const Key('detail-retry')));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('editor-title')))
            .controller!
            .text,
        'Fresh server title',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('editor-title')),
                matching: find.byType(TextField),
              ),
            )
            .focusNode!
            .hasFocus,
        false,
      );
    },
  );
  testWidgets(
    'one unchanged valid Save enabled; missing requirements still save; blank title disabled',
    (tester) async {
      final org = FakeOrganization();
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('editor-save')))
            .onPressed,
        isNotNull,
      );
      expect(
        find.text(
          'Choose a priority and duration to qualify for the heap. You can save without them.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('editor-title')), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Enter a task title.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('editor-save')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'dirty system back defaults to keep edits; discard never writes',
    (tester) async {
      final org = FakeOrganization();
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor-title')), 'My edits');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('editor-title')))
            .controller!
            .text,
        'My edits',
      );
      await tester.tap(find.byKey(const Key('editor-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
      expect(org.puts, 0);
    },
  );
  testWidgets(
    'saving blocks visible and system back, fields, waiting and repeated PUT',
    (tester) async {
      final org = FakeOrganization()
        ..onGet = (_) async =>
            TaskDetail.fromJson(detailJson(dueDate: '2026-10-05'));
      final pending = Completer<TaskDetail>();
      org.onSave = (_) => pending.future;
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('editor-title')))
            .enabled,
        false,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('editor-due-date')))
            .enabled,
        false,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('editor-clear-due-date')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('editor-awaiting')))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('editor-back')))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Edit task'), findsOneWidget);
      expect(org.puts, 1);
      pending.complete(detail());
      await tester.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
    },
  );
  testWidgets(
    'conflict and uncertain differing choices retain title and waiting',
    (tester) async {
      for (final uncertain in [false, true]) {
        final org = FakeOrganization()
          ..onSave = (_) => throw HeapApiException(
            'Rejected',
            unknownOutcome: uncertain,
            statusCode: uncertain ? null : 409,
            code: uncertain ? null : 'task_conflict',
          );
        await openEditor(tester, org);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('editor-title')),
          'My edits',
        );
        await revealTap(tester, find.byKey(const Key('editor-awaiting')));
        await revealTap(tester, find.byKey(const Key('editor-save')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('editor-title')))
              .enabled,
          false,
        );
        org.onGet = (_) async => detail(title: 'Remote title');
        await revealTap(tester, find.byKey(const Key('reload-saved-task')));
        expect(find.text('Task title: Remote title'), findsOneWidget);
        expect(
          find.text('Awaiting external dependencies: Yes'),
          findsOneWidget,
        );
        await revealTap(tester, find.byKey(const Key('keep-my-edits')));
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('editor-title')))
              .controller!
              .text,
          'My edits',
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('editor-awaiting')),
              )
              .value,
          true,
        );
        expect(org.puts, 1);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('editor-save')))
              .onPressed,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('conflicting due dates retain distinct years in summaries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final org = FakeOrganization();
    org.onGet = (_) async =>
        TaskDetail.fromJson(detailJson(dueDate: '2026-10-06'));
    org.onSave = (_) => throw const HeapApiException(
      'Conflict',
      statusCode: 409,
      code: 'task_conflict',
    );
    await openEditor(tester, org);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-title')), 'My edits');
    await revealTap(tester, find.byKey(const Key('editor-save')));
    org.onGet = (_) async =>
        TaskDetail.fromJson(detailJson(dueDate: '2026-10-06'));
    await revealTap(tester, find.byKey(const Key('reload-saved-task')));
    await revealTap(tester, find.byKey(const Key('keep-my-edits')));
    await revealTap(tester, find.byKey(const Key('editor-due-date')));
    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2027').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<DateTime>(DateTime(2027, 10, 6))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await revealTap(tester, find.byKey(const Key('editor-save')));
    org.onGet = (_) async =>
        TaskDetail.fromJson(detailJson(dueDate: '2026-10-06'));
    await revealTap(tester, find.byKey(const Key('reload-saved-task')));
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(TaskEditorPage)),
    );
    expect(
      find.text(
        'Due date: ${localizations.formatCompactDate(DateTime(2026, 10, 6))}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Due date: ${localizations.formatCompactDate(DateTime(2027, 10, 6))}',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'matching unknown save offers status-aware return without second PUT',
    (tester) async {
      final org = FakeOrganization()
        ..onSave = (_) =>
            throw const HeapApiException('Unknown', unknownOutcome: true);
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor-title')), 'My edits');
      await revealTap(tester, find.byKey(const Key('editor-save')));
      org.onGet = (_) async => detail(title: 'My edits');
      await revealTap(tester, find.byKey(const Key('reload-saved-task')));
      expect(
        find.text(
          'The saved task matches your changes. This confirms its current state.',
        ),
        findsOneWidget,
      );
      await revealTap(tester, find.byKey(const Key('return-confirmed')));
      expect(find.text('Edit task'), findsNothing);
      expect(org.puts, 1);
    },
  );
  testWidgets(
    'uncertain adopted saved version still needs possible-save leave guard',
    (tester) async {
      var left = 0;
      final org = FakeOrganization()
        ..onSave = (_) =>
            throw const HeapApiException('Unknown', unknownOutcome: true);
      await openEditor(tester, org, onLeave: () => left++);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor-title')), 'My edits');
      await revealTap(tester, find.byKey(const Key('editor-save')));
      await revealTap(tester, find.byKey(const Key('reload-saved-task')));
      await revealTap(tester, find.byKey(const Key('use-saved-version')));
      await tester.tap(find.byKey(const Key('editor-back')));
      await tester.pumpAndSettle();
      expect(find.text('Leave without checking the save?'), findsOneWidget);
      await tester.tap(find.text('Leave and discard draft'));
      await tester.pumpAndSettle();
      expect(left, 1);
      expect(org.puts, 1);
    },
  );
  testWidgets(
    'completed reconciliation shows saved values and waiting separately from preserved draft',
    (tester) async {
      final org = FakeOrganization();
      org.onGet = (_) async =>
          TaskDetail.fromJson(detailJson(dueDate: '2026-10-06'));
      org.onSave = (_) =>
          throw const HeapApiException('Unknown', unknownOutcome: true);
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor-title')), 'My draft');
      await revealTap(tester, find.byKey(const Key('editor-save')));
      org.onGet = (_) async => TaskDetail.fromJson(
        detailJson(
          title: 'Completed server task',
          status: 'completed',
          dueDate: '2026-10-06',
          waiting: true,
        ),
      );
      await revealTap(tester, find.byKey(const Key('reload-saved-task')));
      expect(find.text('Task title: Completed server task'), findsOneWidget);
      expect(find.text('Task title: My draft'), findsOneWidget);
      final dueDateLabel = MaterialLocalizations.of(
        tester.element(find.byType(TaskEditorPage)),
      ).formatCompactDate(DateTime(2026, 10, 6));
      expect(find.text('Due date: $dueDateLabel'), findsNWidgets(2));
      expect(find.text('Awaiting external dependencies: Yes'), findsOneWidget);
      expect(find.text('Awaiting external dependencies: No'), findsOneWidget);
      expect(find.text('Project: No project'), findsNWidgets(2));
      expect(find.byKey(const Key('editor-save')), findsNothing);
    },
  );
  testWidgets(
    '320 width and 2x text has scrollable waiting/action and short keyboard fallback',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final org = FakeOrganization();
      await openEditor(tester, org, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('editor-due-date')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('editor-awaiting')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('editor-title')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('due date is draft-only, same-date no-op, and clear is guarded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final org = FakeOrganization()
      ..onGet = (_) async =>
          TaskDetail.fromJson(detailJson(dueDate: '2026-10-05'));
    await openEditor(tester, org);
    await tester.pumpAndSettle();
    expect(find.text('Due date: Oct 5, 2026'), findsNothing);
    final dueDateField = tester.widget<TextFormField>(
      find.byKey(const Key('editor-due-date')),
    );
    expect(dueDateField.controller!.text, contains('2026'));
    expect(find.text('Due date'), findsOneWidget);
    expect(org.puts, 0);

    await revealTap(tester, find.byKey(const Key('editor-due-date')));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    final dateSave = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('OK'),
    );
    await tester.ensureVisible(dateSave);
    await tester.pumpAndSettle();
    await tester.tap(dateSave);
    await tester.pumpAndSettle();
    expect(org.puts, 0);
    expect(find.text('Discard changes?'), findsNothing);

    await tester.tap(find.byKey(const Key('editor-clear-due-date')));
    await tester.pumpAndSettle();
    expect(org.puts, 0);
    expect(find.text('Clear date'), findsNothing);
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();
    expect(org.lastSubmission!.draft.dueDate, isNull);
    expect(org.lastSubmission!.toJson()['due_date'], isNull);
  });
  testWidgets(
    'maximum date selection is submitted unchanged with other edits',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final org = FakeOrganization()
        ..onGet = (_) async =>
            TaskDetail.fromJson(detailJson(dueDate: '9999-12-31'));
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await revealTap(tester, find.byKey(const Key('editor-due-date')));
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byKey(ValueKey<DateTime>(DateTime(9999, 12, 31))).last,
        ),
      );
      await tester.pumpAndSettle();
      final confirm = find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('OK'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor-title')), 'Edited');
      await revealTap(tester, find.byKey(const Key('editor-save')));
      expect(org.lastSubmission!.toJson()['due_date'], '9999-12-31');
      expect(org.puts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Escape cancels picker, restores focus, and leaves date clean', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final org = FakeOrganization()
      ..onGet = (_) async =>
          TaskDetail.fromJson(detailJson(dueDate: '9999-12-31'));
    await openEditor(tester, org);
    await tester.pumpAndSettle();
    await revealTap(tester, find.byKey(const Key('editor-due-date')));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('editor-due-date')),
              matching: find.byType(TextField),
            ),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    expect(org.puts, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });
  testWidgets(
    'minimum date selection is submitted unchanged with other edits',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final org = FakeOrganization();
      org.onGet = (_) async =>
          TaskDetail.fromJson(detailJson(dueDate: '0001-01-01'));
      org.onSave = (_) =>
          throw const HeapApiException('Unknown', unknownOutcome: true);
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await revealTap(tester, find.byKey(const Key('editor-due-date')));
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byKey(ValueKey<DateTime>(DateTime(1, 1, 1))).last,
        ),
      );
      await tester.pumpAndSettle();
      final confirm = find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('OK'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-title')));
      await tester.enterText(find.byKey(const Key('editor-title')), 'Draft');
      await revealTap(tester, find.byKey(const Key('editor-save')));
      await revealTap(tester, find.byKey(const Key('reload-saved-task')));
      expect(find.textContaining('Due date:'), findsNWidgets(2));
      expect(org.lastSubmission!.toJson()['due_date'], '0001-01-01');
      expect(org.puts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'waiting-only change gets dirty guard and never writes immediately',
    (tester) async {
      final org = FakeOrganization();
      await openEditor(tester, org);
      await tester.pumpAndSettle();
      await revealTap(tester, find.byKey(const Key('editor-awaiting')));
      expect(org.puts, 0);
      await tester.tap(find.byKey(const Key('editor-back')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    },
  );
}
