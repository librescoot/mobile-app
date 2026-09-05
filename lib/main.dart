import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/util/legacy_to_async_migration_util.dart';

import '../background/bg_service.dart';
import '../domain/log_helper.dart';
import '../flutter/blue_plus_mockable.dart';
import '../home_screen.dart';
import '../scooter_service.dart';
import '../service/sharing_handler.dart';
import '../theme/librescoot_theme.dart';
import '../background/widget_handler.dart';

void main() async {
  LogHelper().initialize();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await HomeWidget.setAppGroupId("group.com.librescoot.app");

  Locale? savedLocale;

  await migrateSharedPrefs();

  final String? localeString = await SharedPreferencesAsync().getString('savedLocale');
  if (localeString != null) {
    Logger("Main").fine("Saved locale: $localeString");
    final parts = localeString.split('_');
    savedLocale = parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  } else {
    final parts = Platform.localeName.split('_');
    final lang = parts[0];
    final country = parts.length > 1 ? parts[1] : null;
    // Map device locale to a supported variant (e.g. en_GB -> en_GB),
    // otherwise fall back to just the language code.
    const supportedVariants = {'en_GB'};
    if (country != null && supportedVariants.contains('${lang}_$country')) {
      savedLocale = Locale(lang, country);
    } else {
      savedLocale = Locale(lang);
    }
  }

  // here goes nothing...
  setupBackgroundService();
  setupWidget();

  runApp(ChangeNotifierProvider(
      create: (context) => ScooterService(FlutterBluePlusMockable()),
      child: EasyDynamicThemeWidget(
        child: MyApp(
          savedLocale: savedLocale,
        ),
      )));
}

Future<void> migrateSharedPrefs() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary(
    legacySharedPreferencesInstance: prefs,
    sharedPreferencesAsyncOptions: SharedPreferencesOptions(),
    migrationCompletedKey: 'migrationCompleted',
  );
}

class MyApp extends StatefulWidget {
  final Locale? savedLocale;
  const MyApp({this.savedLocale, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _MyAppState extends State<MyApp> {
  SharingHandler? _sharingHandler;
  ScooterService? _scooterService;
  late final FlutterI18nDelegate _localizationsDelegate;

  @override
  void initState() {
    super.initState();
    _localizationsDelegate = FlutterI18nDelegate(
      translationLoader: FileTranslationLoader(
        fallbackFile: 'en',
        basePath: 'assets/i18n',
        forcedLocale: widget.savedLocale,
      ),
      missingTranslationHandler: (key, locale) {
        Logger("Main").warning(
          "--- Missing Key: $key, languageCode: ${locale?.languageCode}",
        );
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sharingHandler == null) {
      // Bind to the Provider's ScooterService, not the background service's
      // global. Touching that global from the foreground isolate constructs a
      // second ScooterService here (top-level fields are lazily initialized
      // per isolate), with its own location, RSSI and refresh timers, and it
      // then reports state the UI never drives.
      final service = Provider.of<ScooterService>(context, listen: false);
      _scooterService = service;
      _sharingHandler = SharingHandler(
        navigatorKey: navigatorKey,
        service: service,
      );
      _sharingHandler!.init();
      service.addListener(_pushStateToWidget);
    }
  }

  void _pushStateToWidget() {
    final service = _scooterService;
    if (service == null) return;
    passToWidget(
      connected: service.connected,
      lastPing: service.identity.lastPing,
      scooterState: service.state,
      primarySOC: service.battery.primarySOC,
      secondarySOC: service.battery.secondarySOC,
      scooterName: service.identity.name,
      scooterColor: service.identity.color,
      lastLocation: service.identity.lastLocation,
      seatClosed: service.vehicle.seatClosed,
      scooterLocked: service.vehicle.handlebarsLocked,
      scooterId: service.myScooter?.remoteId.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Librescoot App for unu',
      theme: buildLibrescootTheme(Brightness.light),
      darkTheme: buildLibrescootTheme(Brightness.dark),
      themeMode: EasyDynamicTheme.of(context).themeMode,
      localizationsDelegates: [_localizationsDelegate],
      home: const HomeScreen(),
    );
  }

  @override
  void dispose() {
    _scooterService?.removeListener(_pushStateToWidget);
    _sharingHandler?.dispose();
    super.dispose();
  }
}
