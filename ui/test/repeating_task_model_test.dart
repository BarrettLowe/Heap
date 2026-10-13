import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/repeat_rule.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_editor_controller.dart';

import 'task_flow_fakes.dart';

void main() {
  group('repeat response metadata', () {
    test(
      'requires repeat and accepts null or canonical positive interval strings',
      () {
        expect(
          InboxTask.fromJson({...detailJson(), 'repeat': null}).repeat,
          isNull,
        );
        for (final repeat in [
          {'unit': 'days', 'interval': '14'},
          {'unit': 'months', 'interval': '1'},
        ]) {
          expect(
            InboxTask.fromJson({...detailJson(), 'repeat': repeat}).repeat,
            RepeatRule.fromJson(repeat),
          );
        }
        final missing = detailJson()..remove('repeat');
        expect(() => InboxTask.fromJson(missing), throwsFormatException);
      },
    );

    test('rejects malformed or non-strict repeat values', () {
      for (final invalid in <Object?>[
        {'unit': 'weeks', 'interval': '1'},
        {'unit': 'days', 'interval': '0'},
        {'unit': 'days', 'interval': '-1'},
        {'unit': 'days', 'interval': '+1'},
        {'unit': 'days', 'interval': '01'},
        {'unit': 'days', 'interval': ' 1'},
        {'unit': 'days', 'interval': '1 '},
        {'unit': 'days', 'interval': '1.0'},
        {'unit': 'days', 'interval': '1e0'},
        {'unit': 'days', 'interval': ''},
        {'unit': 'days', 'interval': 1},
        {'unit': 'days', 'interval': 1.0},
        {'unit': 'days', 'interval': 1e0},
        {'unit': 'days', 'interval': true},
        {'unit': 'days', 'interval': '1', 'extra': true},
        {'unit': 'days'},
        [],
        'days',
      ]) {
        expect(
          () => InboxTask.fromJson({...detailJson(), 'repeat': invalid}),
          throwsFormatException,
        );
      }
    });

    test('rejects numeric JSON tokens for intervals', () {
      for (final json in [
        '{"unit":"days","interval":1}',
        '{"unit":"days","interval":1.0}',
        '{"unit":"days","interval":1e0}',
      ]) {
        expect(
          () => RepeatRule.fromJson(jsonDecode(json)),
          throwsFormatException,
          reason: json,
        );
      }
    });

    test('repeat value has value equality and stable JSON', () {
      final repeat = RepeatRule(unit: 'months', interval: '2');
      expect(repeat, RepeatRule(unit: 'months', interval: '2'));
      expect(repeat.toJson(), {'unit': 'months', 'interval': '2'});
    });
  });

  test(
    'repeat survives detail snapshots and is included in organization writes',
    () {
      final task = TaskDetail.fromJson({
        ...detailJson(priority: 2, duration: 30),
        'repeat': {'unit': 'days', 'interval': '14'},
      });
      final draft = OrganizationDraft.fromTask(task);
      expect(draft.repeat, task.repeat);
      expect(
        task,
        isNot(
          TaskDetail.fromJson({
            ...detailJson(priority: 2, duration: 30),
            'repeat': {'unit': 'days', 'interval': '13'},
          }),
        ),
      );
      final submission = OrganizationSubmission(original: task, draft: draft);
      expect(submission.matches(task), isTrue);
      expect(submission.toJson()['repeat'], {'unit': 'days', 'interval': '14'});
    },
  );

  test('repeat drafts save, cancel, and reject raw invalid intervals without losing text', () async {
    final service = FakeOrganization()
      ..onGet = (_) async => detail(
        repeat: RepeatRule(unit: 'days', interval: '2'),
      );
    final controller = TaskEditorController(service, taskId);
    await controller.load();
    controller.edit(repeatIntervalText: '3', setRepeatInterval: true);
    expect(controller.dirty, true);
    expect(controller.canSave, true);
    expect(
      (await controller.save())!.repeat,
      RepeatRule(unit: 'days', interval: '3'),
    );
    expect(service.lastSubmission!.toJson()['repeat'], {
      'unit': 'days',
      'interval': '3',
    });

    for (final raw in [
      '',
      '0',
      '-1',
      '1.2',
      '1e3',
      '01',
      '+1',
      ' 1',
      '1 ',
      'garbage',
    ]) {
      controller.edit(repeatIntervalText: raw, setRepeatInterval: true);
      expect(controller.dirty, true, reason: raw);
      expect(controller.canSave, false, reason: raw);
      expect(controller.draft!.repeatIntervalText, raw);
      expect(
        controller.draft!.sameFields(
          OrganizationDraft.fromTask(controller.saved!),
        ),
        isFalse,
      );
      expect(
        () => OrganizationSubmission(
          original: controller.saved!,
          draft: controller.draft!,
        ).toJson(),
        throwsFormatException,
      );
    }
    controller.edit(setRepeatUnit: true, repeatUnit: null);
    expect(controller.draft!.repeat, isNull);
    expect(controller.canSave, true);
    controller.dispose();
  });

  test(
    'large canonical intervals remain exact in list, detail, draft, and Off',
    () async {
      final intervals = ['9007199254740993', List.filled(400, '9').join()];
      for (final interval in intervals) {
        final repeat = RepeatRule(unit: 'months', interval: interval);
        expect(
          InboxTask.fromJson({...detailJson(), 'repeat': repeat.toJson()})
              .repeat,
          repeat,
        );
        expect(
          TaskDetail.fromJson({...detailJson(), 'repeat': repeat.toJson()})
              .repeat,
          repeat,
        );

        final service = FakeOrganization();
        final controller = TaskEditorController(service, taskId);
        await controller.load();
        controller.edit(
          repeatUnit: 'months',
          setRepeatUnit: true,
          repeatIntervalText: interval,
          setRepeatInterval: true,
        );
        expect(controller.canSave, true);
        final submission = OrganizationSubmission(
          original: controller.saved!,
          draft: controller.draft!,
        );
        expect(
          (submission.toJson()['repeat'] as Map<String, Object?>)['interval'],
          interval,
        );
        expect((await controller.save())!.repeat!.interval, interval);
        controller.edit(setRepeatUnit: true, repeatUnit: null);
        expect(controller.draft!.repeat, isNull);
        expect(controller.canSave, true);
        controller.dispose();
      }
    },
  );

  test(
    'repeat validation rejection preserves the submitted interval draft',
    () async {
      final service = FakeOrganization()
        ..onSave = (_) => throw const HeapApiException(
          'Rejected',
          statusCode: 422,
          code: 'invalid_request',
          fieldErrors: {'repeat': 'Invalid repeat rule.'},
        );
      final controller = TaskEditorController(service, taskId);
      await controller.load();
      controller.edit(
        repeatUnit: 'days',
        setRepeatUnit: true,
        repeatIntervalText: '8',
        setRepeatInterval: true,
      );
      expect(await controller.save(), isNull);
      expect(controller.draft!.repeatIntervalText, '8');
      expect(controller.draft!.repeat, RepeatRule(unit: 'days', interval: '8'));
      expect(controller.fieldErrors['repeat'], 'Invalid repeat rule.');
      controller.dispose();
    },
  );

  test('uncertain repeat save only matches a fresh task with the submitted recurrence', () async {
    final service = FakeOrganization()
      ..onSave = (_) =>
          throw const HeapApiException('Unknown save', unknownOutcome: true);
    final controller = TaskEditorController(service, taskId);
    await controller.load();
    controller.edit(
      repeatUnit: 'months',
      setRepeatUnit: true,
      repeatIntervalText: '2',
      setRepeatInterval: true,
    );
    await controller.save();
    service.onGet = (_) async => detail(
      repeat: RepeatRule(unit: 'months', interval: '2'),
    );
    await controller.reconcile();
    expect(
      controller.matching?.repeat,
      RepeatRule(unit: 'months', interval: '2'),
    );
    expect(controller.uncertain, false);
    expect(service.puts, 1);
    controller.dispose();
  });

  test(
    'Use saved version adopts the fetched repeat without resolving uncertainty',
    () async {
      final service = FakeOrganization()
        ..onSave = (_) =>
            throw const HeapApiException('Unknown save', unknownOutcome: true);
      final controller = TaskEditorController(service, taskId);
      await controller.load();
      controller.edit(
        repeatUnit: 'months',
        setRepeatUnit: true,
        repeatIntervalText: '2',
        setRepeatInterval: true,
      );
      await controller.save();
      service.onGet = (_) async => detail(
        repeat: RepeatRule(unit: 'days', interval: '7'),
      );
      await controller.reconcile();
      controller.chooseVersion(keepEdits: false);
      expect(controller.draft!.repeat, RepeatRule(unit: 'days', interval: '7'));
      expect(controller.dirty, false);
      expect(controller.uncertain, true);
      expect(service.puts, 1);
      controller.dispose();
    },
  );

  test('repeat conflict preserves local choice and adopts the new comparison token', () async {
    final service = FakeOrganization()
      ..onSave = (_) => throw const HeapApiException(
        'Conflict',
        statusCode: 409,
        code: 'task_conflict',
      );
    final controller = TaskEditorController(service, taskId);
    await controller.load();
    controller.edit(
      repeatUnit: 'months',
      setRepeatUnit: true,
      repeatIntervalText: '3',
      setRepeatInterval: true,
    );
    expect(await controller.save(), isNull);
    service.onGet = (_) async => detail(
      repeat: RepeatRule(unit: 'days', interval: '7'),
      updated: '2026-10-04T12:34:56.000000Z',
    );
    await controller.reconcile();
    controller.chooseVersion(keepEdits: true);
    expect(controller.draft!.repeat, RepeatRule(unit: 'months', interval: '3'));
    expect(controller.saved!.repeat, RepeatRule(unit: 'days', interval: '7'));
    expect(controller.dirty, true);
    expect(controller.canSave, true);
    controller.dispose();
  });
}
