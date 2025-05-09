import '../models/scooter.dart';

/// Settings for the application
class AppSettings {
  /// Whether to automatically unlock when in proximity
  final bool autoUnlock;
  
  /// Threshold RSSI value for auto-unlock (-100 to 0, higher is closer)
  final int autoUnlockThreshold;
  
  /// Whether to flash hazard lights when locking/unlocking
  final bool hazardLighting;
  
  /// Whether to automatically open seat after unlocking
  final bool openSeatOnUnlock;
  
  /// User's preferred locale
  final String preferredLocale;
  
  /// Whether to require biometric authentication
  final bool useBiometrics;
  
  /// Whether to show seasonal effects
  final bool seasonalEffects;
  
  AppSettings({
    this.autoUnlock = false,
    this.autoUnlockThreshold = -70,
    this.hazardLighting = false,
    this.openSeatOnUnlock = false,
    this.preferredLocale = 'en',
    this.useBiometrics = false,
    this.seasonalEffects = true,
  });
  
  /// Creates a copy with updated fields
  AppSettings copyWith({
    bool? autoUnlock,
    int? autoUnlockThreshold,
    bool? hazardLighting,
    bool? openSeatOnUnlock,
    String? preferredLocale,
    bool? useBiometrics,
    bool? seasonalEffects,
  }) {
    return AppSettings(
      autoUnlock: autoUnlock ?? this.autoUnlock,
      autoUnlockThreshold: autoUnlockThreshold ?? this.autoUnlockThreshold,
      hazardLighting: hazardLighting ?? this.hazardLighting,
      openSeatOnUnlock: openSeatOnUnlock ?? this.openSeatOnUnlock,
      preferredLocale: preferredLocale ?? this.preferredLocale,
      useBiometrics: useBiometrics ?? this.useBiometrics,
      seasonalEffects: seasonalEffects ?? this.seasonalEffects,
    );
  }
  
  /// Converts to JSON representation
  Map<String, dynamic> toJson() {
    return {
      'autoUnlock': autoUnlock,
      'autoUnlockThreshold': autoUnlockThreshold,
      'hazardLighting': hazardLighting,
      'openSeatOnUnlock': openSeatOnUnlock,
      'preferredLocale': preferredLocale,
      'useBiometrics': useBiometrics,
      'seasonalEffects': seasonalEffects,
    };
  }
  
  /// Creates from JSON
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      autoUnlock: json['autoUnlock'] ?? false,
      autoUnlockThreshold: json['autoUnlockThreshold'] ?? -70,
      hazardLighting: json['hazardLighting'] ?? false,
      openSeatOnUnlock: json['openSeatOnUnlock'] ?? false,
      preferredLocale: json['preferredLocale'] ?? 'en',
      useBiometrics: json['useBiometrics'] ?? false,
      seasonalEffects: json['seasonalEffects'] ?? true,
    );
  }
}

/// Service interface for local storage operations
abstract class LocalStorageService {
  /// Gets all saved scooters
  Future<List<Scooter>> getScooters();
  
  /// Gets a specific scooter by ID
  Future<Scooter?> getScooter(String scooterId);
  
  /// Saves a scooter
  Future<void> saveScooter(Scooter scooter);
  
  /// Removes a scooter
  Future<void> deleteScooter(String scooterId);
  
  /// Gets the application settings
  Future<AppSettings> getAppSettings();
  
  /// Saves application settings
  Future<void> saveAppSettings(AppSettings settings);
  
  /// Clears all data
  Future<void> clearAll();
  
  /// Migrates data from the old format to the new format
  Future<void> migrateFromLegacyFormat();
}