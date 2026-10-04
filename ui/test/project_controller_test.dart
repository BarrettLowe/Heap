import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_api.dart';
import 'package:heap_app/project.dart';
import 'package:heap_app/project_controller.dart';

import 'project_fakes.dart';

void main() {
  test(
    'latest list read wins and confirmed writes invalidate old reads',
    () async {
      final service = FakeProjects();
      final c = ProjectsController(service);
      final old = Completer<List<Project>>();
      service.onList = () => old.future;
      final pending = c.load();
      service.onList = () async => [project(name: 'Fresh')];
      await c.load();
      old.complete([project(name: 'Old')]);
      await pending;
      expect(c.projects.single.name, 'Fresh');
      final older = Completer<List<Project>>();
      service.onList = () => older.future;
      final refresh = c.load();
      c.applyConfirmed(project(name: 'Saved'));
      older.complete([project(name: 'Old')]);
      await refresh;
      expect(c.projects.single.name, 'Saved');
      c.dispose();
    },
  );
  test('failed refresh keeps previous projects and marks them stale', () async {
    final service = FakeProjects();
    final c = ProjectsController(service);
    await c.load();
    service.onList = () async => throw const HeapApiException('offline');
    await c.load();
    expect(c.projects.single.name, 'Garden');
    expect(c.stale, true);
    expect(c.error, 'offline');
    c.removeConfirmed(projectId);
    await c.load();
    expect(c.projects, isEmpty);
    c.dispose();
  });
  test(
    'editor latest GET wins, and validation failure keeps picker draft',
    () async {
      final service = FakeProjects();
      final c = ProjectEditorController(service, projectId);
      final old = Completer<Project>();
      service.onGet = (_) => old.future;
      final first = c.load();
      service.onGet = (_) async => project(name: 'Fresh');
      await c.load();
      old.complete(project(name: 'Old'));
      await first;
      expect(c.draft!.name, 'Fresh');
      c.edit(name: ' ', color: '#468BBB', setColor: true);
      expect(await c.save(), isNull);
      expect(c.fieldErrors['name'], 'Enter a project name.');
      expect(c.draft!.color, '#468BBB');
      expect(service.writes, 0);
      c.dispose();
    },
  );
  test('editor fetches detail; retains arbitrary values, blocks pending duplicates', () async {
    final service = FakeProjects()
      ..onGet = (_) async => Project.fromJson({
        ...projectJson(),
        'color': 'custom',
        'icon': 'other',
      });
    final c = ProjectEditorController(service, projectId);
    await c.load();
    c.edit(name: 'Renamed');
    expect(c.draft!.color, 'custom');
    final pending = Completer<Project>();
    service.onSave = (_, _) => pending.future;
    final save = c.save();
    expect(c.pending, true);
    expect(await c.save(), isNull);
    pending.complete(project(name: 'Renamed'));
    expect(await save, isNotNull);
    expect(service.writes, 1);
    expect(service.lastOriginal!.description, 'Keep this description');
    c.dispose();
  });
  for (final id in [null, projectId]) {
    test('save 404 only marks existing project unavailable: $id', () async {
      final service = FakeProjects()
        ..onSave = (_, _) async =>
            throw const HeapApiException('Rejected', statusCode: 404);
      final c = ProjectEditorController(service, id);
      addTearDown(c.dispose);
      await c.load();
      c.edit(
        name: 'Draft',
        color: 'custom',
        icon: 'home-outline',
        setColor: true,
        setIcon: true,
      );
      expect(await c.save(), isNull);
      expect(c.draft!.name, 'Draft');
      expect(c.draft!.color, 'custom');
      expect(c.draft!.icon, 'home-outline');
      expect(c.missing, id != null);
      expect(c.canSave, id == null);
      expect(c.uncertain, false);
      expect(c.error, 'Rejected');
      if (id == null) {
        expect(await c.save(), isNull);
        expect(service.writes, 2);
        expect(service.gets, 0);
        expect(service.lists, 0);
      }
    });
  }
  test(
    'uncertain create checks list without inferring success or auto resubmit',
    () async {
      final service = FakeProjects()
        ..onSave = (_, _) async =>
            throw const HeapApiException('unknown', unknownOutcome: true);
      final c = ProjectEditorController(service, null);
      c.edit(name: 'Garden', color: 'custom', setColor: true);
      await c.save();
      expect(c.uncertain, true);
      expect(await c.save(), isNull);
      await c.check();
      expect(service.lists, 1);
      expect(service.writes, 1);
      expect(c.draft!.name, 'Garden');
      expect(c.uncertain, true);
      expect(c.checked, true);
      c.dispose();
    },
  );
  test(
    'uncertain edit checks GET and missing delete is not confirmed deletion',
    () async {
      final service = FakeProjects();
      final c = ProjectEditorController(service, projectId);
      await c.load();
      c.edit(icon: 'home-outline', setIcon: true);
      expect(c.dirty, true);
      service.onDelete = (_) async =>
          throw const HeapApiException('unknown', unknownOutcome: true);
      expect(await c.delete(), false);
      service.onGet = (_) async =>
          throw const HeapApiException('gone', statusCode: 404);
      await c.check();
      expect(c.missing, true);
      expect(c.uncertain, true);
      expect(c.draft!.icon, 'home-outline');
      expect(service.deletes, 1);
      c.dispose();
    },
  );
}
