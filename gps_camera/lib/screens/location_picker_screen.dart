import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../services/location_service.dart';
import '../widgets/ad_banner_widget.dart';

class LocationPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const LocationPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController;
  late LatLng _selectedLocation;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // --- COMPLIANT OPEN MAP LAYERS ---
  int _currentLayerIndex = 0; 
  final List<Map<String, dynamic>> _mapLayers = [
    {
      'name': 'Satellite',
      'url': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'icon': Icons.satellite_alt_rounded,
    },
    {
      'name': 'Street Map',
      'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      'icon': Icons.terrain,
    },
    {
      'name': 'Voyager',
      'url': 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      'icon': Icons.map,
    },
  ];

  String _currentLocationName = "Resolving location...";

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation = LatLng(widget.initialLat, widget.initialLng);
    _fetchLocationName(widget.initialLat, widget.initialLng);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocationName(double lat, double lng) async {
    try {
      Placemark? p = await LocationService.instance.getAddressFromLatLng(lat, lng);
      if (p != null && mounted) {
        final parts = <String>[];
        if (p.name != null && p.name!.trim().isNotEmpty) parts.add(p.name!.trim());
        final streetParts = [p.subThoroughfare, p.thoroughfare]
            .where((s) => s != null && s.trim().isNotEmpty)
            .join(" ");
        if (streetParts.isNotEmpty && !parts.contains(streetParts)) {
          parts.add(streetParts);
        }
        if (p.subLocality != null && p.subLocality!.trim().isNotEmpty && !parts.contains(p.subLocality!.trim())) {
          parts.add(p.subLocality!.trim());
        }
        if (p.locality != null && p.locality!.trim().isNotEmpty && !parts.contains(p.locality!.trim())) {
          parts.add(p.locality!.trim());
        }
        if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty && !parts.contains(p.administrativeArea!.trim())) {
          parts.add(p.administrativeArea!.trim());
        }
        setState(() {
          _currentLocationName = parts.isNotEmpty ? parts.join(", ") : "${lat.toStringAsFixed(5)}°, ${lng.toStringAsFixed(5)}°";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocationName = "${lat.toStringAsFixed(5)}°, ${lng.toStringAsFixed(5)}°";
        });
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();

    try {
      LatLng? target;
      if (query.contains(',') && query.replaceAll(RegExp(r'[^0-9.,-]'), '').isNotEmpty) {
        final parts = query.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) target = LatLng(lat, lng);
        }
      }

      if (target == null) {
        List<Location> locations = await locationFromAddress(query);
        if (locations.isNotEmpty) {
          target = LatLng(locations.first.latitude, locations.first.longitude);
        }
      }

      if (!mounted) return;
      if (target != null) {
        setState(() {
          _selectedLocation = target!;
          _currentLocationName = "Resolving location...";
        });
        _mapController.move(target, 15.0);
        _fetchLocationName(target.latitude, target.longitude);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location not found"), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Search failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _onTapMap(TapPosition _, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _currentLocationName = "Resolving location...";
    });
    _fetchLocationName(point.latitude, point.longitude);
  }

  void _toggleLayer() {
    setState(() {
      _currentLayerIndex = (_currentLayerIndex + 1) % _mapLayers.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _selectedLocation),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 15.0,
              onTap: _onTapMap,
            ),
            children: [
              TileLayer(
                urlTemplate: _mapLayers[_currentLayerIndex]['url'],
                userAgentPackageName: 'com.mubeen.gpscampro',
                maxZoom: 18,
                tileDisplay: const TileDisplay.instantaneous(),
              ),
              if (_mapLayers[_currentLayerIndex]['name'] == 'Satellite')
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.mubeen.gpscampro',
                  maxZoom: 18,
                  tileDisplay: const TileDisplay.instantaneous(),
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation,
                    width: 50,
                    height: 50,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
                  ),
                ],
              ),
            ],
          ),

          // Search Bar
          Positioned(
            top: 14, left: 16, right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: "Search address or coordinates...", 
                          border: InputBorder.none,
                          hintStyle: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    IconButton(
                      icon: _isSearching 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.arrow_forward_rounded, color: Colors.blueAccent),
                      onPressed: _performSearch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Layer Toggle Button
          Positioned(
            right: 16,
            bottom: 104,
            child: FloatingActionButton.extended(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: _toggleLayer,
              icon: Icon(_mapLayers[_currentLayerIndex]['icon'], color: Colors.cyanAccent, size: 20),
              label: Text(
                _mapLayers[(_currentLayerIndex + 1) % _mapLayers.length]['name'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),

          // Floating Location Name & Coordinates Glass Card
          Positioned(
            bottom: 16, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentLocationName,
                          style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Text(
                      "${_selectedLocation.latitude.toStringAsFixed(6)}°, ${_selectedLocation.longitude.toStringAsFixed(6)}°",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7), 
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AdBannerWidget()),
    );
  }
}