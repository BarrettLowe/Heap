import 'package:flutter/material.dart';

import 'inbox_controller.dart';
import 'inbox_task.dart';
import 'task_widgets.dart';

class CaptureSheet extends StatefulWidget {
  const CaptureSheet({
    super.key,
    required this.controller,
    required this.title,
    required this.focus,
    required this.onCaptured,
  });
  final InboxController controller;
  final TextEditingController title;
  final FocusNode focus;
  final ValueChanged<InboxTask> onCaptured;
  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<CaptureSheet> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _capture({bool confirmDuplicate = false}) async {
    final submitted = widget.title.text;
    final saved = await widget.controller.capture(
      submitted,
      confirmDuplicate: confirmDuplicate,
    );
    if (!mounted || !saved) return;
    final task = widget.controller.lastCaptured!;
    widget.onCaptured(task);
    if (widget.title.text == submitted) {
      widget.title.clear();
      Navigator.of(context).pop(task);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return PopScope<InboxTask>(
        canPop: !c.saving,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: CappedContent(
              width: 560,
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Capture task',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            key: const Key('close-capture'),
                            tooltip: 'Close capture',
                            onPressed: c.saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('task-title'),
                        controller: widget.title,
                        focusNode: widget.focus,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Task title',
                          hintText: 'What needs doing?',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _capture(),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Unsaved capture text stays here until you add it or clear it.',
                      ),
                      const SizedBox(height: 16),
                      if (c.duplicateWarning case final warning?)
                        StatusPanel(
                          message: warning,
                          actions: [
                            TextButton(
                              key: const Key('capture-refresh'),
                              onPressed: c.loading || c.saving ? null : c.load,
                              child: const Text('Refresh inbox'),
                            ),
                            if (c.canResubmitAfterUnknown)
                              TextButton(
                                key: const Key('capture-resubmit'),
                                onPressed: () =>
                                    _capture(confirmDuplicate: true),
                                child: const Text(
                                  'Submit again (may duplicate)',
                                ),
                              ),
                          ],
                        ),
                      if (c.error != null && !c.unknownOutcome)
                        StatusPanel(message: c.error!),
                      FilledButton.icon(
                        key: const Key('capture'),
                        onPressed: c.saving || c.unknownOutcome
                            ? null
                            : _capture,
                        icon: c.saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(c.saving ? 'Saving…' : 'Add task'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
