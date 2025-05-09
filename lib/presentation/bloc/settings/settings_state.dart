import 'package:flutter/foundation.dart';

import '../../../domain/services/local_storage_service.dart';

/// Base class for all settings-related states
@immutable
abstract class SettingsState {}

/// Initial state when the app starts
class SettingsInitial extends SettingsState {}

/// State when settings are loaded
class SettingsLoaded extends SettingsState {
  /// The current settings
  final AppSettings settings;
  
  SettingsLoaded(this.settings);
}

/// State during settings update
class SettingsUpdating extends SettingsState {
  /// The current settings being updated
  final AppSettings settings;
  
  SettingsUpdating(this.settings);
}

/// State when settings operation fails
class SettingsError extends SettingsState {
  /// Error message
  final String message;
  
  SettingsError(this.message);
}