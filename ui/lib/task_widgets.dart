import 'package:flutter/material.dart';

import 'heap_style.dart';
import 'inbox_task.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.message,
    this.actions = const [],
    this.consequence = false,
  });
  final String message;
  final List<Widget> actions;
  final bool consequence;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Material(
        color: consequence
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (consequence)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.warning_amber_rounded),
                ),
              Text(message),
              if (actions.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onOpen,
    this.focusNode,
    this.highlighted = false,
  });
  final InboxTask task;
  final VoidCallback onOpen;
  final FocusNode? focusNode;
  final bool highlighted;
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _focused = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final colors = priorityColors[task.priority] ?? unsetColors;
    final duration = task.durationMinutes == null
        ? 'Unknown'
        : '${task.durationMinutes} min';
    final narrow =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final title = Text(
      task.title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: heapTitle,
      ),
    );
    final pill = PriorityPill(priority: task.priority);
    return Semantics(
      button: true,
      onTap: widget.onOpen,
      excludeSemantics: true,
      label:
          '${task.title}. ${task.status == 'inbox' ? 'Inbox' : 'Inbox'}. ${priorityLabels[task.priority] ?? 'Unset'}. $duration. ${task.externallyBlocked ? 'Awaiting external dependencies. ' : ''}Open task editor.',
      child: Column(
        children: [
          Material(
            color: _focused || _hovered || widget.highlighted
                ? heapHighlight
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: _focused
                  ? const BorderSide(color: heapGreen, width: 2)
                  : BorderSide.none,
            ),
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onOpen,
              onFocusChange: (value) => setState(() => _focused = value),
              onHover: (value) => setState(() => _hovered = value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors.$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (narrow)
                            title
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: title),
                                const SizedBox(width: 12),
                                pill,
                              ],
                            ),
                          if (task.status == 'inbox') ...[
                            const SizedBox(height: 6),
                            Text(
                              task.priority == null &&
                                      task.durationMinutes == null
                                  ? 'Needs priority and duration'
                                  : task.priority == null
                                  ? 'Needs priority'
                                  : 'Needs duration',
                              style: const TextStyle(
                                color: heapMuted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (narrow) pill,
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 18,
                                    color: heapMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    duration,
                                    style: const TextStyle(
                                      color: heapMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              if (task.externallyBlocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDF0F4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text.rich(
                                    TextSpan(
                                      children: [
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Icon(
                                            Icons.hourglass_empty,
                                            size: 16,
                                            color: Color(0xFF475465),
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' Awaiting external dependencies',
                                        ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF475465),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 36, right: 12),
            child: Divider(height: 1, color: heapDivider),
          ),
        ],
      ),
    );
  }
}

class CappedContent extends StatelessWidget {
  const CappedContent({super.key, required this.child, this.width = 840});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}
