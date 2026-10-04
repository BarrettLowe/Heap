import 'package:flutter/material.dart';

import 'heap_style.dart';
import 'task_widgets.dart';

class TaskToolbar extends StatelessWidget {
  const TaskToolbar({
    super.key,
    required this.onTasks,
    required this.onCapture,
    required this.onProjects,
    this.projectsSelected = false,
    required this.captureFocus,
  });
  final VoidCallback onTasks;
  final VoidCallback onCapture;
  final VoidCallback onProjects;
  final bool projectsSelected;
  final FocusNode captureFocus;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: heapCanvas,
      border: Border(top: BorderSide(color: heapDivider)),
    ),
    child: SafeArea(
      top: false,
      child: CappedContent(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tasks = _destination(
                'Tasks',
                Icons.format_list_bulleted,
                'tasks-toolbar',
                !projectsSelected,
                onTasks,
              );
              final projects = _destination(
                'Projects',
                Icons.bar_chart_rounded,
                'projects-toolbar',
                projectsSelected,
                onProjects,
              );
              final capture = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 64,
                    child: OverflowBox(
                      minWidth: 64,
                      maxWidth: 64,
                      child: IconButton.filled(
                        key: const Key('open-capture'),
                        tooltip: 'Capture task',
                        focusNode: captureFocus,
                        onPressed: onCapture,
                        style: IconButton.styleFrom(
                          backgroundColor: heapGreen,
                          foregroundColor: Colors.white,
                          fixedSize: const Size(64, 64),
                        ),
                        icon: const Icon(Icons.add, size: 30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Capture',
                    style: TextStyle(fontSize: 12, color: heapInk),
                  ),
                ],
              );
              final today = _soon('Today', Icons.calendar_today_outlined);
              final settings = _soon('Settings', Icons.settings);
              final twoRows =
                  constraints.maxWidth / 5 <
                  MediaQuery.textScalerOf(context).scale(12) * 4 + 8;
              if (twoRows) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: tasks),
                        Expanded(child: capture),
                        Expanded(child: today),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: projects),
                        Expanded(child: settings),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: tasks),
                  Expanded(child: today),
                  Expanded(child: capture),
                  Expanded(child: projects),
                  Expanded(child: settings),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _destination(
    String label,
    IconData icon,
    String key,
    bool selected,
    VoidCallback onPressed,
  ) => MergeSemantics(
    child: Semantics(
      selected: selected,
      child: TextButton(
        key: Key(key),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: heapInk,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? heapHighlight : null,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 24),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );

  Widget _soon(String label, IconData icon) => Semantics(
    label: '$label. Coming later. Unavailable.',
    enabled: false,
    excludeSemantics: true,
    child: Padding(
      key: Key('soon-${label.toLowerCase()}'),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: heapMuted),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: heapMuted)),
          const Text('Soon', style: TextStyle(fontSize: 10, color: heapMuted)),
        ],
      ),
    ),
  );
}
