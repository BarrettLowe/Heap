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
      _timePicker(context),
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

  Widget _timePicker(BuildContext context) {
    final minimum = filter.minimumMinutes;
    final maximum = filter.maximumMinutes ?? durationChoices.last;
    final rangeLabel = minimum == null
        ? 'Time'
        : 'Time: ${formatDuration(minimum)}–${formatDuration(maximum)}';
    final accessibleLabel = minimum == null
        ? 'Time filter, any duration'
        : 'Time filter, ${formatDuration(minimum)} to ${formatDuration(maximum)}';

    Future<void> openRange() async {
      var lowerIndex = minimum == null
          ? 0
          : durationChoices.indexWhere((choice) => choice >= minimum);
      if (lowerIndex < 0) lowerIndex = durationChoices.length - 1;
      var sliderChanged = false;
      var upperIndex = durationChoices
          .indexOf(maximum)
          .clamp(0, durationChoices.length - 1);
      final applied = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Apply time range',
        barrierColor: Colors.black54,
        pageBuilder: (context, animation, secondaryAnimation) => StatefulBuilder(
          builder: (context, setDialogState) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('time-range-outside'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
              Center(
                child: AlertDialog(
                  title: const Text('Time range'),
                  actions: [
                    TextButton(
                      key: const Key('time-range-done'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Done'),
                    ),
                  ],
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${formatDuration(durationChoices[lowerIndex])}–${formatDuration(durationChoices[upperIndex])}',
                      ),
                      RangeSlider(
                        min: 0,
                        max: (durationChoices.length - 1).toDouble(),
                        divisions: durationChoices.length - 1,
                        values: RangeValues(
                          lowerIndex.toDouble(),
                          upperIndex.toDouble(),
                        ),
                        semanticFormatterCallback: (value) =>
                            formatDuration(durationChoices[value.round()]),
                        onChanged: (values) => setDialogState(() {
                          lowerIndex = values.start.round();
                          upperIndex = values.end.round();
                          sliderChanged = true;
                        }),
                      ),
                      Row(
                        children: [
                          for (final minutes in durationChoices)
                            Expanded(
                              child: Text(
                                _durationTickLabel(minutes),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Tap outside to apply.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (applied == true && sliderChanged) {
        onChanged(
          HeapFilter.timeRange(
            durationChoices[lowerIndex],
            durationChoices[upperIndex],
          ),
        );
      }
    }

    return Semantics(
      button: true,
      selected: minimum != null,
      label: accessibleLabel,
      onTap: openRange,
      child: ExcludeSemantics(
        child: TextButton.icon(
          key: const Key('time-filter'),
          onPressed: openRange,
          icon: const Icon(Icons.schedule),
          label: Text(rangeLabel),
          style: TextButton.styleFrom(
            foregroundColor: minimum == null ? heapInk : Colors.white,
            backgroundColor: minimum == null ? heapCanvas : heapGreen,
            minimumSize: const Size(48, 48),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }

  String _durationTickLabel(int minutes) =>
      minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h';

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
