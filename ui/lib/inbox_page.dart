import 'package:flutter/material.dart';

import 'heap_style.dart';
import 'inbox_task.dart';
import 'task_widgets.dart';

class TaskListBody extends StatelessWidget {
  const TaskListBody({
    super.key,
    required this.onHeap,
    required this.tasks,
    required this.loaded,
    required this.loading,
    required this.stale,
    required this.error,
    required this.scroll,
    required this.headingFocus,
    required this.onSelect,
    required this.onRetry,
    required this.onOpen,
    required this.rowKey,
    required this.rowFocus,
    this.organizationNotice,
    this.captureWarning,
    this.captureNotice,
    this.highlightedId,
    this.filters,
    this.filteredOut = false,
    this.onClearFilter,
    this.onComplete,
    this.completionPending,
    this.completionUncertain,
    this.onCheckCompletion,
    this.completionChecking,
    this.completionError,
  });
  final bool onHeap;
  final List<InboxTask> tasks;
  final bool loaded;
  final bool loading;
  final bool stale;
  final String? error;
  final ScrollController scroll;
  final FocusNode headingFocus;
  final ValueChanged<bool> onSelect;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpen;
  final Key Function(String) rowKey;
  final FocusNode Function(String) rowFocus;
  final Widget? organizationNotice;
  final String? captureWarning;
  final String? captureNotice;
  final String? highlightedId;
  final Widget? filters;
  final bool filteredOut;
  final VoidCallback? onClearFilter;
  final ValueChanged<String>? onComplete;
  final bool Function(String)? completionPending;
  final bool Function(String)? completionUncertain;
  final ValueChanged<String>? onCheckCompletion;
  final bool Function(String)? completionChecking;
  final String? Function(String)? completionError;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: CappedContent(
      child: Scrollbar(
        controller: scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: scroll,
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width >= 600 ? 24 : 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Focus(
                focusNode: headingFocus,
                child: Text(
                  onHeap ? 'Heap' : 'Inbox',
                  key: Key(onHeap ? 'heap-heading' : 'inbox-heading'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: heapInk,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                onHeap
                    ? 'On the heap, not necessarily unblocked or started.'
                    : 'Capture now. Organize later.',
                style: const TextStyle(fontSize: 15, color: heapMuted),
              ),
              if (onHeap)
                const Text(
                  'Longest on the heap first.',
                  style: TextStyle(color: heapMuted),
                ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Task lists',
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  selected: {onHeap},
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? heapGreen
                          : heapCanvas,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : heapInk,
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Inbox', key: Key('inbox-tab')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Heap', key: Key('on-heap-tab')),
                    ),
                  ],
                  onSelectionChanged: (selection) => onSelect(selection.single),
                ),
              ),
              if (filters case final controls?) ...[
                const SizedBox(height: 12),
                controls,
              ],
              const SizedBox(height: 20),
              ?organizationNotice,
              if (captureWarning case final warning?)
                StatusPanel(message: warning),
              if (captureNotice case final notice?)
                StatusPanel(message: notice),
              if (loading && !loaded)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      Text(
                        onHeap
                            ? 'Loading tasks on the heap…'
                            : 'Loading inbox…',
                      ),
                    ],
                  ),
                ),
              if (!loaded && !loading) ...[
                const Icon(Icons.cloud_off_outlined),
                Text(
                  onHeap
                      ? 'Could not load tasks on the heap.'
                      : 'Could not load the inbox.',
                ),
                const Text(
                  'Check your server or VPN connection, then try again.',
                ),
                StatusPanel(
                  message: error ?? 'Could not reach the server.',
                  actions: [
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ),
              ],
              if (loaded && stale)
                StatusPanel(
                  message: 'Showing previously loaded tasks. This list may be out of date.',
                  actions: [
                    TextButton(
                      onPressed: loading ? null : onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              if (loading && loaded)
                const Column(
                  children: [LinearProgressIndicator(), Text('Refreshing…')],
                ),
              if (loaded && filteredOut) ...[
                Semantics(
                  liveRegion: true,
                  child: const Text('No tasks match this filter'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('clear-heap-filter'),
                    onPressed: onClearFilter,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    child: const Text('Clear filter'),
                  ),
                ),
              ],
              if (loaded && tasks.isEmpty && !filteredOut) ...[
                Text(
                  stale
                      ? 'Previously loaded list was empty.'
                      : onHeap
                      ? 'Nothing on the heap yet.'
                      : 'Your inbox is empty.',
                  key: Key(onHeap ? 'empty-on-heap' : 'empty-inbox'),
                ),
                Text(
                  onHeap
                      ? 'Give an inbox task a priority and duration, then save.'
                      : 'Tap + to capture a task.',
                ),
                if (onHeap)
                  OutlinedButton(
                    key: const Key('go-to-inbox'),
                    onPressed: () => onSelect(false),
                    child: const Text('Go to inbox'),
                  ),
              ],
              for (final task in tasks)
                TaskRow(
                  key: rowKey(task.id),
                  task: task,
                  focusNode: rowFocus(task.id),
                  highlighted: highlightedId == task.id,
                  onOpen: () => onOpen(task.id),
                  onHeap: onHeap,
                  onComplete: onHeap ? () => onComplete?.call(task.id) : null,
                  completionPending: completionPending?.call(task.id) ?? false,
                  completionUncertain:
                      completionUncertain?.call(task.id) ?? false,
                  onCheckCompletion: onHeap
                      ? () => onCheckCompletion?.call(task.id)
                      : null,
                  completionChecking:
                      completionChecking?.call(task.id) ?? false,
                  completionError: completionError?.call(task.id),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
