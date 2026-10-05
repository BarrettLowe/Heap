import 'package:flutter/foundation.dart';

import 'calendar_date.dart';
import 'heap_api.dart';
import 'task_detail.dart';

class OnHeapController extends ChangeNotifier {
  OnHeapController(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  DateTime Function() get clock => _clock;
  final OrganizationService _api;
  List<TaskDetail> _tasks = const [];
  bool loading = false;
  bool loaded = false;
  bool stale = false;
  String? error;
  int _readVersion = 0;
  int _projectDeletionVersion = 0;
  final Set<String> _pending = {};
  final Map<String, ({TaskDetail original, bool completed})> _uncertain = {};
  final Map<String, ({int index, String? before, String? after})>
  _completionPositions = {};
  final Map<String, TaskDetail> _provisional = {};
  final Set<String> _checking = {};
  final Map<String, String> _rowErrors = {};
  bool _disposed = false;
  CalendarDate? _lastSuccessfulLoadDate;
  List<TaskDetail> get tasks => _tasks;
  CalendarDate? get lastSuccessfulLoadDate => _lastSuccessfulLoadDate;
  bool get hasPendingCompletionWrite => _pending.isNotEmpty;
  bool isPending(String id) => _pending.contains(id);
  bool isUncertain(String id) => _uncertain.containsKey(id);
  bool isChecking(String id) =>
      _checking.contains(id) || (loading && isUncertain(id));
  String? errorFor(String id) => _rowErrors[id];

  Future<void> toggleCompletion(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0 || _pending.contains(id) || _uncertain.containsKey(id)) {
      return;
    }
    final original = _tasks[index];
    if (original.status != 'on_heap' && original.status != 'completed') return;
    final completed = original.status == 'on_heap';
    if (completed) {
      _completionPositions[id] = (
        index: index,
        before: index > 0 ? _tasks[index - 1].id : null,
        after: index + 1 < _tasks.length ? _tasks[index + 1].id : null,
      );
    }
    ++_readVersion;
    loading = false;
    final deletionVersion = _projectDeletionVersion;
    _pending.add(id);
    _rowErrors.remove(id);
    _notify();
    try {
      final result = await _api.setCompletion(original, completed: completed);
      if (_disposed || deletionVersion != _projectDeletionVersion) return;
      ++_readVersion;
      loading = false;
      final wasMissing = !_tasks.any((task) => task.id == id);
      _upsert(result, position: _completionPositions[id]);
      if (result.status == 'on_heap' && wasMissing) {
        _provisional[id] = result;
      } else {
        _provisional.remove(id);
      }
      if (!completed && !wasMissing) _completionPositions.remove(id);
      if (wasMissing && result.status == 'on_heap') stale = true;
    } on HeapApiException catch (failure) {
      if (_disposed || deletionVersion != _projectDeletionVersion) return;
      ++_readVersion;
      loading = false;
      if (failure.unknownOutcome) {
        _uncertain[id] = (original: original, completed: completed);
        final wasMissing = !_tasks.any((task) => task.id == id);
        _upsert(original, position: _completionPositions[id]);
        if (wasMissing) stale = true;
      } else {
        _rowErrors[id] = failure.message;
      }
    } catch (_) {
      if (_disposed || deletionVersion != _projectDeletionVersion) return;
      ++_readVersion;
      loading = false;
      _uncertain[id] = (original: original, completed: completed);
      final wasMissing = !_tasks.any((task) => task.id == id);
      _upsert(original, position: _completionPositions[id]);
      if (wasMissing) stale = true;
    } finally {
      if (!_disposed) {
        _pending.remove(id);
        _notify();
      }
    }
  }

  Future<void> checkCompletion(String id) async {
    final attempt = _uncertain[id];
    if (attempt == null || isChecking(id)) return;
    final version = ++_readVersion;
    loading = false;
    _checking.add(id);
    _notify();
    try {
      final task = await _api.getTask(id);
      if (_disposed || version != _readVersion) return;
      if (task.status == (attempt.completed ? 'completed' : 'on_heap')) {
        _uncertain.remove(id);
        if (task.status == 'completed') {
          _provisional.remove(id);
          _completionPositions.remove(id);
        }
        final missing = !_tasks.any((item) => item.id == id);
        _upsert(task, position: _completionPositions[id]);
        if (missing) stale = true;
        if (!attempt.completed) {
          if (missing) _provisional[id] = task;
          if (!missing) _completionPositions.remove(id);
        }
      }
    } on HeapApiException {
      // A failed check cannot rule out a write that is still running.
    } finally {
      _checking.remove(id);
      _notify();
    }
  }

  void _upsert(
    TaskDetail task, {
    ({int index, String? before, String? after})? position,
  }) {
    final updated = [..._tasks];
    final index = updated.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      updated[index] = task;
    } else {
      var insertAt = updated.length;
      if (position != null) {
        final afterIndex = position.after == null
            ? -1
            : updated.indexWhere((item) => item.id == position.after);
        final beforeIndex = position.before == null
            ? -1
            : updated.indexWhere((item) => item.id == position.before);
        if (afterIndex >= 0 && beforeIndex >= 0 && beforeIndex >= afterIndex) {
          insertAt = position.index.clamp(0, updated.length);
        } else if (afterIndex >= 0) {
          insertAt = afterIndex;
        } else if (beforeIndex >= 0) {
          insertAt = beforeIndex + 1;
        } else {
          insertAt = position.index.clamp(0, updated.length);
        }
      }
      updated.insert(insertAt, task);
    }
    _tasks = List.unmodifiable(updated);
    loaded = true;
  }

  Future<void> load() async {
    final version = ++_readVersion;
    final requestedDate = CalendarDate.fromLocalDate(clock());
    loading = true;
    _notify();
    try {
      final result = await _api.listOnHeap(localDate: requestedDate.toString());
      if (_disposed || version != _readVersion) return;
      final confirmed = <String, TaskDetail>{};
      for (final entry in _uncertain.entries.toList()) {
        try {
          final task = await _api.getTask(entry.key);
          if (_disposed || version != _readVersion) return;
          if (task.status ==
              (entry.value.completed ? 'completed' : 'on_heap')) {
            confirmed[entry.key] = task;
          }
        } on HeapApiException {
          // List absence or an unchanged GET does not cancel a timed-out PUT.
        }
      }
      if (_disposed || version != _readVersion) return;
      _tasks = result;
      final responseIds = result.map((task) => task.id).toSet();
      var provisionalRecovery = false;
      for (final entry in confirmed.entries) {
        _uncertain.remove(entry.key);
        if (entry.value.status == 'completed') {
          _provisional.remove(entry.key);
          _completionPositions.remove(entry.key);
          _tasks = List.unmodifiable(
            _tasks.where((task) => task.id != entry.key),
          );
        } else {
          final missing = !_tasks.any((task) => task.id == entry.key);
          _upsert(entry.value, position: _completionPositions[entry.key]);
          provisionalRecovery |= missing;
          if (missing) {
            _provisional[entry.key] = entry.value;
          } else {
            _completionPositions.remove(entry.key);
          }
        }
      }
      for (final entry in _uncertain.entries) {
        final missing = !_tasks.any((task) => task.id == entry.key);
        _upsert(
          entry.value.original,
          position: _completionPositions[entry.key],
        );
        provisionalRecovery |= missing;
      }
      for (final entry in _provisional.entries.toList()) {
        if (responseIds.contains(entry.key)) {
          _provisional.remove(entry.key);
          _completionPositions.remove(entry.key);
        } else {
          _upsert(entry.value, position: _completionPositions[entry.key]);
          provisionalRecovery = true;
        }
      }
      _rowErrors.clear();
      _lastSuccessfulLoadDate = requestedDate;
      loaded = true;
      stale = provisionalRecovery;
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

  void invalidate() {
    ++_readVersion;
    loading = false;
    stale = loaded;
    _notify();
  }

  void clearAfterProjectDeletion() {
    ++_projectDeletionVersion;
    invalidate();
    _provisional.clear();
    _uncertain.clear();
    _completionPositions.clear();
    _tasks = const [];
    loaded = false;
    stale = false;
    error = null;
    _notify();
  }

  void applyConfirmed(TaskDetail task) {
    invalidate();
    final updated = [..._tasks];
    final index = updated.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      if (task.status == 'on_heap') {
        updated[index] = task;
      } else {
        updated.removeAt(index);
      }
    } else if (task.status == 'on_heap') {
      updated.add(task);
    }
    _tasks = List.unmodifiable(updated);
    if (task.status == 'on_heap') {
      loaded = true;
      _provisional[task.id] = task;
    } else {
      _provisional.remove(task.id);
    }
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
