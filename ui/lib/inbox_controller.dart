import 'package:flutter/foundation.dart';

import 'heap_api.dart';
import 'task_detail.dart';

class InboxController extends ChangeNotifier {
  InboxController(this._api);

  final InboxService _api;
  List<InboxTask> _tasks = const [];
  InboxTask? _lastCaptured;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  bool _stale = false;
  bool _unknownOutcome = false;
  bool _refreshedAfterUnknown = false;
  String? _error;
  String? _notice;
  int _readVersion = 0;
  bool _disposed = false;

  List<InboxTask> get tasks => _tasks;
  InboxTask? get lastCaptured => _lastCaptured;
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get saving => _saving;
  bool get stale => _loaded && _stale;
  bool get unknownOutcome => _unknownOutcome;
  bool get canResubmitAfterUnknown =>
      _unknownOutcome && _refreshedAfterUnknown && !_saving;
  String? get duplicateWarning => !_unknownOutcome
      ? null
      : _saving
      ? 'The earlier capture may have succeeded. This capture is pending and could create a duplicate.'
      : _refreshedAfterUnknown
      ? 'Capture may have succeeded. Submitting again may create a duplicate.'
      : 'Capture may have succeeded. Refresh the inbox before submitting again.';
  String? get error => _error;
  String? get notice => _notice;

  Future<void> load() async {
    final version = ++_readVersion;
    _loading = true;
    if (_unknownOutcome) _refreshedAfterUnknown = false;
    _notify();
    try {
      final tasks = await _api.listInbox();
      if (_disposed || version != _readVersion) return;
      _tasks = tasks;
      _loaded = true;
      _stale = false;
      _error = null;
      _notice = null;
      if (_unknownOutcome) _refreshedAfterUnknown = true;
    } on HeapApiException catch (error) {
      if (_disposed || version != _readVersion) return;
      _error = error.message;
      if (_loaded) _stale = true;
    }
    if (_disposed || version != _readVersion) return;
    _loading = false;
    _notify();
  }

  Future<bool> capture(String title, {bool confirmDuplicate = false}) async {
    if (_saving ||
        title.trim().isEmpty ||
        (_unknownOutcome && (!confirmDuplicate || !_refreshedAfterUnknown))) {
      return false;
    }
    _saving = true;
    _notice = null;
    if (_unknownOutcome) _refreshedAfterUnknown = false;
    _notify();
    try {
      final task = await _api.capture(title.trim());
      if (_disposed) return false;
      _lastCaptured = task;
      _unknownOutcome = false;
      _refreshedAfterUnknown = false;
      ++_readVersion;
      final merged =
          <InboxTask>[
            ..._tasks.where((existing) => existing.id != task.id),
            task,
          ]..sort((first, second) {
            final byTime = first.createdAt.compareTo(second.createdAt);
            return byTime != 0 ? byTime : first.id.compareTo(second.id);
          });
      _tasks = List<InboxTask>.unmodifiable(merged);
      _loaded = true;
      _stale = true;
      _notify();
      await load();
      if (_error != null && !_disposed) {
        _notice = 'Capture saved, but the inbox could not be refreshed.';
      }
      _saving = false;
      _notify();
      return true;
    } on HeapApiException catch (error) {
      if (_disposed) return false;
      _error = error.message;
      if (error.unknownOutcome) {
        ++_readVersion;
        _loading = false;
        _unknownOutcome = true;
        _refreshedAfterUnknown = false;
        if (_loaded) _stale = true;
      }
      _saving = false;
      _notify();
      return false;
    }
  }

  void invalidate() {
    ++_readVersion;
    _loading = false;
    _stale = _loaded;
    _notify();
  }

  void clearAfterProjectDeletion() {
    invalidate();
    _tasks = const [];
    _loaded = false;
    _stale = false;
    _error = null;
    _notify();
  }

  void applyConfirmed(TaskDetail task) {
    invalidate();
    final merged =
        <InboxTask>[
          ..._tasks.where((item) => item.id != task.id),
          if (task.status == 'inbox') task,
        ]..sort((first, second) {
          final byTime = first.createdAt.compareTo(second.createdAt);
          return byTime != 0 ? byTime : first.id.compareTo(second.id);
        });
    _tasks = List.unmodifiable(merged);
    if (task.status == 'inbox') _loaded = true;
    _stale = _loaded;
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
