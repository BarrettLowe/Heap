import 'package:flutter/foundation.dart';

import 'heap_api.dart';
import 'task_detail.dart';

class OnHeapController extends ChangeNotifier {
  OnHeapController(this._api);
  final OrganizationService _api;
  List<TaskDetail> _tasks = const [];
  bool loading = false;
  bool loaded = false;
  bool stale = false;
  String? error;
  int _readVersion = 0;
  final Set<String> _pending = {};
  final Map<String, ({TaskDetail original, bool completed})> _uncertain = {};
  final Set<String> _checking = {};
  final Map<String, String> _rowErrors = {};
  bool _disposed = false;
  List<TaskDetail> get tasks => _tasks;
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
    ++_readVersion;
    loading = false;
    _pending.add(id);
    _rowErrors.remove(id);
    _notify();
    try {
      final result = await _api.setCompletion(original, completed: completed);
      if (_disposed) return;
      ++_readVersion;
      loading = false;
      _upsert(result);
    } on HeapApiException catch (failure) {
      if (_disposed) return;
      ++_readVersion;
      loading = false;
      if (failure.unknownOutcome) {
        _uncertain[id] = (original: original, completed: completed);
        _upsert(original);
      } else {
        _rowErrors[id] = failure.message;
      }
    } catch (_) {
      if (_disposed) return;
      ++_readVersion;
      loading = false;
      _uncertain[id] = (original: original, completed: completed);
      _upsert(original);
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
        _upsert(task);
      }
    } on HeapApiException {
      // A failed check cannot rule out a write that is still running.
    } finally {
      _checking.remove(id);
      _notify();
    }
  }

  void _upsert(TaskDetail task) {
    final updated = [..._tasks];
    final index = updated.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      updated[index] = task;
    } else {
      updated.add(task);
      updated.sort(_byAge);
    }
    _tasks = List.unmodifiable(updated);
    loaded = true;
  }

  static int _byAge(TaskDetail first, TaskDetail second) {
    final byAge = first.onHeapSince!.compareTo(second.onHeapSince!);
    return byAge != 0 ? byAge : first.id.compareTo(second.id);
  }

  Future<void> load() async {
    final version = ++_readVersion;
    loading = true;
    _notify();
    try {
      final result = await _api.listOnHeap();
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
      for (final entry in confirmed.entries) {
        _uncertain.remove(entry.key);
        if (entry.value.status == 'completed') {
          _tasks = List.unmodifiable(
            _tasks.where((task) => task.id != entry.key),
          );
        } else {
          _upsert(entry.value);
        }
      }
      for (final attempt in _uncertain.values) {
        _upsert(attempt.original);
      }
      _rowErrors.clear();
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

  void invalidate() {
    ++_readVersion;
    loading = false;
    stale = loaded;
    _notify();
  }

  void clearAfterProjectDeletion() {
    invalidate();
    _tasks = const [];
    loaded = false;
    stale = false;
    error = null;
    _notify();
  }

  void applyConfirmed(TaskDetail task) {
    invalidate();
    final merged =
        <TaskDetail>[
          ..._tasks.where((item) => item.id != task.id),
          if (task.status == 'on_heap') task,
        ]..sort((first, second) {
          final byAge = first.onHeapSince!.compareTo(second.onHeapSince!);
          return byAge != 0 ? byAge : first.id.compareTo(second.id);
        });
    _tasks = List.unmodifiable(merged);
    if (task.status == 'on_heap') loaded = true;
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
