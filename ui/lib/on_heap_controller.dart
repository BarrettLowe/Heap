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
  bool _disposed = false;
  List<TaskDetail> get tasks => _tasks;

  Future<void> load() async {
    final version = ++_readVersion;
    loading = true;
    _notify();
    try {
      final result = await _api.listOnHeap();
      if (_disposed || version != _readVersion) return;
      _tasks = result;
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
