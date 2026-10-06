import 'package:flutter/material.dart';

import 'calendar_date.dart';

import 'heap_api.dart';
import 'heap_style.dart';
import 'project.dart';
import 'project_widgets.dart';
import 'task_detail.dart';
import 'task_editor_controller.dart';
import 'task_widgets.dart';

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.id,
    required this.service,
    required this.projects,
    required this.sourceOnHeap,
    required this.onUncertainLeave,
  });
  final String id;
  final OrganizationService service;
  final ProjectService projects;
  final bool sourceOnHeap;
  final VoidCallback onUncertainLeave;
  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late final TaskEditorController _controller;
  final _title = TextEditingController();
  final _dueDateText = TextEditingController();
  final _titleFocus = FocusNode();
  final _headingFocus = FocusNode();
  final _priorityFocus = FocusNode();
  final _durationFocus = FocusNode();
  final _dueDateFocus = FocusNode();
  final _waitingFocus = FocusNode();
  FocusNode? _lastFieldFocus;
  final _scroll = ScrollController();
  bool _allowPop = false;
  bool _dialogOpen = false;
  bool _titleTouched = false;
  List<Project> _projects = const [];
  bool _projectsLoading = false;
  bool _projectsFailed = false;

  @override
  void initState() {
    super.initState();
    for (final focus in [
      _titleFocus,
      _priorityFocus,
      _durationFocus,
      _dueDateFocus,
      _waitingFocus,
    ]) {
      focus.addListener(() {
        if (focus.hasFocus) _lastFieldFocus = focus;
      });
    }
    _controller = TaskEditorController(widget.service, widget.id)
      ..addListener(_changed);
    _controller.load();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _projectsLoading = true;
      _projectsFailed = false;
    });
    try {
      final projects = await widget.projects.listProjects();
      if (mounted) setState(() => _projects = projects);
    } on HeapApiException {
      if (mounted) setState(() => _projectsFailed = true);
    } finally {
      if (mounted) setState(() => _projectsLoading = false);
    }
  }

  String _dueDateLabel(CalendarDate? date) => date == null
      ? 'None'
      : MaterialLocalizations.of(context).formatCompactDate(date.toLocalDate());

  void _changed() {
    if (!mounted) return;
    final draft = _controller.draft;
    if (draft != null && _title.text != draft.title) _title.text = draft.title;
    if (draft != null) {
      final date = draft.dueDate;
      final text = date == null ? '' : _dueDateLabel(date);
      if (_dueDateText.text != text) _dueDateText.text = text;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _title.dispose();
    _dueDateText.dispose();
    _titleFocus.dispose();
    _headingFocus.dispose();
    _priorityFocus.dispose();
    _durationFocus.dispose();
    _dueDateFocus.dispose();
    _waitingFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_controller.saving || _dialogOpen || _allowPop) return;
    if (_controller.matching case final task?) {
      _pop(task);
      return;
    }
    final lastFocus = _lastFieldFocus ?? _headingFocus;
    if (_controller.dirty || _controller.uncertain) {
      _dialogOpen = true;
      final uncertain = _controller.uncertain;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            uncertain ? 'Leave without checking the save?' : 'Discard changes?',
          ),
          content: Text(
            uncertain
                ? 'The task may already have been saved on the server. Discarding these local edits will not undo a possible save.'
                : 'Your edits have not been saved.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                uncertain ? 'Leave and discard draft' : 'Discard changes',
              ),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (!mounted) return;
      if (discard != true) {
        lastFocus.requestFocus();
        return;
      }
    }
    if (_controller.uncertain) widget.onUncertainLeave();
    _pop();
  }

  void _pop([TaskDetail? task]) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(task);
    });
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _titleTouched = true);
    final task = await _controller.save();
    if (!mounted) return;
    if (task != null) {
      _pop(task);
      return;
    }
    final errors = _controller.fieldErrors;
    final focus = errors.containsKey('title')
        ? _titleFocus
        : errors.containsKey('priority')
        ? _priorityFocus
        : errors.containsKey('duration_minutes')
        ? _durationFocus
        : errors.containsKey('due_date')
        ? _dueDateFocus
        : errors.containsKey('externally_blocked')
        ? _waitingFocus
        : null;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focus.requestFocus();
        if (focus.context case final fieldContext?) {
          Scrollable.ensureVisible(fieldContext);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<TaskDetail>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(24) + 32,
        title: CappedContent(
          width: 640,
          child: Row(
            children: [
              IconButton(
                key: const Key('editor-back'),
                tooltip: 'Cancel editing',
                onPressed: _controller.saving ? null : _cancel,
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(
                child: Text(
                  'Edit task',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: CappedContent(
          width: 640,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inline =
                  constraints.maxHeight < 400 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final padding = MediaQuery.sizeOf(context).width >= 600
                  ? 24.0
                  : 16.0;
              final content = _form(context);
              final actions = _actions(context);
              final scroller = Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...content,
                      if (inline) ...[const SizedBox(height: 24), actions],
                    ],
                  ),
                ),
              );
              if (inline) return scroller;
              return Column(
                children: [
                  Expanded(child: scroller),
                  if (_controller.saved != null || _controller.missing)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      child: actions,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  List<Widget> _form(BuildContext context) {
    final controller = _controller;
    final saved = controller.saved;
    if (saved == null && controller.loading) {
      return [
        Semantics(
          liveRegion: true,
          child: const Column(
            children: [CircularProgressIndicator(), Text('Loading task…')],
          ),
        ),
      ];
    }
    if (saved == null) {
      return [
        StatusPanel(
          message: controller.missing
              ? 'This task is no longer available.'
              : 'Could not load this task. Your list may be out of date.',
          actions: [
            if (!controller.missing)
              TextButton(
                key: const Key('detail-retry'),
                onPressed: controller.load,
                child: const Text('Retry'),
              ),
            if (controller.missing)
              TextButton(
                onPressed: _cancel,
                child: Text(
                  widget.sourceOnHeap ? 'Back to the heap' : 'Back to inbox',
                ),
              ),
          ],
        ),
      ];
    }
    final draft = controller.draft!;
    final status = controller.completed
        ? 'Completed'
        : saved.status == 'on_heap'
        ? 'On the heap'
        : 'In inbox';
    final fields = <Widget>[
      Focus(
        focusNode: _headingFocus,
        autofocus: true,
        child: Text(
          status,
          key: const Key('editor-status'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 16),
      ..._status(context),
    ];
    if (controller.completed) {
      fields.addAll([
        const StatusPanel(
          message: 'This task is completed and cannot be edited.',
        ),
        _summary(controller.comparison ?? saved, 'Saved task'),
        if (controller.dirty || controller.uncertain) ...[
          const SizedBox(height: 16),
          const Text('Your unsaved draft'),
          _draftSummary(draft),
        ],
      ]);
      return fields;
    }
    if (controller.missing) {
      fields.addAll([
        const StatusPanel(
          message: 'This task is no longer available. Your draft is shown below, but this task cannot be saved.',
        ),
        _draftSummary(draft),
      ]);
      return fields;
    }
    fields.addAll([
      TextFormField(
        key: const Key('editor-title'),
        controller: _title,
        focusNode: _titleFocus,
        enabled: controller.editable,
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        scrollPadding: const EdgeInsets.all(32),
        decoration: InputDecoration(
          labelText: 'Task title',
          border: const OutlineInputBorder(),
          errorText:
              controller.fieldErrors['title'] ??
              (_titleTouched && draft.title.trim().isEmpty
                  ? 'Enter a task title.'
                  : null),
        ),
        onChanged: (value) {
          _titleTouched = true;
          controller.edit(title: value);
        },
      ),
      const SizedBox(height: 16),
      _projectDropdown(draft, controller.editable),
      if (_projectsLoading)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Loading projects…'),
          ),
        ),
      if (_projectsFailed)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('Could not load projects.'),
            TextButton(
              key: const Key('editor-projects-retry'),
              onPressed: _projectsLoading ? null : _loadProjects,
              child: const Text('Retry'),
            ),
          ],
        ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final priority = _selectionGroup(
            label: 'Priority',
            key: 'editor-priority',
            focusNode: _priorityFocus,
            value: draft.priority ?? 0,
            options: {0: 'Unset', ...priorityLabels},
            error: controller.fieldErrors['priority'],
            changed: (value) => controller.edit(
              priority: value == 0 ? null : value,
              setPriority: true,
            ),
          );
          final duration = _selectionGroup(
            label: 'Duration',
            key: 'editor-duration',
            focusNode: _durationFocus,
            value: draft.durationMinutes ?? 0,
            options: {
              0: 'Unknown',
              for (final value in durationChoices) value: formatDuration(value),
            },
            error: controller.fieldErrors['duration_minutes'],
            changed: (value) => controller.edit(
              durationMinutes: value == 0 ? null : value,
              setDuration: true,
            ),
          );
          if (MediaQuery.sizeOf(context).width >= 600 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.5) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: priority),
                const SizedBox(width: 16),
                Expanded(child: duration),
              ],
            );
          }
          return Column(
            children: [priority, const SizedBox(height: 16), duration],
          );
        },
      ),
      const SizedBox(height: 16),
      _dueDateField(draft, controller.editable),
      const SizedBox(height: 16),
      CheckboxListTile(
        key: const Key('editor-awaiting'),
        focusNode: _waitingFocus,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: draft.externallyBlocked,
        onChanged: controller.editable
            ? (value) => controller.edit(externallyBlocked: value)
            : null,
        title: const Text('Awaiting external dependencies'),
        subtitle: const Text(
          'Manual flag only. Organized tasks stay on the heap while waiting.',
        ),
      ),
      if (controller.fieldErrors['externally_blocked'] case final message?)
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (!controller.editable && controller.needsChoice) ...[
        const SizedBox(height: 16),
        const Text('Your unsaved draft'),
        _draftSummary(draft),
      ],
    ]);
    return fields;
  }

  Widget _dueDateField(OrganizationDraft draft, bool editable) {
    final date = draft.dueDate;
    Future<void> pickDate() async {
      if (!editable) return;
      final selected = await showDatePicker(
        context: context,
        initialDate: date?.toLocalDate() ?? DateTime.now(),
        firstDate: DateTime(1, 1, 1),
        lastDate: DateTime(9999, 12, 31),
        helpText: 'Select due date',
      );
      if (!mounted) return;
      _dueDateFocus.requestFocus();
      if (selected == null) return;
      final picked = CalendarDate.fromLocalDate(selected);
      if (picked != date) {
        _controller.edit(dueDate: picked, setDueDate: true);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Due date: ${_dueDateLabel(date)}',
          child: TextFormField(
            key: const Key('editor-due-date'),
            focusNode: _dueDateFocus,
            readOnly: true,
            enabled: editable,
            onTap: pickDate,
            decoration: InputDecoration(
              labelText: 'Due date',
              hintText: 'None',
              border: const OutlineInputBorder(),
              errorText: _controller.fieldErrors['due_date'],
              suffixIcon: IconButton(
                tooltip: 'Choose due date',
                onPressed: editable ? pickDate : null,
                icon: const Icon(Icons.calendar_today),
              ),
            ),
            controller: _dueDateText,
          ),
        ),
        if (date != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: 'Clear due date',
              button: true,
              child: TextButton(
                key: const Key('editor-clear-due-date'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: editable
                    ? () => _controller.edit(setDueDate: true)
                    : null,
                child: const Text('Clear date'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _projectDropdown(OrganizationDraft draft, bool editable) {
    final projects = [..._projects];
    if (draft.projectId != null &&
        !projects.any((project) => project.id == draft.projectId)) {
      projects.add(
        Project(
          id: draft.projectId!,
          name: 'Current project',
          description: null,
          color: null,
          icon: null,
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('editor-project-${draft.projectId}'),
      initialValue: draft.projectId ?? '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Project',
        border: OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => [
        const Align(alignment: Alignment.centerLeft, child: Text('No project')),
        for (final project in projects)
          Align(
            alignment: Alignment.centerLeft,
            child: _projectOption(project),
          ),
      ],
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('No project')),
        for (final project in projects)
          DropdownMenuItem<String>(
            value: project.id,
            child: _projectOption(project),
          ),
      ],
      onChanged: editable
          ? (value) => _controller.edit(
              projectId: value!.isEmpty ? null : value,
              setProject: true,
            )
          : null,
    );
  }

  Widget _projectOption(Project project) => Row(
    children: [
      ProjectSwatch(project.color, size: 16),
      const SizedBox(width: 8),
      Icon(projectGlyph(project.icon), size: 20, color: heapInk),
      const SizedBox(width: 8),
      Expanded(child: Text(project.name, overflow: TextOverflow.ellipsis)),
    ],
  );

  Widget _selectionGroup({
    required String label,
    required String key,
    required FocusNode focusNode,
    required int value,
    required Map<int, String> options,
    required String? error,
    required ValueChanged<int> changed,
  }) => Focus(
    key: Key(key),
    focusNode: focusNode,
    child: Semantics(
      label: label,
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in options.entries)
                ChoiceChip(
                  key: Key('$key-${option.key}'),
                  label: Text(option.value),
                  selected: value == option.key,
                  onSelected: _controller.editable
                      ? (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          changed(option.key);
                        }
                      : null,
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );

  List<Widget> _status(BuildContext context) {
    final c = _controller;
    return [
      if (c.saving)
        Semantics(liveRegion: true, child: const Text('Saving task')),
      if (c.uncertain)
        StatusPanel(
          message: c.needsChoice
              ? 'The save may have succeeded. Your draft has been kept. Reload the saved task before trying again.'
              : 'Saving again is a new request; the earlier save may still have reached the server.',
        ),
      if (c.conflict)
        const StatusPanel(
          message: 'This task changed on the server. Your edits have been kept. Reload the saved task before deciding what to keep.',
        ),
      if (c.error != null)
        StatusPanel(
          message: c.fieldErrors.isNotEmpty
              ? 'Task could not be saved. Check the highlighted fields.'
              : c.error!,
        ),
      if (c.notice case final notice?)
        StatusPanel(message: notice, consequence: true),
      if (c.needsChoice && !c.missing && !c.completed && c.matching == null)
        TextButton(
          key: const Key('reload-saved-task'),
          onPressed: c.loading ? null : c.reconcile,
          child: Text(c.loading ? 'Reloading…' : 'Reload saved task'),
        ),
      if (c.matching != null)
        const StatusPanel(
          message: 'The saved task matches your changes. This confirms its current state.',
          consequence: true,
        ),
      if (c.comparison != null && !c.completed && c.matching == null) ...[
        if (c.uncertain)
          const Text(
            'The saved task does not match your draft. The earlier save may still finish.',
          ),
        _summary(c.comparison!, 'Saved on server'),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              key: const Key('use-saved-version'),
              onPressed: c.loading
                  ? null
                  : () => c.chooseVersion(keepEdits: false),
              child: const Text('Use saved version'),
            ),
            TextButton(
              key: const Key('keep-my-edits'),
              onPressed: c.loading
                  ? null
                  : () => c.chooseVersion(keepEdits: true),
              child: const Text('Keep my edits'),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _summary(TaskDetail task, String heading) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(heading, style: Theme.of(context).textTheme.titleMedium),
      Text('Task title: ${task.title}'),
      Text(
        'Status: ${task.status == 'on_heap'
            ? 'On the heap'
            : task.status == 'inbox'
            ? 'In inbox'
            : 'Completed'}',
      ),
      _draftSummary(OrganizationDraft.fromTask(task), includeTitle: false),
    ],
  );
  Widget _draftSummary(
    OrganizationDraft draft, {
    bool includeTitle = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (includeTitle) Text('Task title: ${draft.title}'),
      Text('Project: ${_projectName(draft.projectId)}'),
      Text('Priority: ${priorityLabels[draft.priority] ?? 'Unset'}'),
      Text(
        'Duration: ${draft.durationMinutes == null ? 'Unknown' : formatDuration(draft.durationMinutes!)}',
      ),
      Text('Due date: ${_dueDateLabel(draft.dueDate)}'),
      Text(
        'Awaiting external dependencies: ${draft.externallyBlocked ? 'Yes' : 'No'}',
      ),
    ],
  );

  String _projectName(String? id) {
    if (id == null) return 'No project';
    for (final project in _projects) {
      if (project.id == id) return project.name;
    }
    return 'Current project';
  }

  Widget _actions(BuildContext context) {
    final c = _controller;
    if (c.missing || c.completed) {
      return OutlinedButton(
        onPressed: _cancel,
        child: Text(widget.sourceOnHeap ? 'Back to the heap' : 'Back to inbox'),
      );
    }
    if (c.matching case final task?) {
      return FilledButton(
        key: const Key('return-confirmed'),
        onPressed: () => _pop(task),
        child: Text(
          task.status == 'on_heap' ? 'Return to the heap' : 'Return to inbox',
        ),
      );
    }
    if (c.saved == null) return const SizedBox.shrink();
    final inbox = c.saved!.status == 'inbox';
    final draft = c.draft!;
    final qualifying = draft.priority != null && draft.durationMinutes != null;
    final save = FilledButton(
      key: const Key('editor-save'),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: c.canSave ? _save : null,
      child: _buttonLabel(c.saving, 'Save'),
    );
    final wide =
        MediaQuery.sizeOf(context).width >= 600 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inbox && (draft.priority == null || draft.durationMinutes == null))
          const StatusPanel(
            message: 'Saving will return this task to the inbox.',
            consequence: true,
          ),
        if (!qualifying)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              draft.priority == null && draft.durationMinutes == null
                  ? 'Choose a priority and duration to qualify for the heap. You can save without them.'
                  : draft.priority == null
                  ? 'Choose a priority to qualify for the heap. You can save without it.'
                  : 'Choose a duration to qualify for the heap. You can save without it.',
            ),
          ),
        if (qualifying)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              inbox
                  ? 'Saving will put this task on the heap automatically.'
                  : 'This task stays on the heap when saved.',
            ),
          ),
        if (wide)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [save],
          )
        else
          save,
      ],
    );
  }

  Widget _buttonLabel(bool saving, String label) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      if (saving)
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      Text(saving ? 'Saving…' : label, textAlign: TextAlign.center),
    ],
  );
}
