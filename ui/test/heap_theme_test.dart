import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_style.dart';
import 'package:heap_app/main.dart';
import 'package:heap_app/heap_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Paper desk theme reaches the running app', (tester) async {
    await tester.pumpWidget(const HeapApp(configurationError: true));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = app.theme!;
    expect(theme.colorScheme.primary, heapPrimary);
    expect(theme.colorScheme.onPrimary, Colors.white);
    expect(theme.scaffoldBackgroundColor, heapCanvas);
    expect(theme.colorScheme.surface, heapSurface);
    expect(theme.colorScheme.surfaceContainer, heapSurface);
    expect(theme.colorScheme.onSurface, heapInk);
    expect(theme.colorScheme.onSurfaceVariant, heapMuted);
    expect(theme.colorScheme.outline, heapBorder);
    expect(theme.colorScheme.outlineVariant, heapDivider);
    expect(theme.colorScheme.error, heapError);
    expect(theme.colorScheme.errorContainer, heapErrorSurface);
    expect(theme.inputDecorationTheme.fillColor, heapSurface);
    expect(
      theme.inputDecorationTheme.focusedBorder?.borderSide.color,
      heapPrimary,
    );
    expect(theme.chipTheme.selectedColor, heapHighlight);
    expect(theme.chipTheme.checkmarkColor, heapPrimary);
    expect(theme.dialogTheme.titleTextStyle?.fontFamily, 'HeapSerif');
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('HeapSerif'));
    expect(find.text('Heap'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Heap')).style?.fontFamily,
      isNot('HeapSerif'),
    );
  });

  testWidgets('Paper desk headings use HeapSerif in the running app', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'items': []}), 200);
    });
    await tester.pumpWidget(
      HeapApp(
        api: HeapApi(client: client, baseUri: Uri.parse('http://test')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('inbox-heading')))
          .style
          ?.fontFamily,
      'HeapSerif',
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byType(HeapBrand),
              matching: find.text('Heap'),
            ),
          )
          .style
          ?.fontFamily,
      isNot('HeapSerif'),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'priority and completion pills keep Paper desk colors and labels',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PriorityPill(priority: 1),
                PriorityPill(priority: 2),
                PriorityPill(priority: 3),
                PriorityPill(priority: 4),
                PriorityPill(priority: 5),
                PriorityPill(priority: null),
                PriorityPill(priority: 3, neutral: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('P1 Critical'), findsOneWidget);
      expect(find.text('P2 Important'), findsOneWidget);
      expect(find.text('P3 Normal'), findsNWidgets(2));
      expect(find.text('P4 Someday'), findsOneWidget);
      expect(find.text('P5 Maybe'), findsOneWidget);
      expect(find.text('Unset'), findsOneWidget);
      final pills = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decorations = pills.map(
        (pill) => pill.decoration! as BoxDecoration,
      );
      expect(decorations.map((decoration) => decoration.color), [
        priorityColors[1]!.$1,
        priorityColors[2]!.$1,
        priorityColors[3]!.$1,
        priorityColors[4]!.$1,
        priorityColors[5]!.$1,
        unsetColors.$1,
        heapCompletionNeutral,
      ]);
      expect(decorations.first.borderRadius, BorderRadius.circular(14));
      final text = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(text[0].style?.color, priorityColors[1]!.$2);
      expect(text[1].style?.color, priorityColors[2]!.$2);
      expect(text[2].style?.color, priorityColors[3]!.$2);
      expect(text[3].style?.color, priorityColors[4]!.$2);
      expect(text.last.style?.color, heapCompletionText);
    },
  );

  testWidgets('bundled serif font and license are available as app assets', (
    tester,
  ) async {
    final font = await rootBundle.load('assets/fonts/heap-serif-bold.ttf');
    final license = await rootBundle.loadString(
      'assets/fonts/NOTO-SERIF-OFL.txt',
    );
    expect(font.lengthInBytes, greaterThan(100000));
    expect(license, contains('Copyright'));
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });

  testWidgets('Paper desk app has no overflow at 320 logical pixels and 2x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1200);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'items': []}), 200);
    });
    await tester.pumpWidget(
      HeapApp(
        api: HeapApi(client: client, baseUri: Uri.parse('http://test')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('inbox-heading'))),
      ).scale(10),
      20,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('on-heap-tab')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('on-heap-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heap-heading')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('heap-heading')))
          .style
          ?.fontFamily,
      'HeapSerif',
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('projects-toolbar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('projects-toolbar')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
