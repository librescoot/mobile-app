import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/widgets/state_circle.dart';

void main() {
  for (final (connected, scanning, state, scale) in [
    (true, false, ScooterState.parked, 1.5),
    (true, false, ScooterState.ready, 3.0),
    (true, false, ScooterState.standby, 1.2),
    (false, true, ScooterState.disconnected, 1.5),
    (false, false, ScooterState.disconnected, 0.0),
  ]) {
    testWidgets('upstream circle $connected/$scanning/$state uses scale $scale', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.dark,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                Center(child: StateCircle(connected: connected, scanning: scanning, scooterState: state)),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final animation = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animation.scale, scale);
      expect(animation.duration, const Duration(milliseconds: 800));
      expect(animation.curve, Curves.easeOutBack);
      final circle = find.descendant(of: find.byType(StateCircle), matching: find.byType(Container));
      final widget = tester.widget<Container>(circle);
      expect(widget.constraints!.maxWidth, 412);
      expect(widget.constraints!.maxHeight, 412);
      final decoration = widget.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      if (state.isOn) {
        expect(HSLColor.fromColor(decoration.color!).lightness, closeTo(0.18, 0.005));
      }
      if (state == ScooterState.standby) {
        expect(decoration.color, const Color(0xFF303437));
        final contrast =
            (decoration.color!.computeLuminance() + 0.05) / (const Color(0xFF101010).computeLuminance() + 0.05);
        // Deliberately subdued decorative fill, not a text/control contrast target.
        expect(contrast, closeTo(1.53, 0.02));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
