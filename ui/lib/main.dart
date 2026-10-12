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
    yield LicenseEntryWithLineBreaks([
      'Noto Serif (Google)',
      'SIL Open Font License 1.1',
    ], await rootBundle.loadString('assets/fonts/NOTO-SERIF-OFL.txt'));
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
      colorScheme: ColorScheme.fromSeed(seedColor: heapPrimary).copyWith(
        primary: heapPrimary,
        onPrimary: Colors.white,
        primaryContainer: heapHighlight,
        onPrimaryContainer: heapInk,
        secondary: heapPrimary,
        onSecondary: Colors.white,
        secondaryContainer: heapWarningSurface,
        onSecondaryContainer: heapWarningText,
        tertiary: heapPrimary,
        onTertiary: Colors.white,
        tertiaryContainer: heapHighlight,
        onTertiaryContainer: heapInk,
        surface: heapSurface,
        onSurface: heapInk,
        onSurfaceVariant: heapMuted,
        surfaceContainerLowest: heapSurface,
        surfaceContainerLow: heapSurface,
        surfaceContainer: heapSurface,
        surfaceContainerHigh: heapSurface,
        surfaceContainerHighest: heapSurface,
        surfaceTint: Colors.transparent,
        outline: heapBorder,
        outlineVariant: heapDivider,
        error: heapError,
        onError: Colors.white,
        errorContainer: heapErrorSurface,
        onErrorContainer: heapError,
      ),
      scaffoldBackgroundColor: heapCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: heapCanvas,
        foregroundColor: heapInk,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: heapSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        titleTextStyle: heapSheetHeadingStyle,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: heapSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: heapSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: heapSurface,
        selectedColor: heapHighlight,
        checkmarkColor: heapPrimary,
        labelStyle: const TextStyle(
          color: heapInk,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: heapBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: heapPrimary,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          foregroundColor: heapPrimary,
          side: const BorderSide(color: heapPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          foregroundColor: heapPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: heapSurface,
        labelStyle: const TextStyle(
          color: heapMuted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: heapMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: heapBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: heapBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: heapPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: heapError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: heapError, width: 2),
        ),
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
