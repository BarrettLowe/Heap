import 'inbox_task.dart';

class HeapFilter {
  const HeapFilter.none()
    : minimumMinutes = null,
      maximumMinutes = null,
      priority = null;
  const HeapFilter.time(int minutes)
    : minimumMinutes = minutes,
      maximumMinutes = null,
      priority = null;
  const HeapFilter.timeRange(int minimum, int maximum)
    : minimumMinutes = minimum,
      maximumMinutes = maximum,
      priority = null;
  const HeapFilter.priority(int value)
    : minimumMinutes = null,
      maximumMinutes = null,
      priority = value;

  final int? minimumMinutes;
  final int? maximumMinutes;
  final int? priority;
  bool get active =>
      minimumMinutes != null || maximumMinutes != null || priority != null;

  bool matches(InboxTask task) {
    if (minimumMinutes case final minutes?) {
      final duration = task.durationMinutes;
      return duration != null &&
          duration >= minutes &&
          (maximumMinutes == null || duration <= maximumMinutes!);
    }
    return priority == null || task.priority == priority;
  }
}
