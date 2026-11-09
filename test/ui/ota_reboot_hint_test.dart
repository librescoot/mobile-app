import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/widgets/ota_reboot_hint.dart';

import '../../packages/scooter_flutter/test/update_controller_test.dart' as shared;
import '../support/inline_asset_bundle.dart';
import 'ls_ota_screen_test.dart' show ScreenService;

Widget host(ScreenService service, {Future<void> Function()? onLock}) =>
    ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: InlineFileTranslationLoader(
                  fallbackFile: 'en',
                  basePath: 'assets/i18n',
                  forcedLocale: const Locale('en'))
                ..assetBundle = InlineStringBundle())
        ],
        home: Scaffold(body: OtaRebootHint(onLock: onLock)),
      ),
    );

void main() {
  testWidgets('a parked scooter is asked once, and later leaves a lock tile',
      (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller)..stateValue = ScooterState.parked;
    var locks = 0;
    await tester.pumpWidget(host(service, onLock: () async => locks++));
    await tester.pumpAndSettle();

    expect(find.text('Update installed'), findsOneWidget);
    expect(find.text('To finish installing the update, the scooter has to be locked.'),
        findsOneWidget);
    // Nothing is locked unless the user confirms.
    expect(locks, 0);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update installed'), findsNothing);
    expect(locks, 0);
    expect(find.textContaining('restarts once it is locked'), findsOneWidget);

    // Rebuilding does not ask again.
    service.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Update installed'), findsNothing);

    await tester.tap(find.text('Lock now'));
    await tester.pump();
    expect(locks, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });

  testWidgets('confirming the dialog locks the scooter', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller)..stateValue = ScooterState.ready;
    var locks = 0;
    await tester.pumpWidget(host(service, onLock: () async => locks++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lock scooter and apply update now'));
    await tester.pumpAndSettle();
    expect(locks, 1);
    expect(find.text('Update installed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });

  testWidgets('a locked scooter has nothing left to do', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller)..stateValue = ScooterState.standby;
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('restarts shortly'), findsOneWidget);
    expect(find.text('Lock now'), findsNothing);
    expect(find.text('Update installed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });

  testWidgets('states that cannot be locked from the app show no button',
      (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller)..stateValue = ScooterState.hibernating;
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('restarts once it is locked'), findsOneWidget);
    expect(find.text('Lock now'), findsNothing);
    expect(find.text('Update installed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
}
