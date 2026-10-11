import 'calendar_date.dart';
import 'repeat_rule.dart';

const priorityLabels = <int, String>{
  1: 'P1 Critical',
  2: 'P2 Important',
  3: 'P3 Normal',
  4: 'P4 Someday',
  5: 'P5 Maybe',
};
const durationChoices = <int>[5, 15, 30, 60, 120, 240];

String formatDuration(int minutes) {
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    final hourLabel = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    return remainder == 0 ? hourLabel : '$hourLabel $remainder min';
  }
  return '$minutes min';
}

class InboxTask {
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _timestampPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  );
  const InboxTask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.priority,
    this.durationMinutes,
    this.externallyBlocked = false,
    this.dueDate,
    this.repeat,
  });
  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? priority;
  final int? durationMinutes;
  final bool externallyBlocked;
  final CalendarDate? dueDate;
  final RepeatRule? repeat;

  factory InboxTask.fromJson(
    Object? value, {
    bool allowOtherStatuses = false,
  }) => InboxTask._decode(
    value,
    metadata: true,
    allowOtherStatuses: allowOtherStatuses,
  );

  factory InboxTask.fromCaptureJson(Object? value) =>
      InboxTask._decode(value, metadata: false);

  static InboxTask _decode(
    Object? value, {
    required bool metadata,
    bool allowOtherStatuses = false,
  }) {
    if (value is! Map<String, dynamic> ||
        !value.keys.toSet().containsAll({
          'id',
          'title',
          'status',
          'created_at',
          'updated_at',
          if (metadata) ...[
            'priority',
            'duration_minutes',
            'externally_blocked',
            'due_date',
            'repeat',
          ],
        })) {
      throw const FormatException('Task is missing required fields.');
    }
    final id = value['id'];
    final title = value['title'];
    final status = value['status'];
    final created = value['created_at'];
    final updated = value['updated_at'];
    final priority = metadata ? value['priority'] : null;
    final duration = metadata ? value['duration_minutes'] : null;
    final waiting = metadata ? value['externally_blocked'] : false;
    final dueDateValue = metadata ? value['due_date'] : null;
    final repeatValue = metadata ? value['repeat'] : null;
    if (id is! String ||
        !_uuidPattern.hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        created is! String ||
        updated is! String ||
        !(allowOtherStatuses ? {'inbox', 'on_heap', 'completed'} : {'inbox'})
            .contains(status) ||
        (priority != null &&
            (priority is! int || !priorityLabels.containsKey(priority))) ||
        (duration != null &&
            (duration is! int || !durationChoices.contains(duration))) ||
        waiting is! bool ||
        (metadata && dueDateValue != null && dueDateValue is! String)) {
      throw const FormatException('Task fields have invalid values.');
    }
    final dueDate = dueDateValue == null
        ? null
        : CalendarDate.parse(dueDateValue as String);
    final repeat = metadata && repeatValue != null
        ? RepeatRule.fromJson(repeatValue)
        : null;
    final createdAt = parseUtcTimestamp(created);
    final updatedAt = parseUtcTimestamp(updated);
    if ((!metadata && created != updated) ||
        (metadata &&
            status == 'inbox' &&
            priority != null &&
            duration != null) ||
        (status == 'on_heap' && (priority == null || duration == null))) {
      throw const FormatException(
        'Task status or capture timestamps are inconsistent.',
      );
    }
    return InboxTask(
      id: id,
      title: title,
      status: status as String,
      createdAt: createdAt,
      updatedAt: updatedAt,
      priority: priority as int?,
      durationMinutes: duration as int?,
      externallyBlocked: waiting,
      dueDate: dueDate,
      repeat: repeat,
    );
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is InboxTask &&
      other.id == id &&
      other.title == title &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.priority == priority &&
      other.durationMinutes == durationMinutes &&
      other.externallyBlocked == externallyBlocked &&
      other.dueDate == dueDate &&
      other.repeat == repeat;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    status,
    createdAt,
    updatedAt,
    priority,
    durationMinutes,
    externallyBlocked,
    dueDate,
    repeat,
  );

  static DateTime parseUtcTimestamp(String value) {
    if (!_timestampPattern.hasMatch(value)) {
      throw const FormatException('Invalid UTC timestamp.');
    }
    final date = DateTime.parse(value);
    if (formatUtcTimestamp(date) != value) {
      throw const FormatException('Invalid UTC date.');
    }
    return date;
  }
}

String formatUtcTimestamp(DateTime date) {
  final utc = date.toUtc();
  final iso = utc.toIso8601String();
  // The API requires 6 digits even when Dart omits zero microseconds.
  return utc.microsecond == 0 ? '${iso.substring(0, iso.length - 1)}000Z' : iso;
}
