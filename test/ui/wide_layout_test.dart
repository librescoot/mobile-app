import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/theme/librescoot_theme.dart';
import 'package:unustasis/ui/wide_layout.dart';

Widget _host(Size size, Widget child) => MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  testWidgets('page content is inset only above the wide-display breakpoint', (tester) async {
    late EdgeInsets narrow;
    late EdgeInsets wide;
    await tester.pumpWidget(
      Column(
        children: [
          _host(
            const Size(400, 800),
            Builder(builder: (context) {
              narrow = wideContentPadding(context);
              return const SizedBox.shrink();
            }),
          ),
          _host(
            const Size(1200, 800),
            Builder(builder: (context) {
              wide = wideContentPadding(context);
              return const SizedBox.shrink();
            }),
          ),
        ],
      ),
    );

    expect(narrow, EdgeInsets.zero);
    expect(wide, const EdgeInsets.symmetric(horizontal: 80));
  });

  testWidgets('the base padding survives the wide inset', (tester) async {
    const base = EdgeInsets.fromLTRB(16, 0, 16, 24);
    late EdgeInsets narrow;
    late EdgeInsets wide;
    await tester.pumpWidget(
      Column(
        children: [
          _host(
            const Size(400, 800),
            Builder(builder: (context) {
              narrow = wideContentPadding(context, base: base);
              return const SizedBox.shrink();
            }),
          ),
          _host(
            const Size(1200, 800),
            Builder(builder: (context) {
              wide = wideContentPadding(context, base: base);
              return const SizedBox.shrink();
            }),
          ),
        ],
      ),
    );

    expect(narrow, base);
    expect(wide, const EdgeInsets.fromLTRB(96, 0, 96, 24));
  });

  test('dialogs and bottom sheets are capped in both themes', () {
    expect(wideDisplayBreakpoint, 600);
    for (final brightness in Brightness.values) {
      final theme = buildLibrescootTheme(brightness);
      expect(theme.dialogTheme.constraints, wideDialogConstraints);
      expect(theme.bottomSheetTheme.constraints, wideDialogConstraints);
    }
  });

  testWidgets('WideContent centres and caps its child', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WideContent(maxWidth: 600, child: Text('content')),
      ),
    );

    expect(tester.getCenter(find.byType(Text)).dx, closeTo(600, 1));
    expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(600));
  });
}
