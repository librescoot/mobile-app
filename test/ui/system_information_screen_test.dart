import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/system_information_screen.dart';
import 'package:unustasis/ui/screens/ls_ota_screen.dart';

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  String? currentScooterId = 'A';
  @override
  String? connectingScooterId;
  int reads = 0;
  Future<Map<String, String?>> Function() load = () async => {
        'mdb': 'v1.2.3',
        'dbc': 'v1.2.2',
        'nrf': 'v2.8.0-ls',
      };
  @override
  Future<Map<String, String?>> readInstalledVersions() {
    reads++;
    return load();
  }

  void changed() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service use: ${invocation.memberName}');
}

class _Navigation extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

Future<void> _mount(WidgetTester tester, _Service service,
    {Locale locale = const Locale('en'), NavigatorObserver? observer}) async {
  PackageInfo.setMockInitialValues(
      appName: 'Librescoot',
      packageName: 'org.librescoot.mobile.unu.debug',
      version: '2.0.5',
      buildNumber: '46',
      buildSignature: '');
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: MaterialApp(
      key: ValueKey(locale),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('de')],
      navigatorObservers: [if (observer != null) observer],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n',
          fallbackFile: 'en',
          forcedLocale: locale,
        ))
      ],
      home: const SystemInformationScreen(),
    ),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  test('System information follows all scooter service options before app settings', () {
    final source = File('lib/ui/screens/settings_screen.dart').readAsStringSync();
    final serviceItems = source.indexOf('_librescootUpdateSettingsItems(');
    final information = source.indexOf("title: Text(FlutterI18n.translate(context, 'system_info_title'))");
    final appSection = source.indexOf('Header(FlutterI18n.translate(context, "stats_settings_section_app"))');
    expect(serviceItems, greaterThanOrEqualTo(0));
    expect(information, greaterThan(serviceItems));
    expect(appSection, greaterThan(information));
  });
  testWidgets('shows only board versions without invoking update or action owners', (tester) async {
    final service = _Service();
    await _mount(tester, service);
    expect(find.text('2.0.5 (46)'), findsNothing);
    expect(find.text('vehicle-service'), findsNothing);
    expect(find.text('bluetooth-service'), findsNothing);
    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.text('v2.8.0-ls'), findsOneWidget);
    expect(service.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows reload wording and a connected Bluetooth update entry without planning', (tester) async {
    final service = _Service();
    await _mount(tester, service);
    expect(find.text('Reload version info'), findsOneWidget);
    final updates = find.widgetWithText(ListTile, 'Bluetooth firmware updates');
    await tester.scrollUntilVisible(updates, 250, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<ListTile>(updates).onTap, isNotNull);
    expect(service.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bluetooth update entry navigates to the existing updater', (tester) async {
    final navigation = _Navigation();
    final service = _Service();
    await _mount(tester, service, observer: navigation);
    final updates = find.text('Bluetooth firmware updates');
    await tester.scrollUntilVisible(updates, 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(updates);
    final route = navigation.pushed.last as MaterialPageRoute<dynamic>;
    expect(route.builder(tester.element(find.byType(SystemInformationScreen))), isA<LsOtaScreen>());
    expect(service.reads, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('German reload wording distinguishes version numbers from updates', (tester) async {
    await _mount(tester, _Service(), locale: const Locale('de'));
    expect(find.text('Versionsnummern aktualisieren'), findsOneWidget);
    final updates = find.text('Firmware-Updates über Bluetooth');
    await tester.scrollUntilVisible(updates, 250, scrollable: find.byType(Scrollable).first);
    expect(updates, findsOneWidget);
  });

  testWidgets('offline opening does not query or invent installed versions', (tester) async {
    final service = _Service()..connected = false;
    await _mount(tester, service);
    expect(service.reads, 0);
    final updates = find.widgetWithText(ListTile, 'Bluetooth firmware updates');
    await tester.scrollUntilVisible(updates, 250, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<ListTile>(updates).onTap, isNull);
    expect(tester.widget<ListTile>(updates).enabled, isFalse);
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('2.0.5 (46)'), findsNothing);
    expect(find.text('vehicle-service'), findsNothing);
    expect(find.text('bluetooth-service'), findsNothing);
  });

  testWidgets('labels cached readings on disconnect and hides them for another scooter', (tester) async {
    final service = _Service();
    await _mount(tester, service);
    service.connected = false;
    service.currentScooterId = null;
    service.changed();
    await tester.pump();
    expect(find.text('v2.8.0-ls'), findsOneWidget);
    expect(find.text('Cached readings — disconnected'), findsOneWidget);
    service.connectingScooterId = 'B';
    service.changed();
    await tester.pump();
    expect(find.text('v2.8.0-ls'), findsNothing);
    expect(service.reads, 1);
  });

  testWidgets('late snapshot for another scooter is discarded', (tester) async {
    final pending = Completer<Map<String, String?>>();
    final service = _Service()..load = () => pending.future;
    await _mount(tester, service);
    service.currentScooterId = 'B';
    service.changed();
    pending.complete({'mdb': 'old-scooter'});
    await tester.pump();
    expect(find.text('old-scooter'), findsNothing);
    expect(service.reads, 1);
  });

  testWidgets('unknown or unsupported versions are unavailable', (tester) async {
    final service = _Service()..load = () async => {'mdb': 'unknown', 'dbc': ' ', 'nrf': null};
    await _mount(tester, service);
    expect(find.text('unknown'), findsNothing);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('copy diagnostics contains versions but no scooter identifier', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _mount(tester, _Service()..currentScooterId = 'private-device-id');
    await tester.scrollUntilVisible(find.text('Copy diagnostics'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Copy diagnostics'));
    await tester.pump();
    expect(copied, contains('v2.8.0-ls'));
    expect(copied, isNot(contains('vehicle-service')));
    expect(copied, isNot(contains('bluetooth-service')));
    expect(copied, contains('2.0.5 (46)'));
    expect(copied, isNot(contains('private-device-id')));
  });

  testWidgets('disposal during a read does not update a dead screen', (tester) async {
    final pending = Completer<Map<String, String?>>();
    await _mount(tester, _Service()..load = () => pending.future);
    await tester.pumpWidget(const SizedBox());
    pending.complete({'mdb': 'v1'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
