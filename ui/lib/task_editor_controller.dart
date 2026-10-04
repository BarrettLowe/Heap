import 'package:flutter/foundation.dart';

import 'heap_api.dart';
import 'task_detail.dart';

class TaskEditorController extends ChangeNotifier {
  TaskEditorController(this._api, this.id);
  final OrganizationService _api;
  final String id;
  TaskDetail? saved;
  OrganizationDraft? draft;
  OrganizationSubmission? submitted;
  TaskDetail? comparison;
  TaskDetail? matching;
  bool loading = false;
  bool saving = false;
  bool uncertain = false;
  bool conflict = false;
  bool needsChoice = false;
  bool missing = false;
  String? error;
  String? notice;
  Map<String, String> fieldErrors = const {};
  int _readVersion = 0;
  bool _disposed = false;

  bool get completed =>
      saved?.status == 'completed' || comparison?.status == 'completed';
  bool get dirty =>
      matching == null &&
      draft != null &&
      saved != null &&
      !draft!.sameFields(OrganizationDraft.fromTask(saved!));
  bool get editable =>
      saved != null &&
      draft != null &&
      !missing &&
      !completed &&
      !loading &&
      !saving &&
      !needsChoice &&
      matching == null;
  bool get canSave => editable && draft!.title.trim().isNotEmpty;

  Future<void> load() async {
    if (saving || loading || saved != null) return;
    final version = ++_readVersion;
    loading = true;
    _notify();
    try {
      final task = await _api.getTask(id);
      if (_disposed || version != _readVersion) return;
      saved = task;
      draft = OrganizationDraft.fromTask(task);
      missing = false;
      error = null;
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
    String? title,
    int? priority,
    int? durationMinutes,
    bool? externallyBlocked,
    bool setPriority = false,
    bool setDuration = false,
  }) {
    if (!editable) return;
    draft = OrganizationDraft(
      title: title ?? draft!.title,
      priority: setPriority ? priority : draft!.priority,
      durationMinutes: setDuration ? durationMinutes : draft!.durationMinutes,
      externallyBlocked: externallyBlocked ?? draft!.externallyBlocked,
    );
    final errors = {...fieldErrors};
    if (title != null) errors.remove('title');
    if (setPriority) errors.remove('priority');
    if (setDuration) errors.remove('duration_minutes');
    if (externallyBlocked != null) errors.remove('externally_blocked');
    fieldErrors = Map.unmodifiable(errors);
    _notify();
  }

  Future<TaskDetail?> save() async {
    if (!canSave) return null;
    ++_readVersion;
    submitted = OrganizationSubmission(original: saved!, draft: draft!);
    saving = true;
    error = null;
    notice = null;
    fieldErrors = const {};
    _notify();
    try {
      final result = await _api.saveOrganization(submitted!);
      if (_disposed) return null;
      uncertain = false;
      conflict = false;
      needsChoice = false;
      saved = result;
      draft = OrganizationDraft.fromTask(result);
      saving = false;
      _notify();
      return result;
    } on HeapApiException catch (failure) {
      if (_disposed) return null;
      saving = false;
      error = failure.unknownOutcome ? null : failure.message;
      fieldErrors = failure.fieldErrors;
      if (failure.unknownOutcome) {
        uncertain = true;
        needsChoice = true;
      } else if (failure.statusCode == 409 && failure.code == 'task_conflict') {
        conflict = true;
        needsChoice = true;
      } else if (failure.statusCode == 409 &&
          failure.code == 'task_completed') {
        needsChoice = true;
        error = 'This task is completed and cannot be edited. Reload the saved task.';
      } else if (failure.statusCode == 404) {
        missing = true;
      }
      _notify();
      return null;
    }
  }

  Future<void> reconcile() async {
    if (loading || saving || !needsChoice) return;
    final version = ++_readVersion;
    loading = true;
    comparison = null;
    matching = null;
    _notify();
    try {
      final task = await _api.getTask(id);
      if (_disposed || version != _readVersion) return;
      comparison = task;
      missing = false;
      error = null;
      if (task.status != 'completed' &&
          uncertain &&
          submitted?.matches(task) == true) {
        matching = task;
        uncertain = false;
        conflict = false;
        needsChoice = false;
        notice = null;
      }
    } on HeapApiException catch (failure) {
      if (_disposed || version != _readVersion) return;
      missing = failure.statusCode == 404;
      error = uncertain
          ? 'Could not check the saved task. The save may still have succeeded.'
          : 'Could not reload the saved task.';
    }
    if (_disposed || version != _readVersion) return;
    loading = false;
    _notify();
  }

  void chooseVersion({required bool keepEdits}) {
    final task = comparison;
    if (loading ||
        task == null ||
        task.status == 'completed' ||
        missing ||
        matching != null) {
      return;
    }
    saved = task;
    if (!keepEdits) draft = OrganizationDraft.fromTask(task);
    comparison = null;
    needsChoice = false;
    conflict = false;
    error = null;
    fieldErrors = const {};
    notice = keepEdits
        ? 'Your edits are not saved. Saving will replace the server\'s title, priority, duration, and awaiting flag with your values.'
        : null;
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
