import 'inbox_task.dart';

class HeapFilter {
  const HeapFilter.none() : minimumMinutes = null, priority = null;
  const HeapFilter.time(int minutes)
    : minimumMinutes = minutes,
      priority = null;
  const HeapFilter.priority(int value)
    : minimumMinutes = null,
      priority = value;

  final int? minimumMinutes;
  final int? priority;
  bool get active => minimumMinutes != null || priority != null;

  bool matches(InboxTask task) {
    if (minimumMinutes case final minutes?) {
      return task.durationMinutes != null && task.durationMinutes! >= minutes;
    }
    return priority == null || task.priority == priority;
  }
}
