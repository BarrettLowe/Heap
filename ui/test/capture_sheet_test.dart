import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/task_lists_page.dart';

import 'task_flow_fakes.dart';

Future<void> captureHost(
  WidgetTester tester,
  InboxController inbox, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TaskListsPage(inbox: inbox, organization: FakeOrganization()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-capture')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('idle close preserves capture text and restores plus focus', (
    tester,
  ) async {
    final service = FakeInbox();
    final inbox = InboxController(service);
    await captureHost(tester, inbox);
    await tester.enterText(find.byKey(const Key('task-title')), 'Keep this');
    await tester.tap(find.byKey(const Key('close-capture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-title')), findsNothing);
    expect(service.posts, 0);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('open-capture')))
          .focusNode!
          .hasFocus,
      true,
    );
    await tester.tap(find.byKey(const Key('open-capture')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-title')))
          .controller!
          .text,
      'Keep this',
    );
    await tester.pumpWidget(const SizedBox());
    inbox.dispose();
  });
  testWidgets(
    'pending POST blocks close/back/barrier and duplicates, retaining newer capture input',
    (tester) async {
      final pending = Completer<InboxTask>();
      final service = FakeInbox()..onCapture = (_) => pending.future;
      final inbox = InboxController(service);
      await captureHost(tester, inbox);
      await tester.enterText(find.byKey(const Key('task-title')), 'Submitted');
      await tester.tap(find.byKey(const Key('capture')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('close-capture')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('capture'))).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.text('Capture task'), findsOneWidget);
      tester
          .widget<TextField>(find.byKey(const Key('task-title')))
          .onSubmitted!('Submitted');
      await tester.pump();
      expect(service.posts, 1);
      await tester.enterText(
        find.byKey(const Key('task-title')),
        'Younger draft',
      );
      service.items = [detail(title: 'Submitted')];
      pending.complete(service.items.single);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('task-title')),
      );
      expect(field.controller!.text, 'Younger draft');
      expect(field.focusNode!.hasFocus, true);
      expect(find.text('Submitted'), findsOneWidget);
      expect(service.posts, 1);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    'uncertainty survives close/reopen and only warned deliberate retry writes',
    (tester) async {
      final service = FakeInbox();
      service.onCapture = (title) async {
        if (service.posts == 1) {
          throw const HeapApiException('Unknown', unknownOutcome: true);
        }
        final task = detail(title: title);
        service.items = [task];
        return task;
      };
      final inbox = InboxController(service);
      await captureHost(tester, inbox);
      await tester.enterText(find.byKey(const Key('task-title')), 'Uncertain');
      await tester.tap(find.byKey(const Key('capture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('close-capture')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'A capture may have succeeded. Reopen capture to check before submitting again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('open-capture')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-title')))
            .controller!
            .text,
        'Uncertain',
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('capture'))).onPressed,
        isNull,
      );
      expect(service.posts, 1);
      await tester.ensureVisible(find.byKey(const Key('capture-refresh')));
      await tester.tap(find.byKey(const Key('capture-refresh')));
      await tester.pumpAndSettle();
      expect(service.posts, 1);
      await tester.ensureVisible(find.byKey(const Key('capture-resubmit')));
      await tester.tap(find.byKey(const Key('capture-resubmit')));
      await tester.pumpAndSettle();
      expect(service.posts, 2);
      expect(find.byKey(const Key('task-title')), findsNothing);
      expect(inbox.unknownOutcome, false);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
  testWidgets(
    '320 width 2x capture stays reachable with docked keyboard inset',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inbox = InboxController(FakeInbox());
      await captureHost(tester, inbox, scale: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('capture')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('task-title')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
}
