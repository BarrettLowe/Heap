import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/mdi_catalog.dart';
import 'package:heap_app/heap_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heap_app/project.dart';
import 'package:heap_app/project_widgets.dart';

import 'project_fakes.dart';
import 'project_widget_test.dart' show host, edit;

Future<void> browse(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('project-icon')));
  await t.tap(find.byKey(const Key('project-icon')));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Browse all…'));
  await t.tap(find.text('Browse all…'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Browse preserves draft; non-common choice only writes on Save and reopens',
    (t) async {
      final service = FakeProjects();
      final requests = <http.Request>[];
      final api = HeapApi(
        baseUri: Uri.parse('http://heap.local'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              ...projectJson(),
              ...jsonDecode(request.body) as Map<String, dynamic>,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      service.onSave = (draft, original) =>
          api.saveProject(draft, original: original);
      await host(t, service);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Draft name');
      await browse(t);
      expect(service.writes, 0);
      expect(requests, isEmpty);
      expect(
        t
            .widget<ProjectPicker>(
              find.byKey(const Key('project-icon'), skipOffstage: false),
            )
            .value,
        'leaf',
      );
      await t.enterText(
        find.byKey(const Key('icon-search')),
        'airplane takeoff',
      );
      await t.pumpAndSettle();
      expect(find.byIcon(mdiIcons['airplane-takeoff']!), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mdi-airplane-takeoff')));
      await t.pumpAndSettle();
      expect(find.text('Choose icon'), findsNothing);
      expect(find.text('Airplane takeoff'), findsOneWidget);
      expect(find.text('Draft name'), findsOneWidget);
      expect(service.writes, 0);
      expect(
        t
            .widget<ProjectPicker>(find.byKey(const Key('project-icon')))
            .focusNode
            .hasFocus,
        true,
      );
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.lastDraft!.icon, 'airplane-takeoff');
      expect(requests.single.method, 'PUT');
      expect(jsonDecode(requests.single.body)['icon'], 'airplane-takeoff');
      await edit(t);
      expect(find.byIcon(mdiIcons['airplane-takeoff']!), findsOneWidget);
      expect(find.text('Airplane takeoff'), findsOneWidget);
      await t.tap(find.byKey(const Key('project-icon')));
      await t.pumpAndSettle();
      expect(find.text('Airplane takeoff'), findsNWidgets(2));
    },
  );

  for (final cancel in ['Cancel', 'Back', 'Escape', 'system Back']) {
    testWidgets('$cancel preserves all drafts and restores Icon focus', (
      t,
    ) async {
      final service = FakeProjects();
      await host(t, service);
      await edit(t);
      await t.enterText(find.byKey(const Key('project-name')), 'Kept name');
      await browse(t);
      await t.enterText(find.byKey(const Key('icon-search')), 'home');
      if (cancel == 'Escape') {
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
      } else if (cancel == 'system Back') {
        await t.binding.handlePopRoute();
      } else if (cancel == 'Back') {
        await t.tap(find.byTooltip('Back'));
      } else {
        await t.tap(find.text('Cancel'));
      }
      await t.pumpAndSettle();
      expect(find.text('Choose icon'), findsNothing);
      expect(find.text('Kept name'), findsOneWidget);
      expect(
        t.widget<ProjectColorPalette>(find.byType(ProjectColorPalette)).value,
        '#779252',
      );
      final picker = t.widget<ProjectPicker>(
        find.byKey(const Key('project-icon')),
      );
      expect(picker.value, 'leaf');
      expect(picker.focusNode.hasFocus, true);
      expect(service.writes, 0);
    });
  }

  testWidgets('no matches, Clear, selected semantics and keyboard selection', (
    t,
  ) async {
    final semantics = t.ensureSemantics();

    final service = FakeProjects();
    await host(t, service);
    await edit(t);
    await browse(t);
    final search = t.widget<EditableText>(find.byType(EditableText).last);
    expect(search.focusNode.hasFocus, true);
    expect(search.keyboardType, TextInputType.text);
    expect(t.testTextInput.hasAnyClients, true);
    await t.enterText(
      find.byKey(const Key('icon-search')),
      'zzzzzz impossible',
    );
    await t.pumpAndSettle();
    expect(find.text('No icons match your search.'), findsOneWidget);
    await t.tap(find.byTooltip('Clear'));
    await t.pumpAndSettle();
    expect(find.text('Ab testing'), findsOneWidget);
    await t.enterText(find.byKey(const Key('icon-search')), 'leaf');
    await t.pumpAndSettle();
    expect(
      t
          .getSemantics(find.byKey(const ValueKey('mdi-leaf')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text('Choose icon'), findsNothing);
    expect(service.writes, 0);
    semantics.dispose();
  });

  testWidgets(
    'unknown remains original with folder fallback; None clears deliberately',
    (t) async {
      final service = FakeProjects()
        ..items = [
          Project.fromJson({...projectJson(), 'icon': 'unknown-icon'}),
        ];
      await host(t, service);
      await edit(t);
      await browse(t);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Saved icon: unknown-icon'), findsOneWidget);
      expect(find.byIcon(mdiIcons['folder-outline']!), findsOneWidget);
      await t.tap(find.byKey(const Key('project-save')));
      await t.pumpAndSettle();
      expect(service.lastDraft!.icon, 'unknown-icon');
      await edit(t);
      await t.tap(find.byKey(const Key('project-icon')));
      await t.pumpAndSettle();
      await t.tap(find.text('None').last);
      await t.pumpAndSettle();
      expect(
        t.widget<ProjectPicker>(find.byKey(const Key('project-icon'))).value,
        isNull,
      );
    },
  );

  for (final layout in [(320.0, 2.0), (1200.0, 1.0)]) {
    testWidgets('catalog wraps without clipping at $layout', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      t.view.physicalSize = Size(layout.$1, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = FakeProjects();
      await host(t, service, scale: layout.$2);
      await t.ensureVisible(find.byType(ProjectRow));
      await edit(t);
      await browse(t);
      expect(
        t.getSize(find.byKey(const Key('icon-modal'))).width,
        layout.$1 == 320 ? 320 : 640,
      );
      await t.enterText(
        find.byKey(const Key('icon-search')),
        'account arrow left outline',
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final grid = t.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, layout.$1 == 320 ? 1 : greaterThan(1));
      final tile = find.byKey(const ValueKey('mdi-account-arrow-left-outline'));
      expect(t.getSize(tile).height, greaterThanOrEqualTo(48));
      await t.tap(tile);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'wide modal contains Tab focus, outlines tile focus and arrows reach lazy rows',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      t.view.physicalSize = const Size(1200, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = FakeProjects();
      await host(t, service);
      await edit(t);
      await browse(t);
      await t.enterText(
        find.byKey(const Key('icon-search')),
        'airplane takeoff',
      );
      await t.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        // Cycle past the modal's small filtered set.
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        var contained = false;
        FocusManager.instance.primaryFocus!.context!.visitAncestorElements((
          element,
        ) {
          if (element.widget.key == const Key('icon-modal')) contained = true;
          return !contained;
        });
        expect(contained, true);
      }
      await t.tap(find.byTooltip('Clear'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      final tile = find.byKey(const ValueKey('mdi-ab-testing'));
      final material = t.widget<Material>(
        find.descendant(of: tile, matching: find.byType(Material)),
      );
      expect((material.shape! as RoundedRectangleBorder).side.width, 2);
      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      expect(
        t.widget<GridView>(find.byType(GridView)).controller!.offset,
        greaterThan(0),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Choose icon'), findsNothing);
      expect(service.writes, 0);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('arrow selection works immediately after leaving no matches', (
    t,
  ) async {
    await host(t, FakeProjects());
    await edit(t);
    await browse(t);
    t.testTextInput.enterText('zzzz impossible');
    await t.pumpAndSettle();
    expect(find.text('No icons match your search.'), findsOneWidget);
    t.testTextInput.enterText('abacus');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Choose icon'), findsNothing);
    expect(find.text('Abacus'), findsOneWidget);
  });

  testWidgets('Android search opens and reopens keyboard; Enter chooses', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await host(t, FakeProjects());
    await edit(t);
    await browse(t);
    expect(
      t.getSize(find.byKey(const Key('icon-modal'))).width,
      t.view.physicalSize.width / t.view.devicePixelRatio,
    );
    final search = t.widget<EditableText>(find.byType(EditableText).last);
    expect(search.keyboardType, TextInputType.text);
    expect(t.testTextInput.hasAnyClients, true);
    expect(t.testTextInput.isVisible, true);
    t.testTextInput.enterText('airplane takeoff');
    await t.pumpAndSettle();
    t.testTextInput.hide();
    await t.pump();
    expect(t.testTextInput.isVisible, false);
    await t.tap(find.byKey(const Key('icon-search')));
    await t.pumpAndSettle();
    expect(
      t.widget<EditableText>(find.byType(EditableText).last).keyboardType,
      TextInputType.text,
    );
    expect(t.testTextInput.isVisible, true);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Airplane takeoff'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
