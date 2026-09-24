import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/sheets/control_sheet.dart';
import 'package:unustasis/ui/widgets/header.dart';

class _Service extends ChangeNotifier implements ScooterService {
  @override
  final identity = ScooterIdentity();
  @override
  final vehicle = VehicleStatus();
  @override
  ScooterState? state = ScooterState.standby;
  @override
  bool connected = true;
  @override
  bool blinkerLeft = false;
  @override
  bool blinkerRight = false;
  @override
  bool? tripCounterSupported = true;
  int resets = 0;
  Object? resetError;
  bool? lastConfirm;
  @override
  Future<void> resetTripCounter() async {
    resets++;
    if (resetError != null) throw resetError!;
  }

  @override
  Future<void> blink({required bool left, required bool right}) async {
    blinkerLeft = left;
    blinkerRight = right;
    notifyListeners();
  }

  @override
  Future<void> lock(
      {bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) async {}
  @override
  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) async {}
  @override
  Future<void> wakeUp() async {}
  @override
  Future<void> hibernate() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens the sheet the way the home screen does, so the harness cannot hide a
/// layout that only fits because something else was scrolling for it.
Future<void> _pumpSheet(WidgetTester tester, _Service service, {double textScale = 1}) async {
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => const ControlSheet(),
              ),
              child: const Text('open controls'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open controls'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Pixel-sized viewport: the sheet has to fit or scroll on a real phone.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('the sheet fits or scrolls, and the reset row is reachable', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _Service();
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    expect(tester.takeException(), isNull, reason: 'no overflow at phone size');
    final reset = find.text('Reset now');
    if (reset.evaluate().isEmpty) {
      await tester.scrollUntilVisible(reset, 120, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }
    expect(reset, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the selected blinker mode when reopened', (tester) async {
    final service = _Service()..blinkerLeft = true;
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    var control = tester.widget<SegmentedButton<BlinkerMode?>>(find.byType(SegmentedButton<BlinkerMode?>).first);
    expect(control.selected, {BlinkerMode.left});

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open controls'));
    await tester.pumpAndSettle();

    control = tester.widget<SegmentedButton<BlinkerMode?>>(find.byType(SegmentedButton<BlinkerMode?>).first);
    expect(control.selected, {BlinkerMode.left});
  });

  testWidgets('the sheet still fits or scrolls with 2x text', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _Service();
    addTearDown(service.dispose);
    await _pumpSheet(tester, service, textScale: 2);

    expect(tester.takeException(), isNull, reason: 'large text must not overflow the sheet');
    final reset = find.text('Reset now');
    if (reset.evaluate().isEmpty) {
      await tester.scrollUntilVisible(reset, 120, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }
    expect(reset, findsOneWidget, reason: 'a large-text rider can still reach it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('resetting the trip is a control, behind a confirmation', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    expect(find.text('Reset now'), findsOneWidget, reason: 'the control lives with the other controls');
    expect(find.text('Ride stats'), findsOneWidget);

    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    expect(find.text('Reset trip counter?'), findsOneWidget);
    expect(service.resets, 0, reason: 'nothing happens before the rider confirms');

    await tester.tap(find.widgetWithText(FilledButton, 'Reset now'));
    await tester.pumpAndSettle();
    expect(service.resets, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reset control is labelled and actionable for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    final service = _Service();
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    final label = find.text('Reset now');
    if (label.evaluate().isEmpty) {
      await tester.scrollUntilVisible(label, 120, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }
    final button = find.ancestor(of: label, matching: find.byType(OutlinedButton)).first;
    final data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Reset now');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('cancelling the confirmation leaves the trip alone', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.resets, 0);
  });

  testWidgets('a failure is reported and the trip is still resettable later', (tester) async {
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    final toasts = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showToast') toasts.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final service = _Service()..resetError = StateError('Scooter not connected!');
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset now'));
    await tester.pumpAndSettle();
    expect(service.resets, 1);
    expect(toasts, hasLength(1));
    expect((toasts.single.arguments as Map)['msg'], 'Connect to the scooter to view the trip counter.');
    expect(find.text('Reset now'), findsOneWidget);
  });

  testWidgets('a transport timeout is reported as a timeout', (tester) async {
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    final toasts = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showToast') toasts.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final service = _Service()..resetError = const TripResetException(TripResetFailure.timeout);
    addTearDown(service.dispose);
    await _pumpSheet(tester, service);

    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset now'));
    await tester.pumpAndSettle();
    expect(toasts, hasLength(1));
    expect((toasts.single.arguments as Map)['msg'], 'The scooter did not answer in time.');
  });

  for (final supported in [false, null]) {
    testWidgets('the control is absent when the trip counter is $supported', (tester) async {
      final service = _Service()..tripCounterSupported = supported;
      addTearDown(service.dispose);
      await _pumpSheet(tester, service);

      expect(find.text('Reset now'), findsNothing);
      expect(find.byType(Header), findsWidgets, reason: 'the rest of the controls still render');
    });
  }
}
