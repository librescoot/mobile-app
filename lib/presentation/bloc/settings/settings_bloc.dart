import 'package:bloc/bloc.dart';
import 'package:logging/logging.dart';

import '../../../domain/services/local_storage_service.dart';
import 'settings_event.dart';
import 'settings_state.dart';

/// BLoC for managing application settings
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final LocalStorageService _storageService;
  final Logger _logger = Logger('SettingsBloc');
  
  SettingsBloc(this._storageService) : super(SettingsInitial()) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateAutoUnlockSetting>(_onUpdateAutoUnlock);
    on<UpdateAutoUnlockThreshold>(_onUpdateAutoUnlockThreshold);
    on<UpdateHazardLighting>(_onUpdateHazardLighting);
    on<UpdateOpenSeatOnUnlock>(_onUpdateOpenSeatOnUnlock);
    on<UpdatePreferredLocale>(_onUpdatePreferredLocale);
    on<UpdateBiometricsSetting>(_onUpdateBiometrics);
    on<UpdateSeasonalEffects>(_onUpdateSeasonalEffects);
  }
  
  Future<void> _onLoadSettings(
    LoadSettings event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final settings = await _storageService.getAppSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      _logger.severe('Failed to load settings', e);
      emit(SettingsError('Failed to load settings: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateAutoUnlock(
    UpdateAutoUnlockSetting event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(autoUnlock: event.enabled);
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update auto-unlock setting', e);
      emit(SettingsError('Failed to update auto-unlock: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateAutoUnlockThreshold(
    UpdateAutoUnlockThreshold event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        autoUnlockThreshold: event.threshold
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update auto-unlock threshold', e);
      emit(SettingsError('Failed to update threshold: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateHazardLighting(
    UpdateHazardLighting event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        hazardLighting: event.enabled
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update hazard lighting setting', e);
      emit(SettingsError('Failed to update hazard lighting: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateOpenSeatOnUnlock(
    UpdateOpenSeatOnUnlock event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        openSeatOnUnlock: event.enabled
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update open seat setting', e);
      emit(SettingsError('Failed to update open seat: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdatePreferredLocale(
    UpdatePreferredLocale event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        preferredLocale: event.locale
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update preferred locale', e);
      emit(SettingsError('Failed to update locale: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateBiometrics(
    UpdateBiometricsSetting event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        useBiometrics: event.enabled
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update biometrics setting', e);
      emit(SettingsError('Failed to update biometrics: ${e.toString()}'));
    }
  }
  
  Future<void> _onUpdateSeasonalEffects(
    UpdateSeasonalEffects event, 
    Emitter<SettingsState> emit
  ) async {
    try {
      final currentSettings = await _getCurrentSettings();
      emit(SettingsUpdating(currentSettings));
      
      final newSettings = currentSettings.copyWith(
        seasonalEffects: event.enabled
      );
      await _storageService.saveAppSettings(newSettings);
      
      emit(SettingsLoaded(newSettings));
    } catch (e) {
      _logger.severe('Failed to update seasonal effects setting', e);
      emit(SettingsError('Failed to update seasonal effects: ${e.toString()}'));
    }
  }
  
  /// Helper to get current settings
  Future<AppSettings> _getCurrentSettings() async {
    if (state is SettingsLoaded) {
      return (state as SettingsLoaded).settings;
    }
    return await _storageService.getAppSettings();
  }
}