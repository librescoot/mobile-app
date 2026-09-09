import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/ui/dialogs/seat_warning.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

Future<void> pumpButton(WidgetTester tester, Future<void> Function()? action) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: ScooterPowerButton(
          action: action,
          icon: Icons.lock_outline,
          label: 'Lock',
          instruction: 'Hold to lock',
        ),
      ),
    ),
  ));
}

Future<void> holdButton(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byType(ElevatedButton)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await gesture.up();
  await tester.pump();
}

void main() {
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
}
