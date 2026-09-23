import 'dart:math';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';
import 'package:unustasis/ui/widgets/scooter_visual.dart';

class _NonEclipseRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => max == 3 ? 1 : 0;
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    ScooterState state = ScooterState.parked,
    List<int> thresholds = const [42],
    int color = 1,
    String? customColor,
    bool customColorMatte = true,
    ValueChanged<int?>? onSurpriseChanged,
    Random? random,
  }) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.dark,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: ScooterVisual(
                state: state,
                scanning: false,
                blinkerLeft: false,
                blinkerRight: false,
                color: color,
                customColor: customColor,
                customColorMatte: customColorMatte,
                random: random ?? Random(7),
                surpriseThresholds: thresholds,
                surpriseDuration: const Duration(seconds: 2),
                onSurpriseChanged: onSurpriseChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('uses the three hidden production thresholds', () {
    const visual = ScooterVisual(
      state: ScooterState.parked,
      scanning: false,
      blinkerLeft: false,
      blinkerRight: false,
    );

    expect(visual.surpriseThresholds, [42, 69, 83]);
  });

  testWidgets('uses rendered artwork for a custom finish', (tester) async {
    await mount(
      tester,
      customColor: '#123456',
      customColorMatte: false,
    );

    final artwork = tester.widget<RenderedScooterArtwork>(find.byType(RenderedScooterArtwork));
    expect(artwork.color, '#123456');
    expect(artwork.matte, isFalse);
    expect(find.byKey(const ValueKey('eclipse-backdrop')), findsNothing);
  });

  testWidgets('Eclipse colour uses the ring backdrop without hidden taps', (tester) async {
    await mount(tester, color: 7);

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('eclipse-backdrop')));
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.gradient, isA<RadialGradient>());
  });

  testWidgets('keeps early taps quiet, then shakes and temporarily swaps the skin', (tester) async {
    final surpriseChanges = <int?>[];
    await mount(
      tester,
      onSurpriseChanged: surpriseChanges.add,
      random: _NonEclipseRandom(),
    );
    final artwork = find.descendant(
      of: find.byType(ScooterVisual),
      matching: find.byType(GestureDetector),
    );

    for (var tap = 0; tap < 22; tap++) {
      await tester.tap(artwork);
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('scooter-skin-#D5D5D5-true')), findsOneWidget);
    var shake = tester.widget<Transform>(find.byKey(const ValueKey('scooter-artwork-shake')));
    expect(shake.transform.storage[12], 0);

    await tester.tap(artwork);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    shake = tester.widget<Transform>(find.byKey(const ValueKey('scooter-artwork-shake')));
    expect(shake.transform.storage[12], isNot(0));

    for (var tap = 23; tap < 42; tap++) {
      await tester.tap(artwork);
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scooter-skin-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-skin-#D5D5D5-true')), findsNothing);
    expect(find.byKey(const ValueKey('eclipse-backdrop')), findsNothing);
    expect(surpriseChanges, [8]);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scooter-skin-#D5D5D5-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('eclipse-backdrop')), findsNothing);
    expect(surpriseChanges, [8, null]);
  });

  testWidgets('ignores hidden taps while disconnected', (tester) async {
    await mount(tester, state: ScooterState.disconnected, thresholds: const [1]);
    final artwork = find.descendant(
      of: find.byType(ScooterVisual),
      matching: find.byType(GestureDetector),
    );

    await tester.tap(artwork);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scooter-skin-#D5D5D5-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-skin-7')), findsNothing);
    expect(find.byKey(const ValueKey('scooter-skin-8')), findsNothing);
    expect(find.byKey(const ValueKey('scooter-skin-9')), findsNothing);
  });
}
