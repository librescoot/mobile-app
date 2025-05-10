import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/scooter.dart';
import '../../domain/services/local_storage_service.dart';

/// Implementation of [LocalStorageService] using SharedPreferences
class SharedPrefsStorageService implements LocalStorageService {
  final Logger _logger = Logger('SharedPrefsStorageService');
  static const String _scootersKey = 'scooters';
  static const String _settingsKey = 'app_settings';
  
  // Legacy keys for migration
  static const String _legacySavedScootersKey = 'savedScooters';
  static const String _legacySavedScooterIdKey = 'savedScooterId';
  
  SharedPreferences? _prefs;
  
  /// Ensures that the shared preferences instance is initialized
  Future<SharedPreferences> _getPrefs() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    return _prefs!;
  }
  
  @override
  Future<List<Scooter>> getScooters() async {
    try {
      final prefs = await _getPrefs();
      
      if (!prefs.containsKey(_scootersKey)) {
        // Check if we need migration
        if (prefs.containsKey(_legacySavedScootersKey) || 
            prefs.containsKey(_legacySavedScooterIdKey)) {
          await migrateFromLegacyFormat();
          return getScooters();
        }
        return [];
      }
      
      final String scootersJson = prefs.getString(_scootersKey) ?? '{}';
      final Map<String, dynamic> scootersMap = jsonDecode(scootersJson);
      
      final List<Scooter> scooters = [];
      
      for (final entry in scootersMap.entries) {
        try {
          final scooterJson = entry.value as Map<String, dynamic>;
          final scooter = Scooter.fromJson(scooterJson);
          scooters.add(scooter);
        } catch (e) {
          _logger.warning('Failed to parse scooter: ${entry.key}', e);
        }
      }
      
      return scooters;
    } catch (e) {
      _logger.severe('Error getting scooters from storage', e);
      return [];
    }
  }
  
  @override
  Future<Scooter?> getScooter(String scooterId) async {
    try {
      final prefs = await _getPrefs();
      
      if (!prefs.containsKey(_scootersKey)) {
        // Check if we need migration
        if (prefs.containsKey(_legacySavedScootersKey) || 
            prefs.containsKey(_legacySavedScooterIdKey)) {
          await migrateFromLegacyFormat();
          return getScooter(scooterId);
        }
        return null;
      }
      
      final String scootersJson = prefs.getString(_scootersKey) ?? '{}';
      final Map<String, dynamic> scootersMap = jsonDecode(scootersJson);
      
      if (!scootersMap.containsKey(scooterId)) {
        return null;
      }
      
      try {
        final scooterJson = scootersMap[scooterId] as Map<String, dynamic>;
        return Scooter.fromJson(scooterJson);
      } catch (e) {
        _logger.warning('Failed to parse scooter: $scooterId', e);
        return null;
      }
    } catch (e) {
      _logger.severe('Error getting scooter from storage', e);
      return null;
    }
  }
  
  @override
  Future<void> saveScooter(Scooter scooter) async {
    try {
      final prefs = await _getPrefs();
      
      String scootersJson = prefs.getString(_scootersKey) ?? '{}';
      Map<String, dynamic> scootersMap = jsonDecode(scootersJson);
      
      scootersMap[scooter.id] = scooter.toJson();
      
      await prefs.setString(_scootersKey, jsonEncode(scootersMap));
    } catch (e) {
      _logger.severe('Error saving scooter to storage', e);
      throw Exception('Failed to save scooter: ${e.toString()}');
    }
  }
  
  @override
  Future<void> deleteScooter(String scooterId) async {
    try {
      final prefs = await _getPrefs();
      
      if (!prefs.containsKey(_scootersKey)) {
        return;
      }
      
      String scootersJson = prefs.getString(_scootersKey) ?? '{}';
      Map<String, dynamic> scootersMap = jsonDecode(scootersJson);
      
      if (scootersMap.containsKey(scooterId)) {
        scootersMap.remove(scooterId);
        await prefs.setString(_scootersKey, jsonEncode(scootersMap));
      }
    } catch (e) {
      _logger.severe('Error deleting scooter from storage', e);
      throw Exception('Failed to delete scooter: ${e.toString()}');
    }
  }
  
  @override
  Future<AppSettings> getAppSettings() async {
    try {
      final prefs = await _getPrefs();
      
      if (!prefs.containsKey(_settingsKey)) {
        // Return default settings if none are saved
        return AppSettings();
      }
      
      final String settingsJson = prefs.getString(_settingsKey) ?? '{}';
      final Map<String, dynamic> settingsMap = jsonDecode(settingsJson);
      
      return AppSettings.fromJson(settingsMap);
    } catch (e) {
      _logger.severe('Error getting app settings from storage', e);
      // Return default settings on error
      return AppSettings();
    }
  }
  
  @override
  Future<void> saveAppSettings(AppSettings settings) async {
    try {
      final prefs = await _getPrefs();
      
      final String settingsJson = jsonEncode(settings.toJson());
      await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      _logger.severe('Error saving app settings to storage', e);
      throw Exception('Failed to save app settings: ${e.toString()}');
    }
  }
  
  @override
  Future<void> clearAll() async {
    try {
      final prefs = await _getPrefs();
      await prefs.clear();
    } catch (e) {
      _logger.severe('Error clearing storage', e);
      throw Exception('Failed to clear storage: ${e.toString()}');
    }
  }
  
  @override
  Future<void> migrateFromLegacyFormat() async {
    _logger.info('Migrating from legacy storage format');
    try {
      final prefs = await _getPrefs();
      
      Map<String, dynamic> scootersMap = {};
      
      // Check for legacy savedScooters format
      if (prefs.containsKey(_legacySavedScootersKey)) {
        String legacyJson = prefs.getString(_legacySavedScootersKey) ?? '{}';
        Map<String, dynamic> legacyMap = jsonDecode(legacyJson);
        
        for (final entry in legacyMap.entries) {
          try {
            final legacyScooter = entry.value as Map<String, dynamic>;
            legacyScooter['id'] = entry.key;
            
            // Create modern scooter from legacy format
            final scooter = Scooter.fromSavedScooter(legacyScooter);
            scootersMap[scooter.id] = scooter.toJson();
          } catch (e) {
            _logger.warning('Failed to migrate legacy scooter: ${entry.key}', e);
          }
        }
      } 
      // Check for older single scooter format
      else if (prefs.containsKey(_legacySavedScooterIdKey)) {
        final String scooterId = prefs.getString(_legacySavedScooterIdKey) ?? '';
        
        if (scooterId.isNotEmpty) {
          try {
            // Collect all legacy properties
            Map<String, dynamic> legacyScooter = {
              'id': scooterId,
              'name': 'Scooter Pro',
              'color': prefs.getInt('color') ?? 1,
              'autoConnect': true,
            };
            
            if (prefs.containsKey('lastPing')) {
              legacyScooter['lastPing'] = prefs.getInt('lastPing');
            }
            
            if (prefs.containsKey('lastLat') && prefs.containsKey('lastLng')) {
              legacyScooter['lastLocation'] = {
                'latitude': prefs.getDouble('lastLat'),
                'longitude': prefs.getDouble('lastLng'),
              };
            }
            
            if (prefs.containsKey('primarySOC')) {
              legacyScooter['lastPrimarySOC'] = prefs.getInt('primarySOC');
            }
            
            if (prefs.containsKey('secondarySOC')) {
              legacyScooter['lastSecondarySOC'] = prefs.getInt('secondarySOC');
            }
            
            if (prefs.containsKey('cbbSOC')) {
              legacyScooter['lastCbbSOC'] = prefs.getInt('cbbSOC');
            }
            
            if (prefs.containsKey('auxSOC')) {
              legacyScooter['lastAuxSOC'] = prefs.getInt('auxSOC');
            }
            
            // Create modern scooter from legacy format
            final scooter = Scooter.fromSavedScooter(legacyScooter);
            scootersMap[scooter.id] = scooter.toJson();
          } catch (e) {
            _logger.warning('Failed to migrate single legacy scooter', e);
          }
        }
      }
      
      // Save migrated scooters
      if (scootersMap.isNotEmpty) {
        await prefs.setString(_scootersKey, jsonEncode(scootersMap));
        _logger.info('Successfully migrated ${scootersMap.length} scooters');
      }
      
      // Migrate app settings
      AppSettings settings = AppSettings(
        autoUnlock: prefs.getBool('autoUnlock') ?? false,
        autoUnlockThreshold: prefs.getInt('autoUnlockThreshold') ?? -70,
        hazardLighting: prefs.getBool('hazardLocking') ?? false,
        openSeatOnUnlock: prefs.getBool('openSeatOnUnlock') ?? false,
        preferredLocale: prefs.getString('savedLocale') ?? 'en',
        useBiometrics: prefs.getBool('biometrics') ?? false,
        seasonalEffects: prefs.getBool('seasonal') ?? true,
      );
      
      await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
      
      // Clean up legacy keys
      await prefs.remove(_legacySavedScootersKey);
      await prefs.remove(_legacySavedScooterIdKey);
      await prefs.remove('lastPing');
      await prefs.remove('lastLat');
      await prefs.remove('lastLng');
      await prefs.remove('color');
      await prefs.remove('primarySOC');
      await prefs.remove('secondarySOC');
      await prefs.remove('cbbSOC');
      await prefs.remove('auxSOC');
      await prefs.remove('autoUnlock');
      await prefs.remove('autoUnlockThreshold');
      await prefs.remove('hazardLocking');
      await prefs.remove('openSeatOnUnlock');
      await prefs.remove('biometrics');
      await prefs.remove('seasonal');
      
      _logger.info('Migration completed successfully');
    } catch (e) {
      _logger.severe('Error during migration', e);
      throw Exception('Failed to migrate from legacy format: ${e.toString()}');
    }
  }
}