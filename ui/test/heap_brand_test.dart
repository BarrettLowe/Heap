import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heap_app/heap_style.dart';

void main() {
  testWidgets('uses the decorative header mark and exposes Heap once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HeapBrand())),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(HeapBrand),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/heap-mark.png',
    );
    expect(image.fit, BoxFit.contain);
    expect(image.color, isNull);
    expect(tester.getSize(find.byWidget(image)), const Size(40, 32));

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Heap'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('wraps at narrow width with enlarged text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 320,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 160, child: HeapBrand()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Heap'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(Image)).dy,
      lessThan(tester.getTopLeft(find.text('Heap')).dy),
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Heap'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
