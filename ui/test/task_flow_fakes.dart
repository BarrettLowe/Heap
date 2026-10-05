import 'package:heap_app/heap_api.dart';
import 'package:heap_app/task_detail.dart';

const taskId = 'd4be2fc9-49b7-46a6-9981-1f063eed03ea';
const assignedProjectId = '00000000-0000-0000-0000-000000000001';
const reassignedProjectId = '00000000-0000-0000-0000-000000000002';
Map<String, Object?> detailJson({
  String id = taskId,
  String title = 'Existing task',
  String? status,
  String? projectId,
  int? priority,
  int? duration,
  bool waiting = false,
  String updated = '2026-10-03T12:34:56.000000Z',
  String? since,
  String? dueDate,
}) {
  final placement =
      status ?? (priority != null && duration != null ? 'on_heap' : 'inbox');
  return {
    'id': id,
    'title': title,
    'status': placement,
    'created_at': '2026-10-03T12:34:56.000000Z',
    'updated_at': updated,
    'priority': priority,
    'duration_minutes': duration,
    'externally_blocked': waiting,
    'project_id': projectId,
    'due_date': dueDate,
    'on_heap_since': since ?? (placement == 'on_heap' ? updated : null),
  };
}

TaskDetail detail({
  String id = taskId,
  String title = 'Existing task',
  String? status,
  String? projectId,
  int? priority,
  int? duration,
  bool waiting = false,
  String updated = '2026-10-03T12:34:56.000000Z',
}) => TaskDetail.fromJson(
  detailJson(
    id: id,
    title: title,
    status: status,
    projectId: projectId,
    priority: priority,
    duration: duration,
    waiting: waiting,
    updated: updated,
  ),
);

class FakeInbox implements InboxService {
  List<InboxTask> items = [];
  Future<List<InboxTask>> Function()? onList;
  Future<InboxTask> Function(String)? onCapture;
  int lists = 0;
  int posts = 0;
  @override
  Future<List<InboxTask>> listInbox() {
    lists++;
    return onList?.call() ?? Future.value(items);
  }

  @override
  Future<InboxTask> capture(String title) {
    posts++;
    return onCapture?.call(title) ?? Future.value(detail(title: title));
  }
}

class FakeOrganization implements OrganizationService {
  int gets = 0;
  int puts = 0;
  int lists = 0;
  Future<TaskDetail> Function(String)? onGet;
  Future<TaskDetail> Function(OrganizationSubmission)? onSave;
  Future<TaskDetail> Function(TaskDetail, {required bool completed})?
  onCompletion;
  int completionWrites = 0;
  Future<List<TaskDetail>> Function()? onList;
  String? lastLocalDate;
  OrganizationSubmission? lastSubmission;
  @override
  Future<TaskDetail> getTask(String id) {
    gets++;
    return onGet?.call(id) ?? Future.value(detail(id: id));
  }

  @override
  Future<TaskDetail> saveOrganization(OrganizationSubmission submission) {
    puts++;
    lastSubmission = submission;
    return onSave?.call(submission) ??
        Future.value(
          detail(
            id: submission.original.id,
            projectId: submission.draft.projectId,
            title: submission.draft.title.trim(),
            priority: submission.draft.priority,
            duration: submission.draft.durationMinutes,
            waiting: submission.draft.externallyBlocked,
            status: submission.expectedStatus,
          ),
        );
  }

  @override
  Future<TaskDetail> setCompletion(
    TaskDetail original, {
    required bool completed,
  }) {
    completionWrites++;
    return onCompletion?.call(original, completed: completed) ??
        Future.value(
          TaskDetail.fromJson({
            'id': original.id,
            'title': original.title,
            'status': completed ? 'completed' : 'on_heap',
            'created_at': formatUtcTimestamp(original.createdAt),
            'updated_at': '2026-10-04T12:34:56.123456Z',
            'priority': original.priority,
            'duration_minutes': original.durationMinutes,
            'externally_blocked': original.externallyBlocked,
            'project_id': original.projectId,
            'on_heap_since': formatUtcTimestamp(original.onHeapSince!),
            'due_date': original.dueDate?.toString(),
          }),
        );
  }

  @override
  Future<List<TaskDetail>> listOnHeap({required String localDate}) {
    lists++;
    lastLocalDate = localDate;
    return onList?.call() ?? Future.value([]);
  }
}
