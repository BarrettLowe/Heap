import 'calendar_date.dart';
import 'inbox_task.dart';
export 'inbox_task.dart' show priorityLabels, durationChoices, formatDuration;

class TaskDetail extends InboxTask {
  const TaskDetail({
    required super.id,
    required super.title,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.updatedAtToken,
    required super.priority,
    required super.durationMinutes,
    required super.externallyBlocked,
    required this.onHeapSince,
    required this.projectId,
    super.dueDate,
  });
  final String updatedAtToken;
  final DateTime? onHeapSince;
  final String? projectId;

  factory TaskDetail.fromJson(Object? value) {
    final base = InboxTask.fromJson(value, allowOtherStatuses: true);
    final json = value as Map<String, dynamic>;
    if (!json.containsKey('on_heap_since')) {
      throw const FormatException('Missing on-the-heap timestamp.');
    }
    if (!json.containsKey('project_id')) {
      throw const FormatException('Missing project association.');
    }
    final projectId = json['project_id'];
    if (projectId != null &&
        (projectId is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(projectId))) {
      throw const FormatException('Invalid project association.');
    }
    final since = json['on_heap_since'];
    if (since != null && since is! String) {
      throw const FormatException('Invalid on-the-heap timestamp.');
    }
    final timestamp = since == null
        ? null
        : InboxTask.parseUtcTimestamp(since as String);
    if ((base.status == 'on_heap' && timestamp == null) ||
        (base.status == 'inbox' && timestamp != null)) {
      throw const FormatException(
        'Status does not match on-the-heap timestamp.',
      );
    }
    return TaskDetail(
      id: base.id,
      title: base.title,
      status: base.status,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      updatedAtToken: json['updated_at'] as String,
      priority: base.priority,
      durationMinutes: base.durationMinutes,
      externallyBlocked: base.externallyBlocked,
      onHeapSince: timestamp,
      projectId: projectId as String?,
      dueDate: base.dueDate,
    );
  }
}

class OrganizationDraft {
  const OrganizationDraft({
    required this.title,
    this.priority,
    this.durationMinutes,
    required this.externallyBlocked,
    required this.projectId,
    this.dueDate,
  });
  factory OrganizationDraft.fromTask(TaskDetail task) => OrganizationDraft(
    title: task.title,
    priority: task.priority,
    durationMinutes: task.durationMinutes,
    externallyBlocked: task.externallyBlocked,
    projectId: task.projectId,
    dueDate: task.dueDate,
  );
  final String title;
  final int? priority;
  final int? durationMinutes;
  final bool externallyBlocked;
  final String? projectId;
  final CalendarDate? dueDate;
  bool sameFields(OrganizationDraft other) =>
      title == other.title &&
      priority == other.priority &&
      durationMinutes == other.durationMinutes &&
      externallyBlocked == other.externallyBlocked &&
      projectId == other.projectId &&
      dueDate == other.dueDate;
}

class OrganizationSubmission {
  const OrganizationSubmission({required this.original, required this.draft});
  final TaskDetail original;
  final OrganizationDraft draft;
  String get expectedStatus =>
      draft.priority != null && draft.durationMinutes != null
      ? 'on_heap'
      : 'inbox';
  Map<String, Object?> toJson() => {
    'title': draft.title.trim(),
    'priority': draft.priority,
    'duration_minutes': draft.durationMinutes,
    'externally_blocked': draft.externallyBlocked,
    'project_id': draft.projectId,
    'due_date': draft.dueDate?.toString(),
    'expected_updated_at': original.updatedAtToken,
  };
  bool matches(TaskDetail task) =>
      task.id == original.id &&
      task.title == draft.title.trim() &&
      task.priority == draft.priority &&
      task.durationMinutes == draft.durationMinutes &&
      task.externallyBlocked == draft.externallyBlocked &&
      task.status == expectedStatus &&
      task.projectId == draft.projectId &&
      task.dueDate == draft.dueDate;
}
