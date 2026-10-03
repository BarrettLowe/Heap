import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/inbox_controller.dart';
import 'package:heap_app/main.dart';

final savedTask = InboxTask(
  id: 'd4be2fc9-49b7-46a6-9981-1f063eed03ea',
  title: 'Saved task',
  status: 'inbox',
  createdAt: DateTime.utc(2026, 10, 3),
  updatedAt: DateTime.utc(2026, 10, 3),
);

class FakeInboxService implements InboxService {
  Future<List<InboxTask>> Function()? onList;
  Future<InboxTask> Function(String title)? onCapture;
  int listCalls = 0;
  int captureCalls = 0;

  @override
  Future<List<InboxTask>> listInbox() {
    listCalls++;
    return onList?.call() ?? Future.value(const []);
  }

  @override
  Future<InboxTask> capture(String title) {
    captureCalls++;
    return onCapture?.call(title) ?? Future.value(savedTask);
  }
}

void main() {
  testWidgets('initial loading is distinct from an empty server response', (
    tester,
  ) async {
    final pending = Completer<List<InboxTask>>();
    final service = FakeInboxService()..onList = () => pending.future;
    final controller = InboxController(service);
    await tester.pumpWidget(
      MaterialApp(home: InboxPage(controller: controller)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('empty-inbox')), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-inbox')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('unavailable inbox can be retried to a genuine empty response', (
    tester,
  ) async {
    final service = FakeInboxService();
    service.onList = () async {
      if (service.listCalls == 1) {
        throw const HeapApiException('Could not reach the server.');
      }
      return const [];
    };
    final fakeController = InboxController(service);
    await tester.pumpWidget(
      MaterialApp(home: InboxPage(controller: fakeController)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load the inbox.'), findsNothing);
    expect(find.text('Could not reach the server.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-inbox')), findsOneWidget);
    expect(find.text('Could not reach the server.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    fakeController.dispose();
  });

  testWidgets('blank capture does not send or clear the draft', (tester) async {
    final service = FakeInboxService();
    final controller = InboxController(service);
    await tester.pumpWidget(
      MaterialApp(home: InboxPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '   ');
    await tester.tap(find.byKey(const Key('capture')));
    await tester.pumpAndSettle();
    expect(service.captureCalls, 0);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-title')))
          .controller!
          .text,
      '   ',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('obsolete GET results do not overwrite a newer response', () async {
    final service = FakeInboxService();
    final older = Completer<List<InboxTask>>();
    service.onList = () =>
        service.listCalls == 1 ? older.future : Future.value([savedTask]);
    final controller = InboxController(service);
    final oldLoad = controller.load();
    await controller.load();
    older.complete(const []);
    await oldLoad;
    expect(controller.tasks, [savedTask]);
    controller.dispose();
  });

  test(
    'duplicate captures are suppressed while the write is pending',
    () async {
      final service = FakeInboxService();
      final capture = Completer<InboxTask>();
      service.onCapture = (_) => capture.future;
      final controller = InboxController(service);
      final first = controller.capture('task');
      final duplicate = await controller.capture('task');
      expect(duplicate, isFalse);
      expect(service.captureCalls, 1);
      capture.complete(savedTask);
      await first;
      controller.dispose();
    },
  );

  test(
    'capture remains disabled until the post-save refresh completes',
    () async {
      final service = FakeInboxService();
      final refresh = Completer<List<InboxTask>>();
      service.onList = () =>
          service.listCalls == 1 ? Future.value(const []) : refresh.future;
      final controller = InboxController(service);
      await controller.load();
      final capture = controller.capture('task');
      await Future<void>.delayed(Duration.zero);
      expect(service.captureCalls, 1);
      expect(controller.saving, isTrue);
      expect(await controller.capture('task'), isFalse);
      refresh.complete([savedTask]);
      expect(await capture, isTrue);
      expect(controller.saving, isFalse);
      controller.dispose();
    },
  );

  test(
    'unknown write outcome requires refresh and explicit duplicate warning',
    () async {
      final service = FakeInboxService();
      service.onList = () async => [savedTask];
      service.onCapture = (_) {
        if (service.captureCalls == 1) {
          throw const HeapApiException(
            'Capture may have succeeded. Refresh the inbox before submitting again.',
            unknownOutcome: true,
          );
        }
        return Future.value(savedTask);
      };
      final controller = InboxController(service);
      expect(await controller.capture('task'), isFalse);
      expect(controller.tasks, isEmpty);
      expect(controller.unknownOutcome, isTrue);
      expect(controller.duplicateWarning, contains('Refresh the inbox'));
      expect(service.listCalls, 0);
      expect(await controller.capture('task'), isFalse);
      expect(service.captureCalls, 1);

      await controller.load();
      expect(controller.canResubmitAfterUnknown, isTrue);
      expect(controller.duplicateWarning, contains('may create a duplicate'));
      expect(await controller.capture('task'), isFalse);
      expect(service.captureCalls, 1);
      expect(await controller.capture('task', confirmDuplicate: true), isTrue);
      expect(controller.unknownOutcome, isFalse);
      expect(service.captureCalls, 2);
      controller.dispose();
    },
  );

  test('read started before an unknown POST cannot count as its refresh', () async {
    final service = FakeInboxService();
    final oldRead = Completer<List<InboxTask>>();
    service.onList = () =>
        service.listCalls == 1 ? oldRead.future : Future.value([]);
    service.onCapture = (_) => throw const HeapApiException(
      'Capture may have succeeded. Refresh the inbox before submitting again.',
      unknownOutcome: true,
    );
    final controller = InboxController(service);
    final load = controller.load();
    expect(await controller.capture('task'), isFalse);
    oldRead.complete([savedTask]);
    await load;
    expect(controller.loaded, isFalse);
    expect(controller.canResubmitAfterUnknown, isFalse);
    await controller.load();
    expect(controller.canResubmitAfterUnknown, isTrue);
    controller.dispose();
  });

  testWidgets(
    'capture failure preserves the draft; late success preserves newer text',
    (tester) async {
      final service = FakeInboxService();
      var shouldFail = true;
      var serverHasTask = false;
      final pending = Completer<InboxTask>();
      service.onList = () async => serverHasTask ? [savedTask] : [];
      service.onCapture = (title) {
        if (shouldFail) {
          shouldFail = false;
          throw const HeapApiException('The server rejected this request.');
        }
        return pending.future.then((task) {
          serverHasTask = true;
          return task;
        });
      };
      final controller = InboxController(service);
      await tester.pumpWidget(
        MaterialApp(home: InboxPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('task-title')), 'keep me');
      await tester.tap(find.byKey(const Key('capture')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-title')))
            .controller!
            .text,
        'keep me',
      );

      await tester.tap(find.byKey(const Key('capture')));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('capture'))).onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('task-title')),
        'newer draft',
      );
      pending.complete(savedTask);
      await tester.pumpAndSettle();
      expect(find.text('Saved task'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-title')))
            .controller!
            .text,
        'newer draft',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'capture does not clear the stale label before the server responds',
    () async {
      final service = FakeInboxService();
      final pending = Completer<InboxTask>();
      service.onList = () async {
        if (service.listCalls == 1) return [savedTask];
        throw const HeapApiException('Could not reach the server.');
      };
      service.onCapture = (_) => pending.future;
      final controller = InboxController(service);
      await controller.load();
      await controller.load();
      expect(controller.stale, isTrue);
      final capture = controller.capture('Another task');
      expect(controller.stale, isTrue);
      expect(controller.error, 'Could not reach the server.');
      pending.complete(savedTask);
      await capture;
      expect(controller.stale, isTrue);
      expect(
        controller.notice,
        'Capture saved, but the inbox could not be refreshed.',
      );
      controller.dispose();
    },
  );

  test(
    'GET containing a pending capture merges uniquely in oldest-first order',
    () async {
      final older = InboxTask(
        id: '00000000-0000-0000-0000-000000000001',
        title: 'Older task',
        status: 'inbox',
        createdAt: DateTime.utc(2026, 10, 2),
        updatedAt: DateTime.utc(2026, 10, 2),
      );
      final service = FakeInboxService();
      final read = Completer<List<InboxTask>>();
      final write = Completer<InboxTask>();
      service.onList = () {
        if (service.listCalls == 1) return read.future;
        throw const HeapApiException('Could not reach the server.');
      };
      service.onCapture = (_) => write.future;
      final controller = InboxController(service);
      final loading = controller.load();
      final capture = controller.capture('Saved task');
      read.complete([older, savedTask]);
      await loading;
      write.complete(savedTask);
      expect(await capture, isTrue);
      expect(controller.tasks.map((task) => task.id).toList(), [
        older.id,
        savedTask.id,
      ]);
      expect(controller.stale, isTrue);
      expect(
        controller.notice,
        'Capture saved, but the inbox could not be refreshed.',
      );
      controller.dispose();
    },
  );

  test(
    'server-confirmed save remains when the following refresh fails',
    () async {
      final service = FakeInboxService();
      service.onList = () async {
        if (service.listCalls > 1) {
          throw const HeapApiException('Could not reach the server.');
        }
        return const [];
      };
      final controller = InboxController(service);
      await controller.load();
      expect(await controller.capture('Saved task'), isTrue);
      expect(controller.tasks, [savedTask]);
      expect(
        controller.notice,
        'Capture saved, but the inbox could not be refreshed.',
      );
      expect(controller.error, 'Could not reach the server.');
      controller.dispose();
    },
  );

  testWidgets('missing configuration is not shown as an empty inbox', (
    tester,
  ) async {
    await tester.pumpWidget(const HeapApp(configurationError: true));
    expect(find.textContaining('Set a valid server origin'), findsOneWidget);
    expect(find.byKey(const Key('empty-inbox')), findsNothing);
  });
}
