import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../scooter_service.dart';

class NavigationSection extends StatefulWidget {
  const NavigationSection({
    required this.service,
    required this.dataIsOld,
    super.key,
  });

  final ScooterService service;
  final bool dataIsOld;

  @override
  State<NavigationSection> createState() => _NavigationSectionState();
}

class _NavigationSectionState extends State<NavigationSection> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng? _currentLocation;
  LatLng? _selectedDestination;
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoading = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      // Center map on current location
      if (_currentLocation != null) {
        _mapController.move(_currentLocation!, 15.0);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        LatLng destination = LatLng(location.latitude, location.longitude);
        
        setState(() {
          _selectedDestination = destination;
          _isSearching = false;
        });

        // Move map to the searched location
        _mapController.move(destination, 15.0);
      } else {
        setState(() => _isSearching = false);
        Fluttertoast.showToast(
          msg: FlutterI18n.translate(context, 'navigation_address_not_found'),
        );
      }
    } catch (e) {
      setState(() => _isSearching = false);
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, 'navigation_search_error'),
      );
    }
  }

  void _sendNavigationToScooter() async {
    if (_selectedDestination == null) {
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, 'navigation_no_destination'),
      );
      return;
    }

    try {
      // Format: navi:start xx.xxxxx,yy.yyyyy
      String command = 'navi:start ${_selectedDestination!.latitude.toStringAsFixed(6)},${_selectedDestination!.longitude.toStringAsFixed(6)}';
      
      // Use the service's sendCommand method
      widget.service.sendNavigationCommand(command);
      
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, 'navigation_sent_success'),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, 'navigation_send_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Search field
        Container(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: FlutterI18n.translate(context, 'navigation_search_hint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _selectedDestination = null;
                        });
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
            onSubmitted: _searchAddress,
          ),
        ),
        // Map
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(52.520008, 13.404954), // Berlin as fallback
              initialZoom: 13.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Disable rotation
              ),
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedDestination = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.freal.unustasis',
              ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.my_location,
                        color: Theme.of(context).colorScheme.primary,
                        size: 40,
                      ),
                    ),
                  if (_selectedDestination != null)
                    Marker(
                      point: _selectedDestination!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_on,
                        color: Theme.of(context).colorScheme.error,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Send button
        Container(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: StreamBuilder<bool>(
              stream: widget.service.connected,
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                return ElevatedButton(
                  onPressed: isConnected && _selectedDestination != null
                      ? _sendNavigationToScooter
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    FlutterI18n.translate(context, 'navigation_send_button'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}