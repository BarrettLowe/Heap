import 'package:flutter/material.dart';

import 'capture_sheet.dart';
import 'heap_api.dart';
import 'heap_filter.dart';
import 'heap_filter_pills.dart';
import 'heap_style.dart';
import 'inbox_controller.dart';
import 'inbox_page.dart';
import 'on_heap_controller.dart';
import 'task_detail.dart';
import 'task_editor_page.dart';
import 'task_toolbar.dart';
import 'task_widgets.dart';
import 'project.dart';
import 'project_controller.dart';
import 'project_editor_page.dart';
import 'project_widgets.dart';

class TaskListsPage extends StatefulWidget {
  const TaskListsPage({
    super.key,
    required this.inbox,
    required this.organization,
    required this.projects,
  });
  final InboxController inbox;
  final OrganizationService organization;
  final ProjectService projects;
  @override
  State<TaskListsPage> createState() => _TaskListsPageState();
}

class _TaskListsPageState extends State<TaskListsPage> {
  late final OnHeapController _heap;
  late final ProjectsController _projects;
  bool _showProjects = false;
  final _uncertainProjectDeletions = <String>{};
  bool _projectsStarted = false;
  String? _projectNotice;
  String? _highlightedProject;
  final _projectsScroll = ScrollController();
  final _projectsHeading = FocusNode();
  final _addProjectFocus = FocusNode();
  final _projectKeys = <String, GlobalKey>{};
  final _projectFocus = <String, FocusNode>{};
  bool _onHeap = false;
  bool _heapStarted = false;
  HeapFilter _filter = const HeapFilter.none();
  bool _editing = false;
  bool _captureOpen = false;
  bool _refreshingLists = false;
  int _listRefreshVersion = 0;
  int _interactionEpoch = 0;
  String? _savedNotice;
  String? _highlightedId;
  final _captureText = TextEditingController();
  final _captureFieldFocus = FocusNode();
  final _captureButtonFocus = FocusNode();
  final _inboxScroll = ScrollController();
  final _heapScroll = ScrollController();
  final _inboxHeading = FocusNode();
  final _heapHeading = FocusNode();
  final _rowKeys = <String, GlobalKey>{};
  final _rowFocus = <String, FocusNode>{};
  GlobalKey _key(String id, bool heap) => _rowKeys.putIfAbsent(
    '$heap-$id',
    () => GlobalKey(debugLabel: 'task-$id'),
  );
  FocusNode _focus(String id, bool heap) =>
      _rowFocus.putIfAbsent('$heap-$id', FocusNode.new);
  @override
  void initState() {
    super.initState();
    _heap = OnHeapController(widget.organization);
    _projects = ProjectsController(widget.projects);
    widget.inbox.load();
  }

  @override
  void dispose() {
    _heap.dispose();
    _projects.dispose();
    _projectsScroll.dispose();
    _projectsHeading.dispose();
    _addProjectFocus.dispose();
    for (final focus in _projectFocus.values) {
      focus.dispose();
    }
    _captureText.dispose();
    _captureFieldFocus.dispose();
    _captureButtonFocus.dispose();
    _inboxScroll.dispose();
    _heapScroll.dispose();
    _inboxHeading.dispose();
    _heapHeading.dispose();
    for (final focus in _rowFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _interacted() {
    ++_interactionEpoch;
  }

  void _select(bool heap) {
    if (_editing || _captureOpen) return;
    _interacted();
    FocusManager.instance.primaryFocus?.unfocus();
    if (heap && !_heapStarted) {
      _heapStarted = true;
      _heap.load();
    }
    setState(() => _onHeap = heap);
  }

  void _changeFilter(HeapFilter filter) {
    _interacted();
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _filter = filter);
  }

  void _revealSelector() {
    if (_editing || _captureOpen) return;
    _interacted();
    if (_showProjects) {
      setState(() => _showProjects = false);
      return;
    }
    final scroll = _onHeap ? _heapScroll : _inboxScroll;
    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openCapture() async {
    if (_captureOpen || _editing) return;
    _interacted();
    _captureOpen = true;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final result = await showModalBottomSheet<InboxTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: heapCanvas,
      builder: (_) => CaptureSheet(
        controller: widget.inbox,
        title: _captureText,
        focus: _captureFieldFocus,
        onCaptured: (task) {
          if (!mounted) return;
          setState(() {
            _onHeap = false;
            _showProjects = false;
            _highlightedId = task.id;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Task added to inbox.')));
        },
      ),
    );
    if (!mounted) return;
    _captureOpen = false;
    setState(() {});
    if (result == null) {
      _captureButtonFocus.requestFocus();
    } else {
      _restoreRow(result.id, false, scroll: true);
    }
  }

  Future<void> _open(String id, bool sourceHeap) async {
    if (_editing || _captureOpen) return;
    _interacted();
    _editing = true;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await Navigator.of(context).push<TaskDetail>(
      MaterialPageRoute(
        builder: (_) => TaskEditorPage(
          id: id,
          service: widget.organization,
          projects: widget.projects,
          sourceOnHeap: sourceHeap,
          onUncertainLeave: () {
            widget.inbox.invalidate();
            _heap.invalidate();
          },
        ),
      ),
    );
    if (!mounted) return;
    _editing = false;
    if (result == null) {
      _restoreRow(id, sourceHeap, scroll: false);
      return;
    }
    widget.inbox.applyConfirmed(result);
    _heap.applyConfirmed(result);
    _heapStarted = true;
    final destinationHeap = result.status == 'on_heap';
    setState(() {
      _onHeap = destinationHeap;
      _highlightedId = result.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          destinationHeap
              ? _filter.matches(result)
                    ? 'Task saved to the heap.'
                    : 'Task saved to the heap. Hidden by the current filter.'
              : sourceHeap
              ? 'Task saved to inbox.'
              : 'Task saved.',
        ),
      ),
    );
    _restoreRow(id, destinationHeap, scroll: destinationHeap != sourceHeap);
    // Restore once on return, never again when the background GETs finish.
    await _refreshLists(force: true);
  }

  Future<void> _refreshLists({bool force = false}) async {
    if (_refreshingLists && !force) return;
    final version = ++_listRefreshVersion;
    setState(() => _refreshingLists = true);
    await Future.wait([widget.inbox.load(), _heap.load()]);
    if (!mounted || version != _listRefreshVersion) return;
    setState(() {
      _refreshingLists = false;
      _savedNotice = widget.inbox.error != null || _heap.error != null
          ? 'Saved, but lists could not be refreshed.'
          : null;
    });
  }

  void _restoreRow(String id, bool heap, {required bool scroll}) {
    final epoch = _interactionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _interactionEpoch ||
          _editing ||
          _captureOpen ||
          _onHeap != heap ||
          _showProjects) {
        return;
      }
      final excluded =
          heap &&
          _heap.tasks.any((task) => task.id == id && !_filter.matches(task));
      final row = excluded ? null : _rowKeys['$heap-$id']?.currentContext;
      if (row != null) {
        if (scroll) {
          Scrollable.ensureVisible(
            row,
            duration: const Duration(milliseconds: 200),
          );
        }
        if (Theme.of(context).platform != TargetPlatform.android &&
            Theme.of(context).platform != TargetPlatform.iOS) {
          _rowFocus['$heap-$id']?.requestFocus();
        }
      } else {
        final heading = heap ? _heapHeading : _inboxHeading;
        heading.requestFocus();
        if (heading.context case final headingContext?) {
          Scrollable.ensureVisible(headingContext);
        }
      }
    });
  }

  void _selectProjects() {
    if (_editing || _captureOpen) return;
    _interacted();
    FocusManager.instance.primaryFocus?.unfocus();
    _projectsStarted = true;
    if (!_showProjects) _projects.load();
    setState(() => _showProjects = true);
  }

  void _invalidateDeletedTasks(String id, {required bool uncertain}) {
    if (!mounted) return;
    setState(() {
      if (uncertain) {
        _uncertainProjectDeletions.add(id);
      } else {
        _uncertainProjectDeletions.remove(id);
      }
    });
    widget.inbox.clearAfterProjectDeletion();
    _heap.clearAfterProjectDeletion();
    _heapStarted = true;
    widget.inbox.load();
    _heap.load();
  }

  Future<void> _openProject([String? id]) async {
    if (_editing || _captureOpen) return;
    _interacted();
    _editing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await Navigator.of(context).push<ProjectEditorResult>(
      MaterialPageRoute(
        builder: (_) => ProjectEditorPage(
          id: id,
          service: widget.projects,
          onDeletionRisk: (uncertain) {
            if (id != null) {
              _invalidateDeletedTasks(id, uncertain: uncertain);
            }
          },
          onUncertainLeave: _projects.load,
        ),
      ),
    );
    if (!mounted) return;
    _editing = false;
    if (result != null) {
      if (result.deleted) {
        _projects.removeConfirmed(id!);
      } else {
        _projects.applyConfirmed(result.project!);
      }
      setState(() {
        _highlightedProject = result.project?.id;
        _projectNotice = result.deleted
            ? 'Project and all assigned tasks deleted.'
            : result.created
            ? 'Project added.'
            : 'Project saved.';
      });
    }
    final epoch = _interactionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _interactionEpoch ||
          !_showProjects ||
          _editing ||
          _captureOpen) {
        return;
      }
      if (result?.deleted == true) {
        _projectsHeading.requestFocus();
        if (_projectsHeading.context case final heading?) {
          Scrollable.ensureVisible(heading);
        }
        return;
      }
      final target = result?.project?.id ?? id;
      final row = _projectKeys[target]?.currentContext;
      if (row != null) {
        if (result != null) {
          Scrollable.ensureVisible(
            row,
            duration: const Duration(milliseconds: 200),
          );
        }
        _projectFocus[target]?.requestFocus();
      } else {
        _addProjectFocus.requestFocus();
      }
    });
    if (result != null) await _projects.load();
  }

  Widget _projectsList() => ProjectsListBody(
    controller: _projects,
    scroll: _projectsScroll,
    headingFocus: _projectsHeading,
    addFocus: _addProjectFocus,
    onAdd: _openProject,
    onOpen: _openProject,
    rowKey: (id) => _projectKeys.putIfAbsent(
      id,
      () => GlobalKey(debugLabel: 'project-$id'),
    ),
    rowFocus: (id) => _projectFocus.putIfAbsent(id, FocusNode.new),
    highlightedId: _highlightedProject,
    notice: _projectNotice,
  );

  Widget? _noticePanel() => _savedNotice == null
      ? null
      : StatusPanel(
          message: _savedNotice!,
          actions: [
            TextButton(
              key: const Key('refresh-lists'),
              onPressed: _refreshingLists ? null : _refreshLists,
              child: const Text('Refresh lists'),
            ),
          ],
        );
  Widget _list(bool heap) => TaskListBody(
    onHeap: heap,
    tasks: heap
        ? _heap.tasks.where(_filter.matches).toList()
        : widget.inbox.tasks,
    filters: heap
        ? HeapFilterPills(filter: _filter, onChanged: _changeFilter)
        : null,
    filteredOut:
        heap && _heap.tasks.isNotEmpty && !_heap.tasks.any(_filter.matches),
    onClearFilter: heap ? () => _changeFilter(const HeapFilter.none()) : null,
    loaded: heap ? _heap.loaded : widget.inbox.loaded,
    loading: heap ? _heap.loading : widget.inbox.loading,
    stale:
        _uncertainProjectDeletions.isNotEmpty ||
        (heap ? _heap.stale : widget.inbox.stale),
    error: heap ? _heap.error : widget.inbox.error,
    scroll: heap ? _heapScroll : _inboxScroll,
    headingFocus: heap ? _heapHeading : _inboxHeading,
    onSelect: _select,
    onRetry: heap ? _heap.load : widget.inbox.load,
    onOpen: (id) => _open(id, heap),
    onComplete: heap ? _heap.toggleCompletion : null,
    completionPending: heap ? _heap.isPending : null,
    completionUncertain: heap ? _heap.isUncertain : null,
    onCheckCompletion: heap ? _heap.checkCompletion : null,
    completionChecking: heap ? _heap.isChecking : null,
    completionError: heap ? _heap.errorFor : null,
    rowKey: (id) => _key(id, heap),
    rowFocus: (id) => _focus(id, heap),
    organizationNotice: _noticePanel(),
    highlightedId: _highlightedId,
    captureWarning: widget.inbox.unknownOutcome && !_captureOpen
        ? 'A capture may have succeeded. Reopen capture to check before submitting again.'
        : null,
    captureNotice: heap ? null : widget.inbox.notice,
  );

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _interacted(),
    child: Focus(
      onKeyEvent: (_, _) {
        _interacted();
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: heapCanvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              CappedContent(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      widget.inbox,
                      _heap,
                      _projects,
                    ]),
                    builder: (context, _) => LayoutBuilder(
                      builder: (context, constraints) {
                        final refresh = IconButton(
                          key: const Key('refresh'),
                          tooltip: _showProjects
                              ? 'Refresh projects'
                              : _onHeap
                              ? 'Refresh the heap'
                              : 'Refresh inbox',
                          onPressed: _showProjects
                              ? _projects.loading
                                    ? null
                                    : _projects.load
                              : _onHeap
                              ? _heap.loading
                                    ? null
                                    : _heap.load
                              : widget.inbox.loading
                              ? null
                              : widget.inbox.load,
                          icon: const Icon(Icons.refresh, color: heapInk),
                        );
                        if (constraints.maxWidth <
                            MediaQuery.textScalerOf(context).scale(32) * 4 +
                                100) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const HeapBrand(),
                              Align(
                                alignment: Alignment.centerRight,
                                child: refresh,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const Expanded(child: HeapBrand()),
                            refresh,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.inbox,
                    _heap,
                    _projects,
                  ]),
                  builder: (context, _) => IndexedStack(
                    index: _showProjects
                        ? 2
                        : _onHeap
                        ? 1
                        : 0,
                    children: [
                      _list(false),
                      if (_heapStarted)
                        _list(true)
                      else
                        const SizedBox.shrink(),
                      if (_projectsStarted)
                        _projectsList()
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: TaskToolbar(
          onTasks: _revealSelector,
          onCapture: _openCapture,
          onProjects: _selectProjects,
          projectsSelected: _showProjects,
          captureFocus: _captureButtonFocus,
        ),
      ),
    ),
  );
}
