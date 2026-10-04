import 'package:flutter/material.dart';

import 'heap_api.dart';
import 'heap_style.dart';
import 'project.dart';
import 'project_controller.dart';
import 'project_widgets.dart';
import 'task_widgets.dart';

class ProjectEditorPage extends StatefulWidget {
  const ProjectEditorPage({
    super.key,
    this.id,
    required this.service,
    required this.onDeletionRisk,
    required this.onUncertainLeave,
  });
  final String? id;
  final ProjectService service;
  final ValueChanged<bool> onDeletionRisk;
  final VoidCallback onUncertainLeave;
  @override
  State<ProjectEditorPage> createState() => _ProjectEditorPageState();
}

class _ProjectEditorPageState extends State<ProjectEditorPage> {
  late final ProjectEditorController _controller;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _headingFocus = FocusNode();
  final _iconFocus = FocusNode();
  final _deleteFocus = FocusNode();
  final _scroll = ScrollController();
  FocusNode? _lastFocus;
  bool _allowPop = false;
  bool _dialogOpen = false;
  bool _nameTouched = false;
  bool _reportedUnavailable = false;

  @override
  void initState() {
    super.initState();
    for (final focus in [_nameFocus, _iconFocus, _deleteFocus]) {
      focus.addListener(() {
        if (focus.hasFocus) _lastFocus = focus;
      });
    }
    _controller = ProjectEditorController(widget.service, widget.id)
      ..addListener(_changed);
    if (widget.id != null) _controller.load();
  }

  void _changed() {
    if (!mounted) return;
    if (widget.id != null && _controller.missing && !_reportedUnavailable) {
      _reportedUnavailable = true;
      widget.onDeletionRisk(false);
    } else if (!_controller.missing) {
      _reportedUnavailable = false;
    }
    if (_controller.draft case final draft?) {
      if (_name.text != draft.name) _name.text = draft.name;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _name.dispose();
    for (final focus in [_nameFocus, _headingFocus, _iconFocus, _deleteFocus]) {
      focus.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String action) async {
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              title == 'Discard changes?' ? 'Keep editing' : 'Cancel',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    return result == true;
  }

  Future<void> _cancel() async {
    if (_controller.pending || _dialogOpen || _allowPop) return;
    final focus = _lastFocus ?? _headingFocus;
    if (_controller.dirty || _controller.uncertain) {
      final discard = await _confirm(
        _controller.uncertain
            ? 'Leave with an uncertain result?'
            : 'Discard changes?',
        _controller.uncertain
            ? 'The request may have succeeded. Leaving discards only this local draft, not a possible change on the server.'
            : 'Your edits have not been saved.',
        'Discard changes',
      );
      if (!mounted) return;
      if (!discard) {
        focus.requestFocus();
        return;
      }
    }
    if (_controller.uncertain) widget.onUncertainLeave();
    _pop();
  }

  void _pop([ProjectEditorResult? result]) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _save() async {
    if (!_controller.canSave || _dialogOpen) return;
    var confirmUncertain = false;
    if (_controller.uncertain) {
      confirmUncertain = await _confirm(
        'Send another request?',
        widget.id == null
            ? 'The earlier request may still create a project. Saving again may create a duplicate.'
            : 'The earlier request may still finish. Saving again sends a new request.',
        'Save again',
      );
      if (!mounted || !confirmUncertain) return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _nameTouched = true);
    final result = await _controller.save(confirmUncertain: confirmUncertain);
    if (!mounted) return;
    if (result != null) {
      _pop(ProjectEditorResult.saved(result, created: widget.id == null));
    } else if (_controller.fieldErrors.containsKey('name')) {
      _nameFocus.requestFocus();
      if (_nameFocus.context case final field?) {
        if (field.mounted) Scrollable.ensureVisible(field);
      }
    }
  }

  Future<void> _delete() async {
    if (!_controller.editable ||
        _dialogOpen ||
        (_controller.uncertain && !_controller.checked)) {
      return;
    }
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteProjectDialog(
        name: _controller.saved!.name,
        controller: _controller,
        onDeletionRisk: widget.onDeletionRisk,
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (result == true) {
      _pop(const ProjectEditorResult.deleted());
    } else {
      _deleteFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope<ProjectEditorResult>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: heapCanvas,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(24) + 32,
          title: CappedContent(
            width: 640,
            child: Row(
              children: [
                IconButton(
                  key: const Key('project-back'),
                  tooltip: 'Cancel editing',
                  onPressed: c.pending ? null : _cancel,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Focus(
                    focusNode: _headingFocus,
                    autofocus: widget.id != null,
                    child: Text(
                      widget.id == null ? 'Add project' : 'Edit project',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
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
                // Match the task editor's compact-height and enlarged-text footer rule.
                final inline =
                    constraints.maxHeight < 400 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                final padding = MediaQuery.sizeOf(context).width >= 600
                    ? 24.0
                    : 16.0;
                final scroller = Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._form(),
                        if (inline && c.draft != null && !c.missing) ...[
                          const SizedBox(height: 24),
                          _saveButton(),
                        ],
                      ],
                    ),
                  ),
                );
                if (inline) return scroller;
                return Column(
                  children: [
                    Expanded(child: scroller),
                    if (c.draft != null && !c.missing)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: heapDivider)),
                        ),
                        child: MediaQuery.sizeOf(context).width >= 600
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: _saveButton(),
                              )
                            : _saveButton(),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _form() {
    final c = _controller;
    return [
      if (c.loading)
        Semantics(
          liveRegion: true,
          child: Column(
            children: [CircularProgressIndicator(), Text('Loading project…')],
          ),
        ),
      if (c.missing)
        const StatusPanel(message: 'This project is no longer available.'),
      if (c.error != null && !c.missing)
        StatusPanel(
          message: c.draft == null ? 'Could not load this project.' : c.error!,
          actions: [
            if (c.draft == null && !c.missing)
              TextButton(
                onPressed: c.loading ? null : c.load,
                child: const Text('Retry'),
              ),
          ],
        ),
      if (c.uncertain)
        StatusPanel(
          message: 'The request may have succeeded. Your draft has been kept. Check projects before trying again.',
          actions: [
            TextButton(
              key: const Key('check-projects'),
              onPressed: c.loading || c.pending ? null : c.check,
              child: const Text('Check projects'),
            ),
          ],
        ),
      if (c.checkNotice != null)
        StatusPanel(message: c.checkNotice!, consequence: true),
      if (c.checkedProjects != null) ...[
        const Text('Projects currently on the server'),
        if (c.checkedProjects!.isEmpty) const Text('No projects yet.'),
        for (final project in c.checkedProjects!) Text(project.name),
        const SizedBox(height: 16),
      ],
      if (c.draft != null) ...[
        TextFormField(
          key: const Key('project-name'),
          controller: _name,
          focusNode: _nameFocus,
          autofocus: widget.id == null,
          enabled: c.editable,
          minLines: 1,
          maxLines: null,
          decoration: InputDecoration(
            labelText: 'Project name',
            border: const OutlineInputBorder(),
            errorText:
                c.fieldErrors['name'] ??
                (_nameTouched && c.draft!.name.trim().isEmpty
                    ? 'Enter a project name.'
                    : null),
          ),
          onChanged: (value) {
            _nameTouched = true;
            c.edit(name: value);
          },
        ),
        const SizedBox(height: 16),
        KeyedSubtree(
          key: const Key('project-color'),
          child: ProjectColorPalette(
            value: c.draft!.color,
            nameFocus: _nameFocus,
            error: c.fieldErrors['color'],
            onChanged: c.editable
                ? (value) => c.edit(color: value, setColor: true)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        ProjectPicker(
          key: const Key('project-icon'),
          label: 'Icon',
          value: c.draft!.icon,
          options: projectIcons,
          focusNode: _iconFocus,
          error: c.fieldErrors['icon'],
          onChanged: c.editable
              ? (value) => c.edit(icon: value, setIcon: true)
              : null,
        ),
        if (widget.id != null && !c.missing) ...[
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('project-delete'),
              focusNode: _deleteFocus,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: c.editable && (!c.uncertain || c.checked)
                  ? _delete
                  : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 12),
                    Flexible(child: Text('Delete project')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
      if (c.missing)
        TextButton(onPressed: _cancel, child: const Text('Back to Projects')),
    ];
  }

  Widget _saveButton() => FilledButton(
    key: const Key('project-save'),
    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
    onPressed: _controller.canSave ? _save : null,
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (_controller.pending)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        Text(
          _controller.pending ? 'Saving…' : 'Save',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({
    required this.name,
    required this.controller,
    required this.onDeletionRisk,
  });
  final String name;
  final ProjectEditorController controller;
  final ValueChanged<bool> onDeletionRisk;
  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  final _cancelFocus = FocusNode();
  Future<void> _delete() async {
    if (widget.controller.pending) return;
    final deleted = await widget.controller.delete();
    if (deleted || widget.controller.uncertain) {
      widget.onDeletionRisk(!deleted && !widget.controller.missing);
    }
    if (mounted) Navigator.pop(context, deleted);
  }

  @override
  void dispose() {
    _cancelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final pending = widget.controller.pending;
      return PopScope<bool>(
        canPop: !pending,
        child: AlertDialog(
          scrollable: true,
          title: const Text('Delete project?'),
          content: Text(
            'This permanently deletes "${widget.name}" and ALL tasks assigned to it, including completed tasks.\n\nThis cannot be undone.',
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    autofocus: true,
                    focusNode: _cancelFocus,
                    onPressed: pending
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('confirm-project-delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: pending ? null : _delete,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        pending ? 'Deleting…' : 'Delete project',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
