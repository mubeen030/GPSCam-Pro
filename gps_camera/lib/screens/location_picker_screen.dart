import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';

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

  // --- GOOGLE MAPS LAYERS ---
  int _currentLayerIndex = 0; 
  final List<Map<String, dynamic>> _mapLayers = [
    {
      'name': 'Google Roads',
      'url': 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', // Google Standard
      'icon': Icons.satellite_alt, // Icon to switch TO Satellite
    },
    {
      'name': 'Google Satellite',
      'url': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}', // Google Hybrid
      'icon': Icons.map, // Icon to switch TO Map
    },
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation = LatLng(widget.initialLat, widget.initialLng);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
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

      if (target != null) {
        setState(() => _selectedLocation = target!);
        _mapController.move(target, 15.0);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location not found"), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Search failed: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _onTapMap(TapPosition _, LatLng point) {
    setState(() => _selectedLocation = point);
  }

  void _toggleLayer() {
    setState(() {
      _currentLayerIndex = _currentLayerIndex == 0 ? 1 : 0;
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
                userAgentPackageName: 'com.example.gps_camera',
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
            top: 16, left: 16, right: 16,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(hintText: "Search Google Maps...", border: InputBorder.none),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    IconButton(
                      icon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.arrow_forward, color: Colors.blue),
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
            bottom: 100,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: _toggleLayer,
              child: Icon(_mapLayers[_currentLayerIndex]['icon'], color: Colors.black87),
            ),
          ),
          
          // Layer Name Label
          Positioned(
            right: 80,
            bottom: 115,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(
                _currentLayerIndex == 0 ? "Switch to Satellite" : "Switch to Roads",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Coordinates Box
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
              child: Text(
                "Selected: ${_selectedLocation.latitude.toStringAsFixed(6)}, ${_selectedLocation.longitude.toStringAsFixed(6)}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}