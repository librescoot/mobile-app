import 'package:flutter/foundation.dart';

/// Base class for all settings-related events
@immutable
abstract class SettingsEvent {}

/// Event to load settings
class LoadSettings extends SettingsEvent {}

/// Event to update auto-unlock setting
class UpdateAutoUnlockSetting extends SettingsEvent {
  /// Whether auto-unlock is enabled
  final bool enabled;
  
  UpdateAutoUnlockSetting(this.enabled);
}

/// Event to update auto-unlock threshold
class UpdateAutoUnlockThreshold extends SettingsEvent {
  /// The RSSI threshold for auto-unlock
  final int threshold;
  
  UpdateAutoUnlockThreshold(this.threshold);
}

/// Event to update hazard lighting setting
class UpdateHazardLighting extends SettingsEvent {
  /// Whether hazard lighting is enabled
  final bool enabled;
  
  UpdateHazardLighting(this.enabled);
}

/// Event to update open seat on unlock setting
class UpdateOpenSeatOnUnlock extends SettingsEvent {
  /// Whether to open seat on unlock
  final bool enabled;
  
  UpdateOpenSeatOnUnlock(this.enabled);
}

/// Event to update preferred locale
class UpdatePreferredLocale extends SettingsEvent {
  /// The preferred locale code
  final String locale;
  
  UpdatePreferredLocale(this.locale);
}

/// Event to update biometrics setting
class UpdateBiometricsSetting extends SettingsEvent {
  /// Whether biometrics is required
  final bool enabled;
  
  UpdateBiometricsSetting(this.enabled);
}

/// Event to update seasonal effects setting
class UpdateSeasonalEffects extends SettingsEvent {
  /// Whether seasonal effects are enabled
  final bool enabled;
  
  UpdateSeasonalEffects(this.enabled);
}