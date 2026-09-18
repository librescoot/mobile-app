import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart' show ScooterState;
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/ui/dialogs/seat_warning.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

Future<void> pumpButton(
  WidgetTester tester,
  Future<void> Function()? action, {
  bool keylessArmed = false,
  bool keylessPaused = false,
  DateTime? keylessPendingSince,
  VoidCallback? onKeylessToggle,
  double textScale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ScooterPowerButton(
            action: action,
            icon: Icons.lock_outline,
            label: 'Lock',
            instruction: 'Hold to lock',
            keylessArmed: keylessArmed,
            keylessPaused: keylessPaused,
            keylessPendingSince: keylessPendingSince,
            keylessActiveLabel: 'Auto-unlock active',
            keylessCountingLabel: 'tap to stop',
            keylessPausedLabel: 'Auto-unlock paused',
            onKeylessToggle: onKeylessToggle,
          ),
        ),
      ),
    ),
  ));
}

double fillFraction(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor ?? 0;

Future<void> holdButton(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byType(ElevatedButton)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await gesture.up();
  await tester.pump();
}

void main() {
  test('keyless only takes the button while unlocking is the action on offer', () {
    // Nothing known or no connection: unlocking is what the button does.
    expect(showsKeylessAction(null), isTrue);
    expect(showsKeylessAction(ScooterState.disconnected), isTrue);
    expect(showsKeylessAction(ScooterState.off), isTrue);
    expect(showsKeylessAction(ScooterState.hibernating), isTrue);
    expect(showsKeylessAction(ScooterState.booting), isTrue);
    // Standby is where proximity actually unlocks.
    expect(showsKeylessAction(ScooterState.standby), isTrue);
    // Already unlocked: the button offers Lock, so keyless stays out of it.
    expect(showsKeylessAction(ScooterState.parked), isFalse);
    expect(showsKeylessAction(ScooterState.ready), isFalse);
    expect(showsKeylessAction(ScooterState.waitingSeatbox), isFalse);
    expect(showsKeylessAction(ScooterState.waitingHibernation), isFalse);
  });

  testWidgets('hold hint is hidden and only short presses show its toast', (tester) async {
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    final toasts = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showToast') toasts.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    var calls = 0;
    await pumpButton(tester, () async {
      calls++;
    });
    expect(find.text('Hold to lock'), findsNothing);
    await tester.tapAt(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pump();
    expect(calls, 0);
    expect(toasts, hasLength(1));
    expect((toasts.single.arguments as Map)['msg'], 'Hold to lock');
    await holdButton(tester);
    expect(calls, 1);
    expect(toasts, hasLength(1));
    expect(find.text('Hold to lock'), findsNothing);
  });

  for (final confirm in [true, false]) {
    testWidgets('SeatWarning ${confirm ? 'confirmation' : 'cancellation'} retains pending button state',
        (tester) async {
      final action = Completer<void>();
      var commands = 0;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          )),
        ],
        home: Scaffold(
            body: Builder(
                builder: (context) => Center(
                        child: ScooterPowerButton(
                      action: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const SeatWarning(),
                        );
                        if (confirmed != true) return;
                        commands++;
                        await action.future;
                      },
                      icon: Icons.lock_outline,
                      label: 'Lock',
                      instruction: 'Hold to lock',
                    )))),
      ));
      await tester.pumpAndSettle();
      await holdButton(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(find.byType(SeatWarning), findsOneWidget);
      expect(find.byType(CircularProgressIndicator, skipOffstage: false), findsOneWidget);
      expect(commands, 0);
      await tester.tap(find.text(confirm ? 'Lock anyways' : 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(commands, confirm ? 1 : 0);
      expect(find.byType(CircularProgressIndicator), confirm ? findsOneWidget : findsNothing);
      action.complete();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  testWidgets('loading spans delayed confirmation and async action, rejecting duplicate holds', (tester) async {
    final confirmation = Completer<bool>();
    final action = Completer<void>();
    var confirmations = 0;
    var commands = 0;
    await pumpButton(tester, () async {
      confirmations++;
      if (!await confirmation.future) return;
      commands++;
      await action.future;
    });

    await holdButton(tester);
    expect(confirmations, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await holdButton(tester);
    expect(confirmations, 1);
    expect(commands, 0);

    confirmation.complete(true);
    await tester.pump();
    expect(commands, 1);
    await tester.pump(const Duration(seconds: 7));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await holdButton(tester);
    expect(commands, 1);
    action.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await holdButton(tester);
    expect(commands, 2);
  });

  testWidgets('cancelled confirmation clears loading immediately and allows retry', (tester) async {
    final confirmation = Completer<bool>();
    var calls = 0;
    await pumpButton(tester, () async {
      calls++;
      if (!await confirmation.future) return;
      fail('Cancelled confirmation must not dispatch');
    });
    await holdButton(tester);
    confirmation.complete(false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await holdButton(tester);
    expect(calls, 2);
  });

  testWidgets('action error clears loading and is reported', (tester) async {
    final action = Completer<void>();
    await pumpButton(tester, () => action.future);
    await holdButton(tester);
    action.completeError(StateError('lock failed'));
    await tester.pump();
    expect(tester.takeException(), isStateError);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('completion after disposal does not update disposed state', (tester) async {
    final action = Completer<void>();
    await pumpButton(tester, () => action.future);
    await holdButton(tester);
    await tester.pumpWidget(const SizedBox());
    action.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled button never starts loading', (tester) async {
    await pumpButton(tester, null);
    await holdButton(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an armed button swaps the lock icon for a spinner and keeps its label', (tester) async {
    var unlocks = 0;
    var toggles = 0;
    await pumpButton(
      tester,
      () async {
        unlocks++;
      },
      keylessArmed: true,
      onKeylessToggle: () => toggles++,
    );
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Auto-unlock active'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing, reason: 'the spinner replaces the icon');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(AnimatedScale)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(toggles, 1);
    expect(unlocks, 0, reason: 'a tap does not unlock');
  });

  testWidgets('a paused button keeps the lock icon and names the pause underneath', (tester) async {
    var toggles = 0;
    await pumpButton(
      tester,
      () async {},
      keylessArmed: true,
      keylessPaused: true,
      onKeylessToggle: () => toggles++,
    );
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Auto-unlock paused'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(AnimatedScale)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(toggles, 1);
  });

  testWidgets('a proximity countdown fills the button and offers the stop', (tester) async {
    var unlocks = 0;
    var toggles = 0;
    await pumpButton(
      tester,
      () async {
        unlocks++;
      },
      keylessArmed: true,
      keylessPendingSince: DateTime.now(),
      onKeylessToggle: () => toggles++,
    );
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('tap to stop'), findsOneWidget);
    expect(find.text('Auto-unlock active'), findsNothing);
    expect(fillFraction(tester), closeTo(0, 0.05), reason: 'the fill starts empty');

    await tester.pump(const Duration(milliseconds: 1500));
    expect(fillFraction(tester), closeTo(0.5, 0.1), reason: 'the fill tracks the countdown');
    expect(unlocks, 0, reason: 'the service owns the actual unlock');

    await tester.tapAt(tester.getCenter(find.byType(AnimatedScale)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(toggles, 1, reason: 'tapping stops the countdown');
    expect(unlocks, 0);
  });

  testWidgets('a countdown that is already running resumes part-filled', (tester) async {
    await pumpButton(
      tester,
      () async {},
      keylessArmed: true,
      keylessPendingSince: DateTime.now().subtract(const Duration(seconds: 2)),
      onKeylessToggle: () {},
    );
    await tester.pump();
    expect(fillFraction(tester), closeTo(0, 0.05), reason: 'a late button starts near the end');
    await tester.pump(const Duration(milliseconds: 500));
    expect(fillFraction(tester), greaterThan(0.5));
  });

  testWidgets('a subline ellipsises at 2x text instead of widening the button', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpButton(
      tester,
      () async {},
      keylessArmed: true,
      keylessPaused: true,
      onKeylessToggle: () {},
      textScale: 2,
    );
    expect(find.text('Auto-unlock paused'), findsOneWidget);
    expect(tester.getSize(find.byType(ScooterPowerButton)).width, 136,
        reason: 'the subline must not stretch the button column');
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding still unlocks by hand while keyless is paused', (tester) async {
    var unlocks = 0;
    var toggles = 0;
    await pumpButton(
      tester,
      () async {
        unlocks++;
      },
      keylessArmed: true,
      keylessPaused: true,
      onKeylessToggle: () => toggles++,
    );

    await holdButton(tester);
    expect(unlocks, 1, reason: 'hold still unlocks while paused');
    expect(toggles, 0);
  });

  testWidgets('keyless stays controllable while the unlock action is unavailable', (tester) async {
    var toggles = 0;
    await pumpButton(tester, null, keylessArmed: true, onKeylessToggle: () => toggles++);

    await tester.tapAt(tester.getCenter(find.byType(AnimatedScale)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(toggles, 1, reason: 'a disconnected scooter is still keyless-armed');
  });
}
