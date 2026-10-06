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
    this.onHeap = false,
    this.onComplete,
    this.completionPending = false,
    this.completionUncertain = false,
    this.onCheckCompletion,
    this.completionChecking = false,
    this.completionError,
  });
  final InboxTask task;
  final VoidCallback onOpen;
  final FocusNode? focusNode;
  final bool highlighted;
  final bool onHeap;
  final VoidCallback? onComplete;
  final bool completionPending;
  final bool completionUncertain;
  final VoidCallback? onCheckCompletion;
  final bool completionChecking;
  final String? completionError;
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _focused = false;
  bool _hovered = false;
  bool _completionFocused = false;
  bool _completionHovered = false;
  bool _bodyFocused = false;
  bool _bodyHovered = false;
  @override
  Widget build(BuildContext context) {
    if (widget.onHeap) return _buildHeapRow(context);
    final task = widget.task;
    final colors = priorityColors[task.priority] ?? unsetColors;
    final duration = task.durationMinutes == null
        ? 'Unknown'
        : formatDuration(task.durationMinutes!);
    final dueDate = task.dueDate == null
        ? null
        : MaterialLocalizations.of(context)
              .formatFullDate(task.dueDate!.toLocalDate());
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
          '${task.title}. Inbox. ${priorityLabels[task.priority] ?? 'Unset'}. $duration. ${dueDate == null ? '' : 'Due $dueDate. '}${task.externallyBlocked ? 'Awaiting external dependencies. ' : ''}Open task editor.',
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
                              if (dueDate != null)
                                _DueDateMetadata(date: dueDate),
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

  Widget _buildHeapRow(BuildContext context) {
    final task = widget.task;
    final completed = task.status == 'completed';
    final duration = task.durationMinutes == null
        ? 'Unknown'
        : formatDuration(task.durationMinutes!);
    final dueDate = task.dueDate == null
        ? null
        : MaterialLocalizations.of(context)
              .formatFullDate(task.dueDate!.toLocalDate());
    final narrow =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final neutral = completed;
    final title = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 180),
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: neutral ? const Color(0xFF3F4742) : heapTitle,
      ),
      child: Text(task.title),
    );
    final pill = PriorityPill(priority: task.priority, neutral: neutral);
    final action = completed ? 'Undo completion for' : 'Complete';
    final bodyEnabled =
        !completed && !widget.completionPending && !widget.completionUncertain;
    final control = Semantics(
      button: true,
      checked: completed,
      enabled: !widget.completionPending && !widget.completionUncertain,
      label: '$action ${task.title}',
      onTap: widget.completionPending || widget.completionUncertain
          ? null
          : widget.onComplete,
      excludeSemantics: true,
      child: Material(
        color: _completionFocused || _completionHovered
            ? heapHighlight
            : Colors.transparent,
        shape: CircleBorder(
          side: _completionFocused
              ? const BorderSide(color: heapGreen, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          key: Key('completion-${task.id}'),
          customBorder: const CircleBorder(),
          onTap: widget.completionPending || widget.completionUncertain
              ? null
              : widget.onComplete,
          onFocusChange: (value) => setState(() => _completionFocused = value),
          onHover: (value) => setState(() => _completionHovered = value),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: widget.completionPending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: completed ? heapGreen : Colors.transparent,
                        border: Border.all(
                          color: completed ? heapGreen : heapMuted,
                          width: 2,
                        ),
                      ),
                      child: completed
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
            ),
          ),
        ),
      ),
    );
    final body = Semantics(
      button: bodyEnabled,
      onTap: bodyEnabled ? widget.onOpen : null,
      excludeSemantics: true,
      label:
          '${task.title}. ${priorityLabels[task.priority] ?? 'Unset'}. $duration. ${dueDate == null ? '' : 'Due $dueDate. '}${task.externallyBlocked ? 'Awaiting external dependencies. ' : ''}${bodyEnabled ? 'Open task editor.' : ''}',
      child: Material(
        color: _bodyFocused || _bodyHovered || widget.highlighted
            ? heapHighlight
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: _bodyFocused
              ? const BorderSide(color: heapGreen, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: bodyEnabled ? widget.onOpen : null,
          onFocusChange: (value) => setState(() => _bodyFocused = value),
          onHover: (value) => setState(() => _bodyHovered = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        Icon(
                          Icons.schedule,
                          size: 18,
                          color: neutral ? const Color(0xFF68716C) : heapMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          duration,
                          style: TextStyle(
                            color: neutral
                                ? const Color(0xFF68716C)
                                : heapMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (dueDate != null)
                      _DueDateMetadata(date: dueDate, neutral: neutral),
                    if (task.externallyBlocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: neutral
                              ? const Color(0xFFE5E8E5)
                              : const Color(0xFFEDF0F4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Icon(
                                  Icons.hourglass_empty,
                                  size: 16,
                                  color: neutral
                                      ? const Color(0xFF59625C)
                                      : const Color(0xFF475465),
                                ),
                              ),
                              const TextSpan(
                                text: ' Awaiting external dependencies',
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: neutral
                                ? const Color(0xFF3F4742)
                                : const Color(0xFF475465),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final message = widget.completionUncertain
        ? '${completed ? 'Undo completion' : 'Completion'} of ${task.title} may have succeeded. The earlier request may still finish. ${widget.completionChecking ? 'Checking…' : 'Check again before making another change.'}'
        : widget.completionPending
        ? 'Updating completion for ${task.title}…'
        : widget.completionError == null
        ? null
        : 'Could not ${completed ? 'undo completion for' : 'complete'} ${task.title}. Retry. ${widget.completionError}';
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            control,
            Expanded(child: body),
          ],
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 12, bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: TextStyle(
                    color: widget.completionPending
                        ? heapMuted
                        : const Color(0xFF8B2D22),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        if (widget.completionUncertain)
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: Key('check-completion-${task.id}'),
                onPressed: widget.completionChecking
                    ? null
                    : widget.onCheckCompletion,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text('Check completion for ${task.title} again'),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(left: 48, right: 12),
          child: Divider(height: 1, color: heapDivider),
        ),
      ],
    );
  }
}

class _DueDateMetadata extends StatelessWidget {
  const _DueDateMetadata({required this.date, this.neutral = false});
  final String date;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral ? const Color(0xFF68716C) : heapMuted;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.calendar_today, size: 16, color: color),
        ),
        Text(date, style: TextStyle(color: color, fontSize: 14)),
      ],
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
