import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_filter.dart';

import 'task_flow_fakes.dart';

void main() {
  test(
    'Time is a minimum including the boundary, not an available-time maximum',
    () {
      const filter = HeapFilter.time(30);
      for (final minutes in [5, 15, 30, 60, 120, 240]) {
        expect(
          filter.matches(detail(priority: 1, duration: minutes)),
          minutes >= 30,
        );
      }
      expect(filter.matches(detail(priority: 1)), false);
    },
  );
  test(
    'Priority matches exactly and waiting does not affect either filter',
    () {
      for (final priority in [1, 2, 3, 4, 5]) {
        for (final waiting in [false, true]) {
          final task = detail(
            priority: priority,
            duration: 30,
            waiting: waiting,
          );
          expect(const HeapFilter.priority(1).matches(task), priority == 1);
          expect(const HeapFilter.time(30).matches(task), true);
        }
      }
    },
  );
  test(
    'single filter variants and Any preserve incoming order and snapshots',
    () {
      final tasks = [
        detail(title: 'First', priority: 5, duration: 120),
        detail(title: 'Second', priority: 1, duration: 15),
        detail(title: 'Third', priority: 2, duration: 30),
      ];
      const time = HeapFilter.time(30);
      const priority = HeapFilter.priority(1);
      const any = HeapFilter.none();
      expect(time.priority, isNull);
      expect(priority.minimumMinutes, isNull);
      expect(any.active, false);
      expect(tasks.where(time.matches).map((task) => task.title), [
        'First',
        'Third',
      ]);
      expect(tasks.where(priority.matches).map((task) => task.title), [
        'Second',
      ]);
      expect(tasks.where(any.matches), tasks);
      expect(tasks.map((task) => task.title), ['First', 'Second', 'Third']);
    },
  );
}
