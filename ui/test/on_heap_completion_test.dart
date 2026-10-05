import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/on_heap_controller.dart';
import 'package:heap_app/task_detail.dart';

const id = 'd4be2fc9-49b7-46a6-9981-1f063eed03ea';
TaskDetail task(
  String status, {
  String? token,
  String taskId = id,
  String since = '2026-10-01T12:34:56.123456Z',
}) => TaskDetail.fromJson({
  'id': taskId,
  'title': 'Keep age',
  'status': status,
  'created_at': '2026-10-03T12:34:56.123456Z',
  'updated_at': token ?? '2026-10-03T12:34:56.123456Z',
  'priority': 2,
  'duration_minutes': 30,
  'externally_blocked': false,
  'on_heap_since': since,
  'project_id': null,
  'due_date': null,
});

class Service implements OrganizationService {
  List<TaskDetail> items = [task('on_heap')];
  Future<List<TaskDetail>> Function()? onList;
  Future<TaskDetail> Function(TaskDetail, {required bool completed})? onToggle;
  int puts = 0;
  int gets = 0;
  final localDates = <String>[];
  Future<TaskDetail> Function(String)? onGet;
  @override
  Future<TaskDetail> setCompletion(
    TaskDetail original, {
    required bool completed,
  }) {
    puts++;
    return onToggle?.call(original, completed: completed) ??
        Future.value(
          task(
            completed ? 'completed' : 'on_heap',
            token: '2026-10-04T12:34:56.123456Z',
          ),
        );
  }

  @override
  Future<List<TaskDetail>> listOnHeap({required String localDate}) {
    localDates.add(localDate);
    return onList?.call() ?? Future.value(items);
  }

  @override
  Future<TaskDetail> getTask(String id) {
    gets++;
    return onGet?.call(id) ?? Future.value(task('completed'));
  }

  @override
  Future<TaskDetail> saveOrganization(OrganizationSubmission submission) =>
      throw UnimplementedError();
}

void main() {
  test('each load captures the injected device-local date once', () async {
    var now = DateTime(2026, 10, 5, 23, 59);
    final service = Service();
    final controller = OnHeapController(service, clock: () => now);
    await controller.load();
    now = DateTime(2026, 10, 6, 0, 1);
    await controller.load();
    expect(service.localDates, ['2026-10-05', '2026-10-06']);
    controller.dispose();
  });

  test('load preserves the exact authoritative response order', () async {
    final serverOrder = [
      task(
        'on_heap',
        taskId: '00000000-0000-4000-8000-000000000004',
        since: '2026-09-01T00:00:00.000000Z',
      ),
      task(
        'on_heap',
        taskId: '00000000-0000-4000-8000-000000000003',
        since: '2026-10-03T00:00:00.000000Z',
      ),
      task(
        'on_heap',
        taskId: '00000000-0000-4000-8000-000000000002',
        since: '2026-10-04T00:00:00.000000Z',
      ),
    ];
    final controller = OnHeapController(Service()..items = serverOrder);
    await controller.load();
    expect(
      controller.tasks.map((item) => item.id),
      serverOrder.map((item) => item.id),
    );
    controller.dispose();
  });

  test(
    'confirmed completion and undo preserve row position and task age',
    () async {
      final service = Service()
        ..items = [
          task(
            'on_heap',
            taskId: '00000000-0000-0000-0000-000000000001',
            since: '2026-09-01T12:34:56.123456Z',
          ),
          task('on_heap'),
          task(
            'on_heap',
            taskId: '00000000-0000-0000-0000-000000000003',
            since: '2026-10-02T12:34:56.123456Z',
          ),
        ];
      final controller = OnHeapController(service);
      await controller.load();
      final originalIds = controller.tasks.map((item) => item.id).toList();
      final age = controller.tasks[1].onHeapSince;
      await controller.toggleCompletion(id);
      expect(controller.tasks.map((item) => item.id), originalIds);
      expect(controller.tasks[1].status, 'completed');
      expect(controller.tasks[1].onHeapSince, age);
      await controller.toggleCompletion(id);
      expect(controller.tasks.map((item) => item.id), originalIds);
      expect(controller.tasks[1].status, 'on_heap');
      expect(controller.tasks[1].onHeapSince, age);
      controller.dispose();
    },
  );

  test(
    'pending blocks writes, definite failures allow deliberate retry',
    () async {
      final service = Service();
      final gate = Completer<TaskDetail>();
      service.onToggle = (_, {required completed}) => gate.future;
      final controller = OnHeapController(service);
      await controller.load();
      final write = controller.toggleCompletion(id);
      await controller.toggleCompletion(id);
      expect(service.puts, 1);
      expect(controller.isPending(id), isTrue);
      gate.completeError(const HeapApiException('rejected'));
      await write;
      expect(controller.errorFor(id), 'rejected');
      expect(controller.isPending(id), isFalse);
      controller.dispose();
    },
  );

  test('unknown write stays locked until successful refresh; failed refresh retains row', () async {
    final service = Service();
    final controller = OnHeapController(service);
    await controller.load();
    service.onToggle = (_, {required completed}) =>
        Future.error(const HeapApiException('unknown', unknownOutcome: true));
    await controller.toggleCompletion(id);
    expect(controller.isUncertain(id), isTrue);
    await controller.toggleCompletion(id);
    expect(service.puts, 1);
    service.onList = () => Future.error(const HeapApiException('offline'));
    await controller.load();
    expect(controller.tasks.single.status, 'on_heap');
    expect(controller.isUncertain(id), isTrue);
    service.onList = () async => [];
    await controller.load();
    expect(controller.tasks, isEmpty);
    expect(controller.isUncertain(id), isFalse);
    controller.dispose();
  });

  test(
    'confirmed delayed undo restores task omitted by a successful refresh',
    () async {
      final older = task(
        'on_heap',
        taskId: '00000000-0000-0000-0000-000000000001',
        since: '2026-09-01T12:34:56.123456Z',
      );
      final newer = task(
        'on_heap',
        taskId: '00000000-0000-0000-0000-000000000003',
        since: '2026-10-02T12:34:56.123456Z',
      );
      final service = Service()..items = [newer, task('on_heap'), older];
      final controller = OnHeapController(service);
      await controller.load();
      await controller.toggleCompletion(id);
      final gate = Completer<TaskDetail>();
      service.onToggle = (_, {required completed}) => gate.future;
      final undo = controller.toggleCompletion(id);
      service.items = [older, newer];
      await controller.load();
      gate.complete(task('on_heap', token: '2026-10-05T12:34:56.123456Z'));
      await undo;
      expect(controller.tasks.map((item) => item.id), [older.id, id, newer.id]);
      expect(controller.tasks[1].onHeapSince, task('on_heap').onHeapSince);
      expect(controller.tasks[1].status, 'on_heap');
      expect(controller.stale, isTrue);
      service.items = [older, newer];
      await controller.load();
      expect(controller.tasks.map((item) => item.id), [older.id, id, newer.id]);
      expect(controller.stale, isTrue);
      service.items = [newer, task('on_heap'), older];
      await controller.load();
      expect(controller.tasks.map((item) => item.id), [newer.id, id, older.id]);
      expect(controller.stale, isFalse);
      controller.dispose();
    },
  );

  for (final completed in [true, false]) {
    test(
      'unchanged recovery and stale list keep ${completed ? 'completion' : 'undo'} locked until a matching GET',
      () async {
        final service = Service();
        final controller = OnHeapController(service);
        await controller.load();
        if (!completed) await controller.toggleCompletion(id);
        final prior = task(completed ? 'on_heap' : 'completed');
        service.onToggle = (_, {required completed}) => Future.error(
          const HeapApiException('timeout', unknownOutcome: true),
        );
        await controller.toggleCompletion(id);
        final writes = service.puts;
        service.items = completed ? [task('on_heap')] : [];
        service.onGet = (_) async => prior;
        await controller.load();
        expect(
          service.gets,
          1,
          reason: 'list absence alone cannot confirm completion',
        );
        expect(controller.isUncertain(id), isTrue);
        expect(controller.tasks.single.status, prior.status);
        await controller.toggleCompletion(id);
        expect(service.puts, writes);
        service.onGet = (_) async => task(completed ? 'completed' : 'on_heap');
        await controller.load();
        expect(controller.isUncertain(id), isFalse);
        expect(controller.stale, !completed);
        expect(
          controller.tasks.map((item) => item.status),
          completed ? [] : ['on_heap'],
        );
        expect(service.puts, writes, reason: 'recovery does not repeat PUT');
        if (!completed) {
          service.items = [task('on_heap')];
          await controller.load();
          expect(controller.stale, isFalse);
        }
        controller.dispose();
      },
    );
  }

  test('timed-out PUT can finish after unchanged GET; only a later explicit matching check unlocks', () async {
    final service = Service();
    final controller = OnHeapController(service);
    await controller.load();
    var remote = task('on_heap');
    final response = Completer<void>();
    service.onGet = (_) async => remote;
    service.onToggle = (_, {required completed}) => response.future
        .then((_) {
          remote = task('completed');
          return remote;
        })
        .timeout(
          const Duration(milliseconds: 1),
          onTimeout: () =>
              throw const HeapApiException('timeout', unknownOutcome: true),
        );
    await controller.toggleCompletion(id);
    await controller.checkCompletion(id);
    expect(controller.isUncertain(id), isTrue);
    expect(service.puts, 1);
    response.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      remote.status,
      'completed',
      reason: 'timeout did not cancel server work',
    );
    expect(
      controller.isUncertain(id),
      isTrue,
      reason: 'late response alone does not confirm UI state',
    );
    await controller.checkCompletion(id);
    expect(controller.isUncertain(id), isFalse);
    expect(controller.tasks.single.status, 'completed');
    expect(service.puts, 1);
    controller.dispose();
  });

  test('task GET started before a newer matching refresh cannot resurrect prior state', () async {
    final service = Service();
    final controller = OnHeapController(service);
    await controller.load();
    service.onToggle = (_, {required completed}) async =>
        throw const HeapApiException('unknown', unknownOutcome: true);
    await controller.toggleCompletion(id);
    final oldGet = Completer<TaskDetail>();
    service.onGet = (_) => oldGet.future;
    final check = controller.checkCompletion(id);
    service.onGet = (_) async => task('completed');
    service.items = [];
    await controller.load();
    oldGet.complete(task('on_heap'));
    await check;
    expect(controller.tasks, isEmpty);
    expect(controller.isUncertain(id), isFalse);
    controller.dispose();
  });

  test(
    'recovered undo remains provisional until authoritative list contains it',
    () async {
      const undoId = '00000000-0000-4000-8000-000000000011';
      final service = Service()..items = [task('on_heap', taskId: undoId)];
      final controller = OnHeapController(service);
      await controller.load();
      await controller.toggleCompletion(undoId);
      service.onToggle = (_, {required completed}) =>
          Future.error(const HeapApiException('unknown', unknownOutcome: true));
      await controller.toggleCompletion(undoId);
      service.items = [];
      service.onGet = (_) async => task('on_heap', taskId: undoId);
      await controller.load();
      expect(controller.tasks.single.id, undoId);
      expect(controller.stale, isTrue);
      await controller.load();
      expect(controller.tasks.map((item) => item.id), [undoId]);
      expect(controller.stale, isTrue);
      controller.dispose();
    },
  );

  test('project deletion clears provisional undo snapshots', () async {
    const deletedId = '00000000-0000-4000-8000-000000000012';
    final service = Service()..items = [task('on_heap', taskId: deletedId)];
    final controller = OnHeapController(service);
    await controller.load();
    await controller.toggleCompletion(deletedId);
    final delayedUndo = Completer<TaskDetail>();
    service.onToggle = (_, {required completed}) => delayedUndo.future;
    final undo = controller.toggleCompletion(deletedId);
    controller.clearAfterProjectDeletion();
    service.items = [];
    await controller.load();
    delayedUndo.complete(task('on_heap', taskId: deletedId));
    await undo;
    await controller.load();
    expect(controller.tasks, isEmpty);
    expect(controller.stale, isFalse);
    controller.dispose();
  });

  test('confirmed completion drops provisional snapshot during uncertain-load recovery', () async {
    const completedId = '00000000-0000-4000-8000-000000000013';
    final service = Service()..items = [task('on_heap', taskId: completedId)];
    final controller = OnHeapController(service);
    await controller.load();
    controller.applyConfirmed(task('on_heap', taskId: completedId));
    service.onToggle = (_, {required completed}) =>
        Future.error(const HeapApiException('unknown', unknownOutcome: true));
    await controller.toggleCompletion(completedId);
    service.items = [];
    service.onGet = (_) async => task('completed', taskId: completedId);
    await controller.load();
    expect(controller.tasks, isEmpty);
    await controller.load();
    expect(controller.tasks, isEmpty);
    controller.dispose();
  });

  test('explicit completion check drops provisional snapshot', () async {
    const checkedId = '00000000-0000-4000-8000-000000000014';
    final service = Service()..items = [task('on_heap', taskId: checkedId)];
    final controller = OnHeapController(service);
    await controller.load();
    controller.applyConfirmed(task('on_heap', taskId: checkedId));
    service.onToggle = (_, {required completed}) =>
        Future.error(const HeapApiException('unknown', unknownOutcome: true));
    await controller.toggleCompletion(checkedId);
    service.onGet = (_) async => task('completed', taskId: checkedId);
    await controller.checkCompletion(checkedId);
    service.items = [];
    await controller.load();
    expect(controller.tasks, isEmpty);
    controller.dispose();
  });

  test('old list response cannot overwrite confirmed completion', () async {
    final service = Service();
    final controller = OnHeapController(service);
    await controller.load();
    final oldRead = Completer<List<TaskDetail>>();
    service.onList = () => oldRead.future;
    final pendingRead = controller.load();
    await controller.toggleCompletion(id);
    oldRead.complete([task('on_heap')]);
    await pendingRead;
    expect(controller.tasks.single.status, 'completed');
    controller.dispose();
  });
}
