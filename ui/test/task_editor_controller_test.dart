import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';
import 'package:heap_app/task_editor_controller.dart';

import 'task_flow_fakes.dart';

const unknown = HeapApiException('Unknown save', unknownOutcome: true);
void main() {
  test('uncertain waiting-only Save matches all fields only after fetched waiting agrees', () async {
    final service = FakeOrganization();
    service.onGet = (_) async => detail(priority: 2, duration: 30);
    service.onSave = (_) => throw unknown;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(externallyBlocked: true);
    await c.save();
    await c.reconcile();
    expect(c.matching, isNull);
    expect(c.uncertain, true);
    expect(c.draft!.externallyBlocked, true);
    service.onGet = (_) async =>
        detail(priority: 2, duration: 30, waiting: true);
    await c.reconcile();
    expect(c.matching!.externallyBlocked, true);
    expect(c.matching!.status, 'on_heap');
    expect(c.uncertain, false);
    expect(service.puts, 1);
    c.dispose();
  });
  for (final association in [
    (null, assignedProjectId),
    (assignedProjectId, null),
    (assignedProjectId, reassignedProjectId),
  ]) {
    final originalProjectId = association.$1;
    test(
      'unknown Save cannot match reassignment from $originalProjectId to ${association.$2}',
      () async {
        final service = FakeOrganization();
        service.onGet = (_) async => detail(projectId: originalProjectId);
        service.onSave = (_) => throw unknown;
        final c = TaskEditorController(service, taskId);
        await c.load();
        c.edit(title: 'My edits');
        await c.save();
        service.onGet = (_) async =>
            detail(title: 'My edits', projectId: association.$2);
        await c.reconcile();
        expect(c.matching, isNull);
        expect(c.uncertain, true);
        expect(c.needsChoice, true);
        expect(service.puts, 1);
        service.onGet = (_) async =>
            detail(title: 'My edits', projectId: originalProjectId);
        await c.reconcile();
        expect(c.matching!.projectId, originalProjectId);
        expect(c.uncertain, false);
        expect(service.puts, 1);
        c.dispose();
      },
    );
  }
  test('deliberate retry keeps edits and preserves association from fresh comparison', () async {
    final service = FakeOrganization();
    service.onGet = (_) async => detail(projectId: assignedProjectId);
    service.onSave = (_) => throw unknown;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(title: 'My edits');
    await c.save();
    service.onGet = (_) async => detail(
      title: 'Remote',
      projectId: reassignedProjectId,
      updated: '2026-10-04T12:34:56.000000Z',
    );
    await c.reconcile();
    c.chooseVersion(keepEdits: true);
    service.onSave = null;
    final saved = await c.save();
    expect(saved!.title, 'My edits');
    expect(saved.projectId, assignedProjectId);
    expect(service.lastSubmission!.toJson()['project_id'], assignedProjectId);
    expect(
      service.lastSubmission!.toJson()['expected_updated_at'],
      '2026-10-04T12:34:56.000000Z',
    );
    c.dispose();
  });
  test('Use saved version adopts all 4 fields but does not prove an uncertain prior write failed', () async {
    final service = FakeOrganization()..onSave = (_) => throw unknown;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(title: 'Local');
    await c.save();
    service.onGet = (_) async =>
        detail(title: 'Remote', priority: 2, duration: 30, waiting: true);
    await c.reconcile();
    c.chooseVersion(keepEdits: false);
    expect(c.draft!.title, 'Remote');
    expect(c.draft!.priority, 2);
    expect(c.draft!.durationMinutes, 30);
    expect(c.draft!.externallyBlocked, true);
    expect(c.dirty, false);
    expect(c.uncertain, true);
    expect(service.puts, 1);
    c.dispose();
  });
  test('project reassignment and clearing are dirty and submitted', () async {
    final service = FakeOrganization()
      ..onGet = (_) async => detail(projectId: assignedProjectId);
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(projectId: reassignedProjectId, setProject: true);
    expect(c.dirty, true);
    expect(service.puts, 0);
    expect((await c.save())!.projectId, reassignedProjectId);
    expect(service.lastSubmission!.toJson()['project_id'], reassignedProjectId);
    c.edit(projectId: null, setProject: true);
    expect(c.dirty, true);
    expect((await c.save())!.projectId, isNull);
    expect(service.lastSubmission!.toJson()['project_id'], isNull);
    c.dispose();
  });

  test('waiting-only draft is dirty; atomic Save stays organized independently of waiting', () async {
    final service = FakeOrganization()
      ..onGet = (_) async => detail(priority: 2, duration: 30);
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(externallyBlocked: true);
    expect(c.dirty, true);
    expect(service.puts, 0);
    final saved = await c.save();
    expect(saved!.status, 'on_heap');
    expect(saved.externallyBlocked, true);
    expect(service.lastSubmission!.toJson()['externally_blocked'], true);
    c.edit(externallyBlocked: false);
    expect((await c.save())!.status, 'on_heap');
    c.dispose();
  });
  test('waiting-only conflict keeps all 4 local fields and adopts only fresh token/status', () async {
    final service = FakeOrganization()
      ..onSave = (_) => throw const HeapApiException(
        'Conflict',
        statusCode: 409,
        code: 'task_conflict',
      );
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(externallyBlocked: true);
    await c.save();
    service.onGet = (_) async => detail(
      title: 'Remote',
      priority: 2,
      duration: 30,
      waiting: false,
      updated: '2026-10-04T12:34:56.000000Z',
    );
    await c.reconcile();
    c.chooseVersion(keepEdits: true);
    expect(c.draft!.title, 'Existing task');
    expect(c.draft!.priority, isNull);
    expect(c.draft!.durationMinutes, isNull);
    expect(c.draft!.externallyBlocked, true);
    expect(c.saved!.status, 'on_heap');
    expect(c.saved!.updatedAtToken, '2026-10-04T12:34:56.000000Z');
    expect(c.notice, contains('awaiting flag'));
    expect(c.notice, contains('project'));
    expect(service.puts, 1);
    c.dispose();
  });
  test('fresh detail only and valid unchanged organized Save', () async {
    final service = FakeOrganization();
    final pending = Completer<TaskDetail>();
    service.onGet = (_) => pending.future;
    final c = TaskEditorController(service, taskId);
    final load = c.load();
    expect(c.draft, isNull);
    expect(c.canSave, false);
    pending.complete(detail(priority: 2, duration: 30));
    await load;
    expect(c.dirty, false);
    expect(c.canSave, true);
    final saved = await c.save();
    expect(saved!.status, 'on_heap');
    expect(
      service.lastSubmission!.original.updatedAtToken,
      '2026-10-03T12:34:56.000000Z',
    );
    c.dispose();
  });

  test('pending save freezes inputs and suppresses duplicate PUT', () async {
    final service = FakeOrganization();
    final pending = Completer<TaskDetail>();
    service.onSave = (_) => pending.future;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(title: 'Changed');
    final save = c.save();
    c.edit(title: 'Later');
    expect(c.draft!.title, 'Changed');
    expect(await c.save(), isNull);
    expect(service.puts, 1);
    pending.complete(detail(title: 'Changed'));
    await save;
    expect(c.saving, false);
    c.dispose();
  });

  test('clearing requirements returns to the inbox; restoring them returns to the heap', () async {
    final service = FakeOrganization()
      ..onGet = (_) async =>
          detail(status: 'on_heap', priority: 2, duration: 30);
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(priority: null, setPriority: true);
    expect(c.canSave, true);
    expect((await c.save())!.status, 'inbox');
    expect(service.lastSubmission!.toJson()['priority'], isNull);
    c.edit(priority: 2, setPriority: true);
    expect((await c.save())!.status, 'on_heap');
    c.dispose();
  });

  test('rejected validation retains draft and exposes field errors', () async {
    final service = FakeOrganization()
      ..onSave = (_) => throw const HeapApiException(
        'Rejected',
        statusCode: 422,
        code: 'invalid_request',
        fieldErrors: {'title': 'Invalid title'},
      );
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(title: 'Changed');
    expect(await c.save(), isNull);
    expect(c.draft!.title, 'Changed');
    expect(c.fieldErrors['title'], 'Invalid title');
    expect(c.canSave, true);
    c.edit(title: 'Correction');
    expect(c.fieldErrors, isEmpty);
    c.dispose();
  });

  test(
    'conflict holds draft until explicit known-ID reconciliation choice',
    () async {
      final service = FakeOrganization()
        ..onSave = (_) => throw const HeapApiException(
          'Conflict',
          statusCode: 409,
          code: 'task_conflict',
        );
      final c = TaskEditorController(service, taskId);
      await c.load();
      c.edit(title: 'My title');
      await c.save();
      expect(c.conflict, true);
      expect(c.editable, false);
      service.onGet = (id) async {
        expect(id, taskId);
        return detail(
          title: 'Remote',
          status: 'on_heap',
          priority: 3,
          duration: 15,
          updated: '2026-10-04T12:34:56.123000Z',
        );
      };
      await c.reconcile();
      expect(c.draft!.title, 'My title');
      expect(c.canSave, false);
      c.chooseVersion(keepEdits: true);
      expect(c.canSave, true);
      expect(c.saved!.status, 'on_heap');
      expect(c.draft!.priority, isNull);
      expect(c.saved!.updatedAtToken, '2026-10-04T12:34:56.123000Z');
      expect(service.puts, 1);
      c.dispose();
    },
  );

  test('unknown PUT matching desired status enables return without any second write', () async {
    final service = FakeOrganization()..onSave = (_) => throw unknown;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(
      title: ' My title ',
      priority: 2,
      setPriority: true,
      durationMinutes: 30,
      setDuration: true,
    );
    await c.save();
    expect(c.uncertain, true);
    expect(c.canSave, false);
    service.onGet = (_) async =>
        detail(title: 'My title', status: 'on_heap', priority: 2, duration: 30);
    await c.reconcile();
    expect(c.matching!.status, 'on_heap');
    expect(c.uncertain, false);
    expect(c.dirty, false);
    expect(c.draft!.title, ' My title ');
    expect(service.puts, 1);
    expect(c.canSave, false);
    c.dispose();
  });

  test('matching qualification but different waiting does not confirm uncertain Save', () async {
    final service = FakeOrganization()..onSave = (_) => throw unknown;
    final c = TaskEditorController(service, taskId);
    await c.load();
    c.edit(
      priority: 2,
      setPriority: true,
      durationMinutes: 30,
      setDuration: true,
    );
    await c.save();
    service.onGet = (_) async =>
        detail(priority: 2, duration: 30, waiting: true);
    await c.reconcile();
    expect(c.matching, isNull);
    expect(c.needsChoice, true);
    c.chooseVersion(keepEdits: true);
    expect(c.uncertain, true);
    expect(c.canSave, true);
    expect(c.draft!.externallyBlocked, false);
    expect(c.saved!.externallyBlocked, true);
    expect(service.puts, 1);
    c.dispose();
  });

  test('unchanged reconciliation never proves failure; either choice preserves uncertainty', () async {
    for (final keep in [false, true]) {
      final service = FakeOrganization()..onSave = (_) => throw unknown;
      final c = TaskEditorController(service, taskId);
      await c.load();
      c.edit(title: 'My edits');
      await c.save();
      await c.reconcile();
      expect(c.matching, isNull);
      c.chooseVersion(keepEdits: keep);
      expect(c.uncertain, true);
      expect(c.editable, true);
      expect(c.draft!.title, keep ? 'My edits' : 'Existing task');
      expect(service.puts, 1);
      c.dispose();
    }
  });

  test('unavailable, missing and completed reconciliation preserve drafts and block writes', () async {
    for (final result in ['unavailable', 'missing', 'completed']) {
      final service = FakeOrganization()..onSave = (_) => throw unknown;
      final c = TaskEditorController(service, taskId);
      await c.load();
      c.edit(title: 'My edits');
      await c.save();
      service.onGet = (_) async {
        if (result == 'completed') {
          return detail(title: 'Completed saved title', status: 'completed');
        }
        throw HeapApiException(
          'Unavailable',
          statusCode: result == 'missing' ? 404 : null,
        );
      };
      await c.reconcile();
      expect(c.draft!.title, 'My edits');
      expect(c.uncertain, true);
      expect(c.canSave, false);
      expect(c.matching, isNull);
      expect(service.puts, 1);
      if (result == 'missing') expect(c.missing, true);
      if (result == 'completed') expect(c.completed, true);
      c.dispose();
    }
  });

  test('missing and completed initial detail cannot be saved', () async {
    for (final missing in [false, true]) {
      final service = FakeOrganization()
        ..onGet = (_) async {
          if (missing) throw const HeapApiException('Missing', statusCode: 404);
          return detail(status: 'completed');
        };
      final c = TaskEditorController(service, taskId);
      await c.load();
      expect(c.canSave, false);
      expect(await c.save(), isNull);
      expect(service.puts, 0);
      c.dispose();
    }
  });

  test(
    'disposed detail, reconciliation and save completions never notify',
    () async {
      for (final phase in ['load', 'reconcile', 'save']) {
        final service = FakeOrganization();
        final c = TaskEditorController(service, taskId);
        final pending = Completer<TaskDetail>();
        Future<Object?> operation;
        if (phase == 'load') {
          service.onGet = (_) => pending.future;
          operation = c.load();
        } else {
          await c.load();
          if (phase == 'reconcile') {
            service.onSave = (_) => throw unknown;
            await c.save();
            service.onGet = (_) => pending.future;
            operation = c.reconcile();
          } else {
            service.onSave = (_) => pending.future;
            operation = c.save();
          }
        }
        c.dispose();
        pending.complete(detail());
        await operation;
      }
    },
  );
}
