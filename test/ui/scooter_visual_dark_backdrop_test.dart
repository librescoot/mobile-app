import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/widgets/scooter_visual.dart';

void main() {
  for (final size in [const Size(320, 480), const Size(412, 600), const Size(600, 240)]) {
    testWidgets('dark scooter backdrop is decorative and preserves artwork layout at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});

      Future<void> show(Brightness brightness) async {
        await tester.pumpWidget(EasyDynamicThemeWidget(
          initialThemeMode: ThemeMode.light,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: const ScooterVisual(
                    state: ScooterState.parked,
                    scanning: false,
                    blinkerLeft: false,
                    blinkerRight: false,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
      }

      await show(Brightness.light);
      final backdrop = find.byKey(const ValueKey('scooter-dark-backdrop'));
      expect(backdrop, findsNothing);
      final artwork = find.byType(AspectRatio);
      final lightBounds = tester.getRect(artwork);

      await show(Brightness.dark);
      expect(backdrop, findsOneWidget);
      expect(tester.getRect(artwork), lightBounds);
      final bounds = tester.getRect(backdrop);
      expect(bounds.width, bounds.height);
      expect(bounds.center, tester.getRect(find.byType(ScooterVisual)).center);
      expect(bounds.width, closeTo(size.shortestSide * 1.85, 0.01));
      final decoration = tester.widget<Container>(backdrop).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, isNull);
      expect(decoration.color!.computeLuminance(),
          greaterThan(ThemeData.dark().scaffoldBackgroundColor.computeLuminance()));
      final ignore = find.ancestor(of: backdrop, matching: find.byType(IgnorePointer)).first;
      expect(tester.widget<IgnorePointer>(ignore).ignoring, isTrue);
      expect(tester.takeException(), isNull);

      await show(Brightness.light);
      expect(backdrop, findsNothing);
      expect(tester.getRect(artwork), lightBounds);
    });
  }
}
