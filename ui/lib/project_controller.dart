import 'package:flutter/foundation.dart';

import 'heap_api.dart';
import 'project.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController(this.service);
  final ProjectService service;
  List<Project> projects = const [];
  bool loading = false;
  bool loaded = false;
  bool stale = false;
  String? error;
  int _readVersion = 0;
  bool _disposed = false;

  Future<void> load() async {
    final version = ++_readVersion;
    loading = true;
    _notify();
    try {
      final result = await service.listProjects();
      if (_disposed || version != _readVersion) return;
      projects = result;
      loaded = true;
      stale = false;
      error = null;
    } on HeapApiException catch (failure) {
      if (_disposed || version != _readVersion) return;
      error = failure.message;
      stale = loaded;
    }
    if (_disposed || version != _readVersion) return;
    loading = false;
    _notify();
  }

  void applyConfirmed(Project project) {
    ++_readVersion;
    loading = false;
    final merged = [...projects.where((item) => item.id != project.id), project]
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    projects = List.unmodifiable(merged);
    loaded = true;
    stale = true;
    error = null;
    _notify();
  }

  void removeConfirmed(String id) {
    ++_readVersion;
    loading = false;
    projects = List.unmodifiable(projects.where((item) => item.id != id));
    stale = loaded;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ProjectEditorController extends ChangeNotifier {
  ProjectEditorController(this.service, this.id) {
    if (id == null) draft = const ProjectDraft();
  }
  final ProjectService service;
  final String? id;
  Project? saved;
  ProjectDraft? draft;
  bool loading = false;
  bool pending = false;
  bool deleting = false;
  bool missing = false;
  bool uncertain = false;
  bool checked = false;
  String? error;
  String? checkNotice;
  List<Project>? checkedProjects;
  Map<String, String> fieldErrors = const {};
  int _readVersion = 0;
  bool _disposed = false;

  bool get dirty =>
      draft != null &&
      !draft!.matches(
        saved == null ? const ProjectDraft() : ProjectDraft.fromProject(saved!),
      );
  bool get editable => draft != null && !loading && !pending && !missing;
  bool get canSave => editable && (!uncertain || checked);

  Future<void> load() async {
    if (id == null || pending) return;
    final version = ++_readVersion;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await service.getProject(id!);
      if (_disposed || version != _readVersion) return;
      saved = result;
      draft ??= ProjectDraft.fromProject(result);
      missing = false;
    } on HeapApiException catch (failure) {
      if (_disposed || version != _readVersion) return;
      missing = failure.statusCode == 404;
      error = failure.message;
    }
    if (_disposed || version != _readVersion) return;
    loading = false;
    _notify();
  }

  void edit({
    String? name,
    String? color,
    String? icon,
    bool setColor = false,
    bool setIcon = false,
  }) {
    if (!editable) return;
    draft = ProjectDraft(
      name: name ?? draft!.name,
      color: setColor ? color : draft!.color,
      icon: setIcon ? icon : draft!.icon,
    );
    fieldErrors = const {};
    error = null;
    _notify();
  }

  Future<Project?> save({bool confirmUncertain = false}) async {
    if (!canSave || (uncertain && !confirmUncertain)) return null;
    if (draft!.name.trim().isEmpty) {
      fieldErrors = const {'name': 'Enter a project name.'};
      _notify();
      return null;
    }
    pending = true;
    checked = false;
    error = null;
    fieldErrors = const {};
    ++_readVersion;
    _notify();
    try {
      final result = await service.saveProject(draft!, original: saved);
      if (_disposed) return null;
      uncertain = false;
      pending = false;
      _notify();
      return result;
    } on HeapApiException catch (failure) {
      if (_disposed) return null;
      _failed(failure);
      return null;
    }
  }

  Future<bool> delete() async {
    if (!editable || saved == null || (uncertain && !checked)) return false;
    pending = true;
    deleting = true;
    checked = false;
    error = null;
    ++_readVersion;
    _notify();
    try {
      await service.deleteProject(id!);
      if (_disposed) return false;
      pending = false;
      deleting = false;
      uncertain = false;
      _notify();
      return true;
    } on HeapApiException catch (failure) {
      if (_disposed) return false;
      _failed(failure, deletion: true);
      return false;
    }
  }

  void _failed(HeapApiException failure, {bool deletion = false}) {
    pending = false;
    deleting = false;
    uncertain = uncertain || failure.unknownOutcome;
    missing = id != null && failure.statusCode == 404;
    error = failure.unknownOutcome
        ? null
        : deletion
        ? 'Could not delete this project.'
        : failure.message;
    fieldErrors = failure.fieldErrors;
    _notify();
  }

  Future<void> check() async {
    if (!uncertain || pending || loading) return;
    final version = ++_readVersion;
    loading = true;
    checked = false;
    error = null;
    checkNotice = null;
    _notify();
    try {
      if (id == null) {
        final result = await service.listProjects();
        if (_disposed || version != _readVersion) return;
        checkedProjects = result;
        checkNotice = 'Projects checked. A matching name does not confirm creation. Saving again may create a duplicate.';
      } else {
        final result = await service.getProject(id!);
        if (_disposed || version != _readVersion) return;
        saved = result;
        missing = false;
        checkNotice =
            'Saved project: ${result.name}\nColor: ${result.color ?? 'None'}\nIcon: ${result.icon ?? 'None'}\nThe earlier request may still finish. Your draft has not been changed.';
      }
      checked = true;
    } on HeapApiException catch (failure) {
      if (_disposed || version != _readVersion) return;
      missing = id != null && failure.statusCode == 404;
      error = missing ? null : 'Could not check projects.';
      if (missing) checkNotice = 'The project is unavailable. This does not confirm that deletion succeeded.';
    }
    if (_disposed || version != _readVersion) return;
    loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_readVersion;
    super.dispose();
  }
}
