import 'package:flutter/material.dart';

import 'heap_filter.dart';
import 'heap_style.dart';
import 'inbox_task.dart';

class HeapFilterPills extends StatelessWidget {
  const HeapFilterPills({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final HeapFilter filter;
  final ValueChanged<HeapFilter> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _picker(
        key: 'time-filter',
        icon: Icons.schedule,
        value: filter.minimumMinutes,
        label: filter.minimumMinutes == null
            ? 'Time'
            : 'Time: ≥${filter.minimumMinutes}m',
        accessibleLabel: filter.minimumMinutes == null
            ? 'Time filter, any duration'
            : 'Time filter, at least ${filter.minimumMinutes} minutes',
        choices: durationChoices,
        option: (minutes) => Text('At least $minutes min'),
        changed: (value) => onChanged(HeapFilter.time(value)),
      ),
      _picker(
        key: 'priority-filter',
        icon: Icons.flag_outlined,
        value: filter.priority,
        label: filter.priority == null
            ? 'Priority'
            : 'Priority: P${filter.priority}',
        accessibleLabel: filter.priority == null
            ? 'Priority filter, any priority'
            : 'Priority filter, ${priorityLabels[filter.priority]}',
        choices: priorityLabels.keys.toList(),
        option: (priority) => PriorityPill(priority: priority),
        changed: (value) => onChanged(HeapFilter.priority(value)),
      ),
    ],
  );

  Widget _picker({
    required String key,
    required IconData icon,
    required int? value,
    required String label,
    required String accessibleLabel,
    required List<int> choices,
    required Widget Function(int) option,
    required ValueChanged<int> changed,
  }) => MergeSemantics(
    child: Semantics(
      button: true,
      selected: value != null,
      label: accessibleLabel,
      child: PopupMenuButton<int>(
        key: Key(key),
        tooltip: '',
        onSelected: (selection) {
          if (selection == 0) {
            onChanged(const HeapFilter.none());
          } else {
            changed(selection);
          }
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            key: Key('$key-any'),
            value: 0,
            checked: value == null,
            child: const Text('Any'),
          ),
          for (final choice in choices)
            CheckedPopupMenuItem(
              key: Key('$key-$choice'),
              value: choice,
              checked: value == choice,
              child: option(choice),
            ),
        ],
        borderRadius: BorderRadius.circular(28),
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: value == null ? heapCanvas : heapGreen,
              border: Border.all(
                color: value == null ? heapDivider : heapGreen,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: IconTheme(
              data: IconThemeData(
                color: value == null ? heapInk : Colors.white,
                size: 20,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: value == null ? heapInk : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
