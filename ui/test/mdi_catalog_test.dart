import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/mdi_catalog.dart';
import 'package:heap_app/project_widgets.dart';

void main() {
  test('entire MDI 7.4.47 release has exact const glyph lookup', () {
    final source = File('tool/mdi-7.4.47.scss').readAsStringSync();
    final matches = RegExp(r'"([a-z0-9-]+)": ([0-9A-F]+)').allMatches(source);
    expect(matches.length, 7447);
    expect(mdiIcons.length, matches.length);
    expect(
      mdiIcons.keys.toList(),
      orderedEquals(matches.map((m) => m[1]!).toList()..sort()),
    );
    for (final m in matches) {
      final glyph = projectGlyph(m[1]);
      expect(glyph, mdiIcons[m[1]]);
      expect(glyph.codePoint, int.parse(m[2]!, radix: 16));
      expect(glyph.fontFamily, 'HeapProjectIcons');
    }
    expect(projectGlyph(null), mdiIcons['folder-outline']);
    expect(projectGlyph('not-an-icon'), mdiIcons['folder-outline']);
  });

  test('search ignores case, spaces and hyphens; every word must match', () {
    expect(searchMdiIcons(''), mdiIcons.keys.toList());
    expect(searchMdiIcons('  '), mdiIcons.keys.toList());
    expect(searchMdiIcons('HOME Outline'), contains('home-outline'));
    expect(searchMdiIcons('outline-home'), searchMdiIcons('HOME outline'));
    expect(searchMdiIcons('home   outline'), searchMdiIcons('home-outline'));
    expect(searchMdiIcons('zebra impossible-word'), isEmpty);
    expect(mdiLabel('airplane-takeoff'), 'Airplane takeoff');
  });
  test(
    'bundled full font cmap contains every catalog glyph, not missing glyphs',
    () {
      final font = ByteData.sublistView(
        File('assets/fonts/heap-project-icons.ttf').readAsBytesSync(),
      );
      var cmap = 0;
      for (var i = 0; i < font.getUint16(4); i++) {
        final table = 12 + i * 16; // SFNT header and table record sizes.
        if (font.getUint32(table) == 0x636d6170) {
          // cmap table tag.
          cmap = font.getUint32(table + 8);
        }
      }
      expect(cmap, isNonZero);
      var format12 = 0;
      for (var i = 0; i < font.getUint16(cmap + 2); i++) {
        final offset = cmap + font.getUint32(cmap + 4 + i * 8 + 4);
        if (font.getUint16(offset) == 12) format12 = offset;
      }
      expect(format12, isNonZero);
      final glyphs = <int, int>{};
      for (var i = 0; i < font.getUint32(format12 + 12); i++) {
        final group = format12 + 16 + i * 12;
        final first = font.getUint32(group);
        final last = font.getUint32(group + 4);
        final glyph = font.getUint32(group + 8);
        for (var code = first; code <= last; code++) {
          glyphs[code] = glyph + code - first;
        }
      }
      for (final icon in mdiIcons.values) {
        expect(glyphs[icon.codePoint], isNotNull);
        expect(glyphs[icon.codePoint], isNonZero);
      }
    },
  );

  testWidgets('font rasterizes distinct actual glyphs beyond old subset', (
    t,
  ) async {
    await t.runAsync(() async {
      final loader = FontLoader('HeapProjectIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/heap-project-icons.ttf').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    });
    final samples = [
      mdiIcons['airplane-takeoff']!,
      mdiIcons['abacus']!,
      mdiIcons['zodiac-virgo']!,
      const IconData(0x10ffff, fontFamily: 'HeapProjectIcons'),
    ]; // Unassigned glyph for comparison.
    final keys = List.generate(samples.length, (_) => GlobalKey());
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < samples.length; i++)
                RepaintBoundary(
                  key: keys[i],
                  child: SizedBox.square(
                    dimension: 64,
                    child: Icon(samples[i], size: 28),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final pixels = <Uint8List>[];
    await t.runAsync(() async {
      for (final key in keys) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        pixels.add(data!.buffer.asUint8List());
        image.dispose();
      }
    });
    for (var i = 0; i < samples.length - 1; i++) {
      expect(listEquals(pixels[i], pixels.last), false);
      expect(
        listEquals(pixels[i], pixels[(i + 1) % (samples.length - 1)]),
        false,
      );
    }
  });
}
