import 'package:flutter/foundation.dart';

/// Represents a geographical location with coordinates and a timestamp
@immutable
class Location {
  /// Latitude coordinate
  final double latitude;
  
  /// Longitude coordinate
  final double longitude;
  
  /// When this location was recorded
  final DateTime timestamp;

  Location({
    required this.latitude,
    required this.longitude,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a copy with updated fields
  Location copyWith({
    double? latitude,
    double? longitude,
    DateTime? timestamp,
  }) {
    return Location(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Converts to JSON
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates from JSON
  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      latitude: json['latitude'],
      longitude: json['longitude'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is Location &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return latitude.hashCode ^
      longitude.hashCode ^
      timestamp.hashCode;
  }

  @override
  String toString() {
    return 'Location(latitude: $latitude, longitude: $longitude, timestamp: $timestamp)';
  }
}