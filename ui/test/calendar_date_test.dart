import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/calendar_date.dart';
import 'package:heap_app/inbox_task.dart';
import 'package:heap_app/task_detail.dart';

import 'task_flow_fakes.dart';

void main() {
  test('strict canonical real dates round trip without UTC conversion', () {
    final date = CalendarDate.parse('2024-02-29');
    expect(date.toString(), '2024-02-29');
    expect(CalendarDate.fromLocalDate(DateTime(2024, 2, 29)), date);
    expect(date.toLocalDate(), DateTime(2024, 2, 29));
    for (final invalid in [
      '2023-02-29',
      '2026-02-30',
      '2026-2-03',
      '0000-01-01',
      '10000-01-01',
    ]) {
      expect(() => CalendarDate.parse(invalid), throwsFormatException);
    }
  });

  test('bulk task due date is required; capture stays explicitly undated', () {
    expect(
      () => InboxTask.fromJson(detailJson()..remove('due_date')),
      throwsFormatException,
    );
    final captured = InboxTask.fromCaptureJson({
      'id': taskId,
      'title': 'Captured',
      'status': 'inbox',
      'created_at': '2026-10-03T12:34:56.000000Z',
      'updated_at': '2026-10-03T12:34:56.000000Z',
    });
    expect(captured.dueDate, isNull);
    expect(
      InboxTask.fromJson(detailJson(dueDate: '2026-10-05')).dueDate,
      CalendarDate.parse('2026-10-05'),
    );
  });

  test(
    'draft equality, request JSON, and uncertain matching include due date',
    () {
      final original = detail();
      final date = CalendarDate.parse('2026-10-05');
      final draft = OrganizationDraft(
        title: original.title,
        priority: original.priority,
        durationMinutes: original.durationMinutes,
        externallyBlocked: original.externallyBlocked,
        projectId: original.projectId,
        dueDate: date,
      );
      final submission = OrganizationSubmission(
        original: original,
        draft: draft,
      );
      expect(submission.toJson()['due_date'], '2026-10-05');
      expect(
        submission.matches(detailJson(dueDate: '2026-10-05').letDetail()),
        isTrue,
      );
      expect(draft.sameFields(OrganizationDraft.fromTask(original)), isFalse);
    },
  );
}

extension on Map<String, Object?> {
  TaskDetail letDetail() => TaskDetail.fromJson(this);
}
