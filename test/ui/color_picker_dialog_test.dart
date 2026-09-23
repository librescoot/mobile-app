import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/theme/scooter_colors.dart';
import 'package:unustasis/ui/widgets/color_picker_dialog.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    int initialValue = 0,
    String scooterName = 'Scooter Pro',
  }) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          localizationsDelegates: [
            FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
                basePath: 'assets/i18n',
                fallbackFile: 'en',
                forcedLocale: const Locale('en'),
              ),
            ),
          ],
          home: Scaffold(
            body: ColorPickerDialog(
              initialValue: initialValue,
              scooterName: scooterName,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows large finish swatches and an animated two-angle preview', (tester) async {
    await mount(tester, initialValue: 2);

    expect(find.byKey(const ValueKey('scooter-color-option-1')), findsNothing);
    for (final value in [0, 2, 3, 4, 5, 6]) {
      expect(find.byKey(ValueKey('scooter-color-option-$value')), findsOneWidget);
    }
    expect(find.text('Matte Pine'), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-noise-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-noise-6')), findsNothing);
    final title = find.text('Scooter Pro');
    expect(title, findsOneWidget);
    expect(find.ancestor(of: title, matching: find.byType(Center)), findsWidgets);
    final backdrop = find.byKey(const ValueKey('scooter-color-preview-backdrop'));
    expect(backdrop, findsOneWidget);
    final backdropSize = tester.getSize(backdrop);
    expect(find.byKey(const ValueKey('scooter-color-front-#557064-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-side-#557064-true')), findsNothing);

    final glossyFill = tester.widget<DecoratedBox>(find.byKey(const ValueKey('scooter-color-fill-6')));
    final glossyGradient = (glossyFill.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(glossyGradient.stops, [0, 0.48, 1]);
    final gloss = tester.widget<DecoratedBox>(find.byKey(const ValueKey('scooter-color-gloss-6')));
    final glossGradient = (gloss.decoration as BoxDecoration).gradient! as RadialGradient;
    expect(glossGradient.colors.first.a, closeTo(0.28, 0.001));

    await tester.tap(find.byKey(const ValueKey('scooter-color-preview')));
    await tester.pump(const Duration(milliseconds: 260));
    expect(tester.getSize(backdrop), backdropSize);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('scooter-color-side-#557064-true')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scooter-color-option-6')));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byKey(const ValueKey('scooter-color-side-#557064-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-side-#0F214F-false')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('scooter-color-side-#0F214F-false')), findsOneWidget);
  });

  testWidgets('maps legacy white to the Matte Stone swatch', (tester) async {
    expect(scooterColors[3]!.displayColor, const Color(0xFFD5D5D5));
    await mount(tester, initialValue: 1);

    final stone = find.byKey(const ValueKey('scooter-color-option-3'));
    expect(find.byKey(const ValueKey('scooter-color-front-#D5D5D5-true')), findsOneWidget);
    expect(find.descendant(of: stone, matching: find.byIcon(Icons.check)), findsOneWidget);
  });

  testWidgets('edits a custom color and finish with a live rendered preview', (tester) async {
    await mount(tester);

    await tester.tap(find.byKey(const ValueKey('scooter-color-option-custom')));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.byType(Scaffold), findsNWidgets(2));
    expect(find.byKey(const ValueKey('custom-color-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-color-backdrop')), findsOneWidget);
    expect(
      tester.widget<RenderedScooterArtwork>(find.byKey(const ValueKey('custom-color-preview'))).color,
      '#7D5FFF',
    );

    await tester.drag(find.byType(Slider).first, const Offset(-50, 0));
    await tester.pump();
    final updatedColor =
        tester.widget<RenderedScooterArtwork>(find.byKey(const ValueKey('custom-color-preview'))).color;
    expect(updatedColor, isNot('#7D5FFF'));

    await tester.tap(find.byType(Switch));
    await tester.tap(find.widgetWithText(TextButton, 'Save').last);
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('scooter-color-front-$updatedColor-false')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('scooter-color-option-custom')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps limited editions behind their alternate access paths', (tester) async {
    await mount(tester, scooterName: 'Eclipse');
    expect(find.byKey(const ValueKey('scooter-color-option-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-option-8')), findsNothing);

    await mount(tester, scooterName: 'Kori');
    expect(find.byKey(const ValueKey('scooter-color-option-8')), findsOneWidget);

    await mount(tester);
    expect(find.byKey(const ValueKey('scooter-color-option-7')), findsNothing);
    expect(find.byKey(const ValueKey('scooter-color-option-8')), findsNothing);
    for (var tap = 0; tap < 23; tap++) {
      await tester.tap(find.byKey(const ValueKey('scooter-color-preview')));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('scooter-color-option-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('scooter-color-option-8')), findsOneWidget);
  });
}
