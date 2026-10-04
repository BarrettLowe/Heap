import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'heap_api.dart';
import 'heap_style.dart';
import 'inbox_controller.dart';
import 'task_lists_page.dart';

export 'inbox_page.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Heap project icons (Material Design Icons)',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Heap project icons (Apache License 2.0)',
    ], await rootBundle.loadString('assets/fonts/APACHE-2.0.txt'));
  });
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Heap',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: heapGreen).copyWith(
        primary: heapGreen,
        onPrimary: Colors.white,
        surface: heapCanvas,
        onSurface: heapInk,
      ),
      scaffoldBackgroundColor: heapCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: heapCanvas,
        foregroundColor: heapInk,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: widget.configurationError || widget.api == null
        ? const _ConfigurationPage()
        : TaskListsPage(
            inbox: _controller!,
            organization: widget.api!,
            projects: widget.api!,
          ),
  );
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
          'Set a valid server origin with --dart-define=HEAP_API_BASE_URL=https://your-server.example',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
