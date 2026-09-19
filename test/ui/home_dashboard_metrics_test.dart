import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

TripCounterSnapshot _trip() => TripCounterSnapshot(
      distanceMeters: 98765,
      ridingSeconds: 45240,
      averageSpeedKph: 78,
      resetPolicy: TripResetPolicy.manual,
      lastReset: null,
      lastResetReason: TripResetReason.initial,
      generation: 1,
      status: TripCounterStatus.idle,
    );

Widget _summary({VoidCallback? onRideTap, VoidCallback? onRangeTap}) => MaterialApp(
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
        body: DashboardMetricsSummary(
          odometerMeters: 123456789,
          trip: _trip(),
          primarySOC: 96,
          secondarySOC: 87,
          dataIsOld: false,
          onRideTap: onRideTap ?? () {},
          onRangeTap: onRangeTap ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('compact dashboard displays non-zero trip, battery, and range data', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    var rideTaps = 0;
    var rangeTaps = 0;
    await tester.pumpWidget(_summary(onRideTap: () => rideTaps++, onRangeTap: () => rangeTaps++));
    await tester.pumpAndSettle();

    expect(find.text('98.8'), findsOneWidget);
    expect(find.text('123456.8'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('h'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('96'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('≈82'), findsOneWidget);
    expect(find.text('km'), findsNWidgets(3));
    expect(find.text('m'), findsOneWidget);
    expect(find.text('%'), findsNWidgets(2));
    expect(find.text('Odometer'), findsNothing);
    expect(find.text('Current trip'), findsNothing);
    expect(find.text('Estimated range'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.battery_full_rounded), findsNWidgets(2));
    // One Material Symbols glyph each for distance, duration, odometer, range.
    expect(find.byType(SvgPicture), findsNWidgets(4));

    await tester.tap(find.text('98.8'));
    await tester.tap(find.text('≈82'));
    expect(rideTaps, 1);
    expect(rangeTaps, 1);
  });

  testWidgets('an absent main battery shows a dash and does not count towards range', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
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
          body: DashboardMetricsSummary(
            odometerMeters: 123456789,
            trip: _trip(),
            primarySOC: 0,
            secondarySOC: 87,
            dataIsOld: false,
            onRideTap: () {},
            onRangeTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The empty bay reads as "no battery", not "flat battery".
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    // Range comes from the pack that is actually fitted.
    expect(find.text('≈39'), findsOneWidget);
  });

  testWidgets('each readout centres its content, with the chevron hanging off the right', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(_summary());
    await tester.pumpAndSettle();

    // Each row reserves the chevron's width on its leading edge, so the content
    // centres the same way the scooter name above it does.
    final rows = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.width == double.infinity && widget.height == 38,
    );
    expect(rows, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      final row = tester.getRect(rows.at(index));
      // Leftmost glyph (a battery is an Icon, a ride metric an SVG) up to the
      // last readout text: the chevron sits after both.
      var contentStart = double.infinity;
      for (final glyphs in [
        find.descendant(of: rows.at(index), matching: find.byType(SvgPicture)),
        find.descendant(of: rows.at(index), matching: find.byType(Icon)),
      ]) {
        if (glyphs.evaluate().isEmpty) continue;
        final left = tester.getRect(glyphs.first).left;
        if (left < contentStart) contentStart = left;
      }
      final contentEnd = tester.getRect(find.descendant(of: rows.at(index), matching: find.byType(Text)).last).right;
      expect((contentStart + contentEnd) / 2, closeTo(row.center.dx, 1.5),
          reason: 'row $index centres its content rather than the chevron');
    }
  });

  testWidgets('every glyph shares the optical centre of the digits beside it', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Wide enough that the metrics row is not scaled by its FittedBox, so
    // glyph geometry can be compared in unscaled pixels.
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(_summary());
    await tester.pumpAndSettle();

    // Digits are visually centred roughly 0.36 em above their baseline, so a
    // glyph sharing that centre is what "aligned with the text" looks like.
    double opticalCentreOf(String sample) {
      final text = tester.widget<Text>(find.text(sample));
      final painter = TextPainter(
        text: TextSpan(text: sample, style: text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline =
          tester.getTopLeft(find.text(sample)).dy + painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.dispose();
      return baseline - text.style!.fontSize! * 0.3635;
    }

    final rideCentre = opticalCentreOf('98.8');
    final batteryCentre = opticalCentreOf('96');
    final midpoint = (rideCentre + batteryCentre) / 2;

    final glyphs = [
      ...find.byIcon(Icons.battery_full_rounded).evaluate(),
      ...find.byIcon(Icons.chevron_right_rounded).evaluate(),
      ...find.byType(SvgPicture).evaluate(),
    ];
    expect(glyphs, hasLength(8));
    for (final glyph in glyphs) {
      final box = glyph.renderObject! as RenderBox;
      final centre = box.localToGlobal(box.size.center(Offset.zero)).dy;
      expect(centre, closeTo(centre < midpoint ? rideCentre : batteryCentre, 1));
    }
  });
}
