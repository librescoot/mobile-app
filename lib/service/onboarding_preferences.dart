import 'package:shared_preferences/shared_preferences.dart';

const int currentFirstRunOnboardingVersion = 1;
const String firstRunOnboardingVersionKey = 'firstRunOnboardingVersion';

class OnboardingPreferences {
  OnboardingPreferences({SharedPreferencesAsync? preferences}) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<bool> isCurrent() async {
    final version = await _preferences.getInt(firstRunOnboardingVersionKey) ?? 0;
    return version >= currentFirstRunOnboardingVersion;
  }

  Future<bool?> onlineServicesChoice() => _preferences.getBool('osmConsent');

  Future<void> complete({required bool onlineServicesEnabled}) async {
    // Persist the choice before the completion marker. An interrupted write can
    // therefore never mark onboarding complete without recording consent.
    await _preferences.setBool('osmConsent', onlineServicesEnabled);
    await _preferences.setInt(firstRunOnboardingVersionKey, currentFirstRunOnboardingVersion);
  }
}
