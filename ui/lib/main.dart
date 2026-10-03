import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'heap_api.dart';
import 'inbox_controller.dart';

void main() {
  final baseUri = parseApiBaseUri(
    const String.fromEnvironment('HEAP_API_BASE_URL'),
  );
  if (baseUri == null) {
    runApp(const HeapApp(configurationError: true));
    return;
  }
  runApp(
    HeapApp(
      api: HeapApi(client: http.Client(), baseUri: baseUri),
    ),
  );
}

class HeapApp extends StatefulWidget {
  const HeapApp({super.key, this.api, this.configurationError = false});

  final HeapApi? api;
  final bool configurationError;

  @override
  State<HeapApp> createState() => _HeapAppState();
}

class _HeapAppState extends State<HeapApp> {
  late final InboxController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.api == null ? null : InboxController(widget.api!);
  }

  @override
  void dispose() {
    _controller?.dispose();
    widget.api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heap',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF214E3B)),
        scaffoldBackgroundColor: const Color(0xFFFAFAF5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFAF5),
          foregroundColor: Color(0xFF214E3B),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: widget.configurationError
          ? const _ConfigurationPage()
          : InboxPage(controller: _controller!),
    );
  }
}

class _ConfigurationPage extends StatelessWidget {
  const _ConfigurationPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Heap')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Set a valid server origin with '
          '--dart-define=HEAP_API_BASE_URL=https://your-server.example',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class InboxPage extends StatefulWidget {
  const InboxPage({required this.controller, super.key});

  final InboxController controller;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _capture({bool confirmDuplicate = false}) async {
    final draft = _titleController.text;
    if (draft.trim().isEmpty || widget.controller.saving) return;
    final saved = await widget.controller.capture(
      draft,
      confirmDuplicate: confirmDuplicate,
    );
    if (saved && mounted && _titleController.text == draft) {
      _titleController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.landscape_rounded),
            SizedBox(width: 12),
            Text('Heap'),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => IconButton(
              key: const Key('refresh'),
              tooltip: 'Refresh inbox',
              onPressed: widget.controller.loading
                  ? null
                  : widget.controller.load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inbox',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('Get it out of your head. Organize it later.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('task-title'),
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                        hintText: 'What needs doing?',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _capture(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => FilledButton.icon(
                      key: const Key('capture'),
                      onPressed:
                          widget.controller.saving ||
                              widget.controller.unknownOutcome
                          ? null
                          : _capture,
                      icon: widget.controller.saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(widget.controller.saving ? 'Saving' : 'Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => _inboxBody(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inboxBody(BuildContext context) {
    final controller = widget.controller;
    if (controller.loading && !controller.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.loaded) {
      return _Unavailable(
        message:
            controller.duplicateWarning ??
            controller.error ??
            'Could not load the inbox.',
        onRetry: controller.load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.duplicateWarning case final warning?)
          _StatusMessage(
            message: warning,
            onRetry: controller.canResubmitAfterUnknown || controller.loading
                ? null
                : controller.load,
            onDuplicate: controller.canResubmitAfterUnknown
                ? () => _capture(confirmDuplicate: true)
                : null,
          ),
        if (!controller.unknownOutcome && controller.stale)
          _StatusMessage(
            message:
                'Showing saved inbox. It may be out of date. ${controller.error ?? ''}',
            onRetry: controller.loading ? null : controller.load,
          )
        else if (!controller.unknownOutcome && controller.error != null)
          _StatusMessage(
            message: controller.error!,
            onRetry: controller.loading ? null : controller.load,
          ),
        if (controller.notice case final notice?)
          _StatusMessage(message: notice),
        if (controller.loading) const LinearProgressIndicator(),
        Expanded(
          child: controller.tasks.isEmpty
              ? const Center(
                  child: Text('Your inbox is empty', key: Key('empty-inbox')),
                )
              : ListView.builder(
                  itemCount: controller.tasks.length,
                  itemBuilder: (context, index) {
                    final task = controller.tasks[index];
                    return Card.filled(
                      child: ListTile(
                        leading: Icon(
                          Icons.circle_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(task.title),
                        subtitle: const Text('Waiting to be organized'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, this.onRetry, this.onDuplicate});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDuplicate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (onRetry != null || onDuplicate != null)
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                  if (onDuplicate != null)
                    TextButton(
                      onPressed: onDuplicate,
                      child: const Text('Submit again (may duplicate)'),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
