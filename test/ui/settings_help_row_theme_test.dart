import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/settings_dropdown_tile.dart';
import 'package:unustasis/ui/widgets/settings_help_row_theme.dart';

// Exercise the real scoped theme with the same overriding textColor as the app.
ThemeData rowTestTheme(Brightness brightness) {
  final theme = ThemeData(brightness: brightness);
  return theme.copyWith(listTileTheme: ListTileThemeData(textColor: theme.colorScheme.onSurface));
}

TextStyle renderedStyle(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.descendant(of: find.text(text), matching: find.byType(RichText)))
    .text
    .style!;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('scoped hierarchy, alignment and disabled semantics in $brightness', (tester) async {
      final semantics = tester.ensureSemantics();

      var toggled = false;
      final theme = rowTestTheme(brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(children: [
            const ListTile(title: Text('Outside')),
            SettingsHelpRowTheme(
              child: Column(children: [
                const ListTile(leading: Icon(Icons.help), title: Text('Help'), subtitle: Text('Description')),
                SwitchListTile(
                  secondary: const Icon(Icons.lock),
                  title: const Text('Setting'),
                  subtitle: const Text('Setting description'),
                  value: false,
                  onChanged: (value) => toggled = value,
                ),
                const SwitchListTile(
                  title: Text('Disabled'),
                  subtitle: Text('Disabled description'),
                  value: false,
                  onChanged: null,
                ),
                const ExpansionTile(leading: Icon(Icons.info), title: Text('FAQ'), children: [Text('Answer')]),
              ]),
            ),
          ]),
        ),
      ));
      for (final title in ['Help', 'Setting', 'FAQ']) {
        expect(renderedStyle(tester, title).fontSize, 18);
        expect(renderedStyle(tester, title).fontWeight, FontWeight.w400);
      }
      expect(renderedStyle(tester, 'Outside').fontSize, isNot(18));
      for (final description in ['Description', 'Setting description']) {
        expect(renderedStyle(tester, description).fontSize, 14);
        expect(renderedStyle(tester, description).color, theme.colorScheme.onSurfaceVariant);
      }
      expect(renderedStyle(tester, 'Disabled').color, theme.disabledColor);
      expect(renderedStyle(tester, 'Disabled description').color, theme.disabledColor);
      final subtitleGap = tester.getTopLeft(find.text('Description')).dy - tester.getBottomLeft(find.text('Help')).dy;
      expect(subtitleGap, inInclusiveRange(0, 6));
      expect(tester.getTopLeft(find.text('Help')).dx, tester.getTopLeft(find.text('Setting')).dx);
      expect(tester.getTopLeft(find.text('FAQ')).dx, tester.getTopLeft(find.text('Help')).dx);
      final switchRow = tester.getSemantics(find.byType(SwitchListTile).first).getSemanticsData();
      expect(switchRow.label, 'Setting\nSetting description');
      expect(switchRow.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSemantics(find.byType(Switch).first).getSemanticsData().flagsCollection.isToggled,
          isNot(Tristate.none));
      await tester.tap(find.text('Setting description'));
      expect(toggled, isTrue);
      expect(tester.getSemantics(find.byType(SwitchListTile).last).getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long rows and compact selector wrap at $width dp / $scale scale', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const title = 'A long translated title for automatic scooter hibernation';
        const description = 'A longer translated explanation of the setting that must remain readable and wrap.';
        var selected = 0;
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: SettingsHelpRowTheme(child: StatefulBuilder(builder: (context, setState) {
            return ListView(children: [
              SettingsDropdownTile<int>(
                leading: const Icon(Icons.bedtime),
                title: const Text(title),
                subtitle: const Text(description),
                value: selected,
                hint: const Text('Duration'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Never')),
                  DropdownMenuItem(value: 1, child: Text('Fourteen translated days')),
                ],
                onChanged: (value) => setState(() => selected = value!),
              ),
              SwitchListTile(
                  title: const Text(title),
                  subtitle: const Text(description),
                  secondary: const Icon(Icons.lock),
                  value: false,
                  onChanged: (_) {}),
            ]);
          }))),
        ));
        expect(tester.takeException(), isNull);
        final dropdown = find.byType(DropdownButton<int>);
        if (scale == 1) expect(tester.getSize(dropdown).width, lessThan(128));
        expect(tester.getSize(dropdown).height, greaterThanOrEqualTo(48));
        expect(DropdownButtonHideUnderline.at(tester.element(dropdown)), isTrue);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Fourteen translated days').last);
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(tester.widget<DropdownButton<int>>(dropdown).value, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final direction in TextDirection.values) {
    testWidgets('scaled fallback retains single selector semantics and disabled state in $direction', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const label = 'Fourteen translated days';
      for (final enabled in [true, false]) {
        await tester.pumpWidget(MaterialApp(
          theme: rowTestTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2), boldText: true),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(
              body: SettingsHelpRowTheme(
                  child: ListView(children: [
            SettingsDropdownTile<int>(
              leading: const Icon(Icons.bedtime),
              title: const Text('Timer title'),
              subtitle: const Text('Description'),
              value: 1,
              hint: const Text('Duration'),
              items: const [DropdownMenuItem(value: 1, child: Text(label))],
              onChanged: enabled ? (_) {} : null,
            ),
          ]))),
        ));
        await tester.pumpAndSettle();
        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.trailing, isNull);
        expect(tile.onTap, isNull);
        final button = find.byType(DropdownButton<int>);
        expect(tester.getTopLeft(button).dy, greaterThan(tester.getBottomLeft(find.text('Description')).dy));
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), enabled);
        expect(data.label, 'Timer title\nDescription\n$label');
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    });
  }
}
