import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/heap_style.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/inbox_page.dart';
import 'package:heap_app/project.dart';
import 'package:heap_app/project_editor_page.dart';
import 'package:heap_app/project_widgets.dart';
import 'package:heap_app/task_lists_page.dart';

import 'project_fakes.dart';
import 'task_flow_fakes.dart';

Future<void> host(
  WidgetTester tester,
  FakeProjects projects, {
  double scale = 1,
  FakeInbox? source,
  FakeOrganization? org,
}) async {
  final inbox = InboxController(source ?? FakeInbox());
  addTearDown(inbox.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: heapGreen),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TaskListsPage(
        inbox: inbox,
        organization: org ?? FakeOrganization(),
        projects: projects,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('projects-toolbar')));
  await tester.pumpAndSettle();
}

Future<void> edit(WidgetTester tester) async {
  await tester.tap(find.byType(ProjectRow));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create defaults None, one Save, list row and separate capture', (
    t,
  ) async {
    final service = FakeProjects()..items = [];
    await host(t, service);
    expect(find.textContaining('No projects yet.'), findsOneWidget);
    await t.tap(find.byKey(const Key('add-project')));
    await t.pumpAndSettle();
    expect(find.byType(ProjectEditorPage), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('None'), findsWidgets);
    expect(find.byKey(const Key('project-delete')), findsNothing);
    await t.tap(find.byKey(const Key('project-save')));
    await t.pumpAndSettle();
    expect(find.text('Enter a project name.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('project-name')), 'New garden');
    await t.tap(find.byKey(const Key('project-save')));
    await t.pumpAndSettle();
    expect(service.lastDraft!.color, isNull);
    expect(service.lastDraft!.icon, isNull);
    expect(find.text('Project added.'), findsOneWidget);
    expect(find.byType(ProjectRow), findsOneWidget);
  });
  testWidgets(
    'create 404 keeps all draft fields without deletion risk or task reloads',
    (t) async {
      final service = FakeProjects()
        ..onSave = (_, _) async =>
            throw const HeapApiException('Create rejected', statusCode: 404);
      final source = FakeInbox()..items = [detail(title: 'Kept inbox')];
      final org = FakeOrganization()
        ..onList = () async => [
          detail(title: 'Kept heap', priority: 1, duration: 5),
        ];
      await host(t, service, source: source, org: org);
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('on-heap-tab')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('projects-toolbar')));
      await t.pumpAndSettle();
      final inboxReads = source.lists;
      final heapReads = org.lists;
      final projectReads = service.lists;
      await t.tap(find.byKey(const Key('add-project')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('project-name')), 'Draft');
      await t.tap(find.byKey(const Key('project-color-option-#2E8EB8')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('project-icon')));
      await t.pumpAndSettle();
      await t.tap(find.text('Home').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Create rejected'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.bySemanticsLabel('Color #2E8EB8'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('This project is no longer available.'), findsNothing);
      expect(find.textContaining('deletion succeeded'), findsNothing);
      expect(
        find.text('Project and all assigned tasks deleted.'),
        findsNothing,
      );
      expect(find.byKey(const Key('check-projects')), findsNothing);
      expect(source.lists, inboxReads);
      expect(org.lists, heapReads);
      expect(service.lists, projectReads);
      final lists = t.widgetList<TaskListBody>(
        find.byType(TaskListBody, skipOffstage: false),
      );
      expect(lists, hasLength(2));
      for (final list in lists) {
        expect(list.tasks, hasLength(1));
        expect(list.stale, false);
      }
      final rejectedDraft = service.lastDraft!;
      expect(
        t.widget<FilledButton>(find.byKey(const Key('project-save'))).onPressed,
        isNotNull,
      );
      await t.enterText(find.byKey(const Key('project-name')), 'Corrected');
      service.onSave = null;
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.writes, 2);
      expect(service.lastOriginal, isNull);
      expect(service.lastDraft!.name, 'Corrected');
      expect(service.lastDraft!.color, rejectedDraft.color);
      expect(service.lastDraft!.icon, rejectedDraft.icon);
      expect(find.text('Project added.'), findsOneWidget);
      expect(source.lists, inboxReads);
      expect(org.lists, heapReads);
    },
  );
  testWidgets(
    'edit uses fresh detail, name-only save retains saved arbitrary choices',
    (t) async {
      final service = FakeProjects()
        ..onGet = (_) async => Project.fromJson({
          ...projectJson(name: 'Fresh'),
          'color': 'legacy',
          'icon': 'unknown',
        });
      await host(t, service);
      await edit(t);
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.bySemanticsLabel('Color'), findsOneWidget);
      expect(find.text('Saved icon: unknown'), findsOneWidget);
      await t.enterText(find.byKey(const Key('project-name')), 'Renamed');
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.lastDraft!.color, 'legacy');
      expect(service.lastDraft!.icon, 'unknown');
      expect(service.lastOriginal!.description, 'Keep this description');
    },
  );
  testWidgets('curated menus, cancellation, picker-only dirty guard', (
    t,
  ) async {
    final service = FakeProjects();
    await host(t, service);
    await edit(t);
    await t.tap(find.byKey(const Key('project-color')));
    await t.pumpAndSettle();
    expect(projectColorValues.length, 20);
    expect(find.text('None'), findsWidgets);
    expect(find.text('Green'), findsNothing);
    final paletteSemantics = t.ensureSemantics();
    for (final color in projectColorValues) {
      expect(
        t.getSemantics(find.byKey(Key('project-color-option-$color'))).label,
        'Color $color',
      );
    }
    paletteSemantics.dispose();
    final semantics = t.ensureSemantics();
    for (final color in projectColorValues) {
      expect(
        t.getSemantics(find.byKey(Key('project-color-option-$color'))).label,
        'Color $color',
      );
    }
    semantics.dispose();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(service.writes, 0);
    await t.tap(find.byKey(const Key('project-icon')));
    await t.pumpAndSettle();
    for (final label in ['None', 'Folder', 'Home', 'Leaf', 'Tools', 'Work']) {
      expect(find.text(label), findsWidgets);
    }
    await t.tap(find.text('Home').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('project-back')));
    await t.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(ProjectEditorPage), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(service.writes, 0);
  });
  testWidgets(
    'delete names saved name, safe default, confirmed delete clears both task lists on failed refresh',
    (t) async {
      final service = FakeProjects();
      final source = FakeInbox()..items = [detail(title: 'Old inbox')];
      final org = FakeOrganization()
        ..onList = () async => [
          detail(title: 'Old heap', priority: 1, duration: 5),
        ];
      await host(t, service, source: source, org: org);
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('on-heap-tab')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('projects-toolbar')));
      await t.pumpAndSettle();
      await edit(t);
      await t.enterText(
        find.byKey(const Key('project-name')),
        'Unsaved rename',
      );
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      expect(find.textContaining('"Garden" and ALL tasks'), findsOneWidget);
      expect(find.textContaining('including completed tasks.'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(service.deletes, 0);
      expect(find.text('Unsaved rename'), findsOneWidget);
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      source.onList = () async => throw const HeapApiException('offline');
      org.onList = () async => throw const HeapApiException('offline');
      service.items = [];
      await t.tap(find.byKey(const Key('confirm-project-delete')));
      await t.pumpAndSettle();
      expect(service.deletes, 1);
      expect(
        find.text('Project and all assigned tasks deleted.'),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsNothing);
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      expect(find.text('Old heap'), findsNothing);
      await t.tap(find.byKey(const Key('inbox-tab')));
      await t.pumpAndSettle();
      expect(find.text('Old inbox'), findsNothing);
    },
  );
  testWidgets(
    'pending write blocks duplicate, deletion and back; errors keep draft',
    (t) async {
      final service = FakeProjects();
      final pending = Completer<Project>();
      service.onSave = (_, _) => pending.future;
      await host(t, service);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Draft');
      await t.tap(find.byKey(const Key('project-save')));
      await t.pump();
      expect(
        t.widget<FilledButton>(find.byKey(const Key('project-save'))).onPressed,
        isNull,
      );
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(ProjectEditorPage), findsOneWidget);
      pending.completeError(
        const HeapApiException('Rejected', fieldErrors: {'name': 'Bad name'}),
      );
      await t.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Bad name'), findsOneWidget);
      expect(service.writes, 1);
    },
  );
  testWidgets(
    'capture cancel stays Projects, confirmed capture returns Inbox',
    (t) async {
      final service = FakeProjects();
      await host(t, service);
      await t.tap(find.byKey(const Key('open-capture')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('close-capture')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('add-project')), findsOneWidget);
      await t.tap(find.byKey(const Key('open-capture')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('task-title')), 'Captured');
      await t.tap(find.byKey(const Key('capture')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox-tab')), findsOneWidget);
      expect(find.byKey(const Key('add-project')), findsNothing);
    },
  );
  testWidgets(
    'read failures retry, stale list stays visible, missing detail is read-only',
    (t) async {
      final service = FakeProjects()
        ..onList = () async => throw const HeapApiException('offline');
      await host(t, service);
      expect(find.text('Could not load projects.'), findsOneWidget);
      service.onList = null;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.byType(ProjectRow), findsOneWidget);
      service.onList = () async => throw const HeapApiException('offline');
      await t.tap(find.byKey(const Key('refresh')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Showing previously loaded projects. This list may be out of date.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ProjectRow), findsOneWidget);
      service.onGet = (_) async => throw const HeapApiException('offline');
      await edit(t);
      expect(find.text('Could not load this project.'), findsOneWidget);
      expect(find.byKey(const Key('project-save')), findsNothing);
      service.onGet = (_) async =>
          throw const HeapApiException('gone', statusCode: 404);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('This project is no longer available.'), findsOneWidget);
      expect(find.text('Could not load this project.'), findsNothing);
      expect(find.byKey(const Key('project-delete')), findsNothing);
    },
  );
  testWidgets(
    'color only is dirty, None clears deliberately, Back cancels discard by default',
    (t) async {
      final service = FakeProjects();
      await host(t, service);
      await edit(t);
      await t.tap(find.byKey(const Key('project-color-option-none')));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(ProjectEditorPage), findsOneWidget);
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.lastDraft!.color, isNull);
      expect(service.lastDraft!.icon, 'leaf');
    },
  );
  testWidgets(
    'uncertain create requires successful GET check and deliberate retry confirmation',
    (t) async {
      final service = FakeProjects()..items = [];
      service.onSave = (_, _) async =>
          throw const HeapApiException('unknown', unknownOutcome: true);
      await host(t, service);
      await t.tap(find.byKey(const Key('add-project')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('project-name')), 'Draft');
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'The request may have succeeded. Your draft has been kept. Check projects before trying again.',
        ),
        findsOneWidget,
      );
      expect(
        t.widget<FilledButton>(find.byKey(const Key('project-save'))).onPressed,
        isNull,
      );
      service.onList = () async => throw const HeapApiException('offline');
      await t.tap(find.byKey(const Key('check-projects')));
      await t.pumpAndSettle();
      expect(find.text('Could not check projects.'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('project-save'))).onPressed,
        isNull,
      );
      service.onList = () async => [project(name: 'Draft')];
      await t.tap(find.byKey(const Key('check-projects')));
      await t.pumpAndSettle();
      expect(find.byType(ProjectEditorPage), findsOneWidget);
      expect(service.writes, 1);
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(find.text('Send another request?'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(service.writes, 1);
      service.onSave = null;
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save again'));
      await t.pumpAndSettle();
      expect(service.writes, 2);
      expect(find.text('Project added.'), findsOneWidget);
    },
  );
  testWidgets(
    'pending deletion blocks outside, Escape and back; rejection preserves all draft fields',
    (t) async {
      final service = FakeProjects();
      final pending = Completer<void>();
      service.onDelete = (_) => pending.future;
      await host(t, service);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Draft rename');
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-project-delete')));
      await t.pump();
      expect(find.text('Deleting…'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('confirm-project-delete')),
            )
            .onPressed,
        isNull,
      );
      await t.tapAt(const Offset(5, 5));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Delete project?'), findsOneWidget);
      expect(service.deletes, 1);
      pending.completeError(
        const HeapApiException('rejected', statusCode: 422),
      );
      await t.pumpAndSettle();
      expect(find.text('Could not delete this project.'), findsOneWidget);
      expect(find.text('Draft rename'), findsOneWidget);
      expect(find.bySemanticsLabel('Saved color: #779252'), findsOneWidget);
      expect(find.text('Leaf'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('project-delete')));
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      expect(find.text('Delete project?'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Delete project?'), findsNothing);
      expect(service.deletes, 1);
    },
  );
  testWidgets(
    'unknown delete GET 404 never claims success, keeps draft and removes stale tasks',
    (t) async {
      final service = FakeProjects()
        ..onDelete = (_) async =>
            throw const HeapApiException('unknown', unknownOutcome: true);
      final source = FakeInbox()..items = [detail(title: 'Old inbox')];
      await host(t, service, source: source);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Kept draft');
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      source.onList = () async => throw const HeapApiException('offline');
      await t.tap(find.byKey(const Key('confirm-project-delete')));
      await t.pumpAndSettle();
      expect(find.text('Kept draft'), findsOneWidget);
      service.onGet = (_) async =>
          throw const HeapApiException('gone', statusCode: 404);
      await t.tap(find.byKey(const Key('check-projects')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'The project is unavailable. This does not confirm that deletion succeeded.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('project-save')), findsNothing);
      expect(find.byKey(const Key('project-delete')), findsNothing);
      expect(
        find.text('Project and all assigned tasks deleted.'),
        findsNothing,
      );
      expect(
        t.widget<TextFormField>(find.byKey(const Key('project-name'))).enabled,
        false,
      );
      await t.tap(find.byKey(const Key('project-back')));
      await t.pumpAndSettle();
      await t.tap(find.text('Discard changes'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      expect(find.text('Old inbox'), findsNothing);
    },
  );
  testWidgets(
    'timed-out deletion keeps early task reloads stale and clears them after late project 404',
    (t) async {
      final service = FakeProjects()
        ..onDelete = (_) async => throw const HeapApiException(
          'Delete timed out',
          unknownOutcome: true,
        );
      final source = FakeInbox()..items = [detail(title: 'Removed inbox task')];
      final org = FakeOrganization()
        ..onList = () async => [
          detail(title: 'Removed heap task', priority: 1, duration: 5),
        ];
      await host(t, service, source: source, org: org);
      await edit(t);
      await t.tap(find.byKey(const Key('project-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-project-delete')));
      await t.pumpAndSettle();
      final earlyLists = t
          .widgetList<TaskListBody>(
            find.byType(TaskListBody, skipOffstage: false),
          )
          .toList();
      expect(earlyLists, hasLength(2));
      for (final list in earlyLists) {
        expect(list.loaded, true);
        expect(list.tasks, hasLength(1));
        expect(
          list.stale,
          true,
          reason: 'Early successful GET cannot resolve a delayed DELETE.',
        );
      }
      expect(
        find.text(
          'Showing previously loaded tasks. This list may be out of date.',
          skipOffstage: false,
        ),
        findsNWidgets(2),
      );

      // The delayed DELETE commits after those successful task GETs.
      service.items = [];
      service.onGet = (_) async =>
          throw const HeapApiException('gone', statusCode: 404);
      source.onList = () async => throw const HeapApiException('offline');
      org.onList = () async => throw const HeapApiException('offline');
      await t.tap(find.byKey(const Key('check-projects')));
      await t.pumpAndSettle();
      expect(source.lists, 3);
      expect(org.lists, 2);
      expect(
        find.text('Project and all assigned tasks deleted.'),
        findsNothing,
      );
      expect(
        find.text(
          'The project is unavailable. This does not confirm that deletion succeeded.',
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('project-back')));
      await t.pumpAndSettle();
      await t.tap(find.text('Discard changes'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      expect(find.text('Removed inbox task'), findsNothing);
      await t.tap(find.byKey(const Key('on-heap-tab')));
      await t.pumpAndSettle();
      expect(find.text('Removed heap task'), findsNothing);
    },
  );
  testWidgets(
    'Tasks returns to remembered Heap filter and scroll without reloading tasks',
    (t) async {
      final service = FakeProjects();
      final org = FakeOrganization()
        ..onList = () async => List.generate(
          20,
          (i) => detail(
            id: '00000000-0000-0000-0000-${i.toRadixString(16).padLeft(12, '0')}',
            title: 'Heap task $i',
            priority: 1,
            duration: 30,
          ),
        );
      final source = FakeInbox();
      await host(t, service, org: org, source: source);
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('on-heap-tab')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('priority-filter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('priority-filter-1')));
      await t.pumpAndSettle();
      final scroll = t
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(250);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('projects-toolbar')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('priority-filter')), findsNothing);
      await t.tap(find.byKey(const Key('tasks-toolbar')));
      await t.pumpAndSettle();
      expect(find.text('Priority: P1'), findsOneWidget);
      expect(scroll.offset, 250);
      expect(org.lists, 1);
      expect(source.lists, 1);
      final semantics = t.ensureSemantics();
      expect(
        t.getSemantics(find.byKey(const Key('on-heap-tab'))),
        isSemantics(label: 'Heap', isButton: true, isSelected: true),
      );
      semantics.dispose();
    },
  );
  testWidgets(
    'delayed saved-list read never steals a newer Add draft or focus',
    (t) async {
      final service = FakeProjects();
      await host(t, service);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Saved name');
      final refresh = Completer<List<Project>>();
      service.onList = () => refresh.future;
      await t.tap(find.byKey(const Key('project-save')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(const Key('add-project')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.enterText(find.byKey(const Key('project-name')), 'New draft');
      refresh.complete([project(name: 'Saved name')]);
      await t.pumpAndSettle();
      expect(find.text('New draft'), findsOneWidget);
      final field = t.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, true);
      expect(service.writes, 1);
    },
  );
  testWidgets('inline palette is always visible and updates only the draft', (
    t,
  ) async {
    final service = FakeProjects();
    await host(t, service);
    await edit(t);
    for (final color in projectColorValues) {
      expect(find.byKey(Key('project-color-option-$color')), findsOneWidget);
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('project-color')),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsNothing,
    );
    expect(find.textContaining('#'), findsNothing);
    expect(find.text('Green'), findsNothing);
    final option = find.byKey(const Key('project-color-option-#B82E2E'));
    expect(t.getSize(option).height, greaterThanOrEqualTo(48));
    await t.tap(find.byKey(const Key('project-color-option-#2E8EB8')));
    await t.pumpAndSettle();
    expect(
      t
          .getSemantics(find.byKey(const Key('project-color-option-#2E8EB8')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(find.byType(ProjectEditorPage), findsOneWidget);
    expect(service.writes, 0);
    await t.tap(find.byKey(const Key('project-save')));
    await t.pumpAndSettle();
    expect(service.lastDraft!.color, '#2E8EB8');
  });
  testWidgets('selected hue remains visible around its check badge', (t) async {
    final service = FakeProjects()
      ..onGet = (_) async =>
          Project.fromJson({...projectJson(), 'color': '#B82E2E'});
    await host(t, service);
    await edit(t);
    final swatch = find.byKey(const Key('project-color-swatch-#B82E2E'));
    final badge = find.byKey(const Key('project-color-selected-badge'));
    expect(t.getSize(swatch), const Size(36, 36));
    expect(t.getSize(badge), const Size(22, 22));
    final decoration = t.widget<Container>(swatch).decoration! as BoxDecoration;
    expect(decoration.color, ProjectSwatchColor.parse('#B82E2E'));
    expect((36 - 22) / 2, 7); // 7px of the selected hue remains visible around the badge.
  });
  test('palette has 20 chromatic hues in evenly spaced order', () {
    expect(projectColorValues, hasLength(20));
    final hues = projectColorValues.map((value) {
      final color = ProjectSwatchColor.parse(value);
      final r = color.r;
      final g = color.g;
      final b = color.b;
      final maximum = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minimum = [r, g, b].reduce((a, b) => a < b ? a : b);
      expect(
        maximum - minimum,
        greaterThan(0.15),
        reason: '$value is chromatic',
      );
      final delta = maximum - minimum;
      final sector = maximum == r
          ? ((g - b) / delta) % 6
          : maximum == g
          ? (b - r) / delta + 2
          : (r - g) / delta + 4;
      return (sector * 60) % 360;
    }).toList();
    for (var i = 0; i < hues.length; i++) {
      final next = i + 1 == hues.length ? hues[0] + 360 : hues[i + 1];
      expect(next - hues[i], closeTo(18, 3));
    }
  });
  testWidgets('None is selected accessibly and clears intentionally', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final service = FakeProjects()
      ..onGet = (_) async =>
          Project.fromJson({...projectJson(), 'color': null});
    await host(t, service);
    await edit(t);
    final none = find.byKey(const Key('project-color-option-none'));
    expect(
      t.getSemantics(none),
      isSemantics(
        label: 'None, cleared',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.descendant(of: none, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('project-color-option-#B82E2E')));
    await t.pumpAndSettle();
    await t.tap(none);
    await t.pumpAndSettle();
    expect(service.writes, 0);
    await t.tap(find.byKey(const Key('project-save')));
    await t.pumpAndSettle();
    expect(service.lastDraft!.color, isNull);
    semantics.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('selected None label and check do not overlap at $scale', (
      t,
    ) async {
      final service = FakeProjects()
        ..onGet = (_) async =>
            Project.fromJson({...projectJson(), 'color': null});
      await host(t, service, scale: scale);
      await edit(t);
      final none = find.byKey(const Key('project-color-option-none'));
      final label = find.descendant(of: none, matching: find.text('None'));
      final check = find.descendant(
        of: none,
        matching: find.byIcon(Icons.check),
      );
      expect(t.getRect(label).right, lessThan(t.getRect(check).left));
      expect(t.getSize(none).height, greaterThanOrEqualTo(48));
    });
  }
  testWidgets('focused circle outline contrasts with Heap canvas', (t) async {
    await host(t, FakeProjects());
    await edit(t);
    final option = find.byKey(const Key('project-color-option-#732EB8'));
    await t.ensureVisible(option);
    for (var i = 0; i < 30; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      if (find
          .byKey(const Key('project-color-focus-#732EB8'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    final focused = find.byKey(const Key('project-color-focus-#732EB8'));
    expect(focused, findsOneWidget);
    final decoration =
        t.widget<Container>(focused).decoration! as BoxDecoration;
    final ringColor = (decoration.border! as Border).top.color;
    double luminance(Color color) => color.computeLuminance();
    final lighter = [
      luminance(ringColor),
      luminance(heapCanvas),
    ].reduce((a, b) => a > b ? a : b);
    final darker = [
      luminance(ringColor),
      luminance(heapCanvas),
    ].reduce((a, b) => a < b ? a : b);
    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(3));
  });
  testWidgets('Tab focus is outlined on palette circles and None', (t) async {
    await host(t, FakeProjects());
    await edit(t);
    final seen = <String>{};
    for (var i = 0; i < 24; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      for (final value in [...projectColorValues, 'none']) {
        if (find
            .byKey(Key('project-color-focus-$value'))
            .evaluate()
            .isNotEmpty) {
          seen.add(value);
        }
      }
    }
    expect(seen, containsAll([...projectColorValues, 'none']));
  });
  for (final savedColor in ['#123456', 'legacy-color', '#GGGGGG']) {
    testWidgets('saved color "$savedColor" survives unrelated save', (t) async {
      final service = FakeProjects()
        ..onGet = (_) async => Project.fromJson({
          ...projectJson(),
          'color': savedColor,
          'icon': 'leaf',
        });
      await host(t, service);
      await edit(t);
      expect(find.bySemanticsLabel('Saved color: $savedColor'), findsOneWidget);
      await t.enterText(find.byKey(const Key('project-name')), 'Renamed');
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.lastDraft!.color, savedColor);
    });
  }
  testWidgets('palette tap preserves name focus', (t) async {
    await host(t, FakeProjects());
    await edit(t);
    final nameFocus = t
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('project-name')),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;
    nameFocus.requestFocus();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('project-color-option-#B82E2E')));
    await t.pumpAndSettle();
    expect(nameFocus.hasFocus, isTrue);
  });
  for (final layout in [(320.0, 2.0), (900.0, 2.0)]) {
    testWidgets(
      'inline palette fits and scrolls at ${layout.$1}/${layout.$2}',
      (t) async {
        t.view.physicalSize = Size(layout.$1, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await host(t, FakeProjects(), scale: layout.$2);
        await t.ensureVisible(find.byType(ProjectRow));
        await edit(t);
        await t.ensureVisible(
          find.byKey(const Key('project-color-option-#B82E57')),
        );
        expect(
          find.byKey(const Key('project-color-option-#B82E57')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        expect(
          t.getSize(find.byKey(const Key('project-color'))).width,
          lessThanOrEqualTo(640),
        );
      },
    );
  }
}
