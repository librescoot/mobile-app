import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../background/bg_service.dart';
import '../domain/log_helper.dart';
import '../flutter/blue_plus_mockable.dart';
import '../home_screen.dart';
import '../scooter_service.dart';
import 'background/bg_service.dart';

void main() async {
  LogHelper().initialize();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  Locale? savedLocale;

  SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? localeString = prefs.getString('savedLocale');
  if (localeString != null) {
    Logger("Main").fine("Saved locale: $localeString");
    savedLocale = Locale(localeString);
  } else {
    // we have no language saved, so we pass along the device language
    savedLocale = Locale(Platform.localeName.split('_').first);
  }

  // here goes nothing...
  if (Platform.isAndroid) {
    setupBackgroundService();
  }

  runApp(ChangeNotifierProvider(
      create: (context) => ScooterService(FlutterBluePlusMockable()),
      child: EasyDynamicThemeWidget(
        child: MyApp(
          savedLocale: savedLocale,
        ),
      )));
}

class MyApp extends StatefulWidget {
  final Locale? savedLocale;
  const MyApp({this.savedLocale, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: (kDebugMode ? 'Unustasis Dev' : 'Unustasis'),
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData(brightness: Brightness.light).textTheme),
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: createMaterialColor(const Color(0xFF099768)),
          onPrimary: Colors.black,
          secondary: Colors.green,
          onSecondary: Colors.black,
          surface: Colors.white,
          onTertiary: Colors.white,
          onSurface: Colors.black,
          surfaceContainer: Colors.grey.shade200,
          error: Colors.red,
          onError: Colors.black,
        ),
        /* dark theme settings */
      ),
      darkTheme: ThemeData(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme),
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: createMaterialColor(const Color(0xFF3DCC9D)),
          onPrimary: Colors.white,
          secondary: Colors.green,
          onSecondary: Colors.white,
          surface: const Color.fromARGB(255, 20, 20, 20),
          onTertiary: Colors.black,
          onSurface: Colors.white,
          surfaceContainer: Colors.grey.shade900,
          error: Colors.red,
          onError: Colors.white,
        ),
        /* dark theme settings */
      ),
      themeMode: EasyDynamicTheme.of(context).themeMode,
      localizationsDelegates: [
        FlutterI18nDelegate(
          translationLoader: FileTranslationLoader(
            useCountryCode: false,
            fallbackFile: 'en',
            basePath: 'assets/i18n',
            forcedLocale: widget.savedLocale,
          ),
          missingTranslationHandler: (key, locale) {
            Logger("Main").warning(
                "--- Missing Key: $key, languageCode: ${locale?.languageCode}");
          },
        ),
      ],
      home: const HomeScreen(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.r.round(), g = color.g.round(), b = color.b.round();

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}
