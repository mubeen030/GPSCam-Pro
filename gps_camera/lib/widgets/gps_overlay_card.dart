import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

class GPSOverlayCard extends StatefulWidget {
  final Position? position;
  final Placemark? address;
  final DateTime dateTime;

  const GPSOverlayCard({
    super.key,
    required this.position,
    required this.address,
    required this.dateTime,
  });

  @override
  State<GPSOverlayCard> createState() => _GPSOverlayCardState();
}

class _GPSOverlayCardState extends State<GPSOverlayCard> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;

  @override
  void didUpdateWidget(covariant GPSOverlayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != null && widget.position != oldWidget.position) {
      if (_isMapReady) {
        _mapController.move(
          LatLng(widget.position!.latitude, widget.position!.longitude), 
          15.0
        );
      }
    }
  }

  String _getDirection(double? heading) {
    if (heading == null) return "N 0°";
    final directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) % 360) ~/ 45;
    return "${directions[index]} ${heading.toInt()}°";
  }

  @override
  Widget build(BuildContext context) {
    // FORMATTING: "Sunday, 08 Feb 2026"
    final dayStr = DateFormat('EEEE').format(widget.dateTime);
    final dateStr = DateFormat('dd MMM yyyy').format(widget.dateTime);
    final timeStr = DateFormat('hh:mm a').format(widget.dateTime);
    
    final lat = widget.position?.latitude ?? 0.0;
    final lng = widget.position?.longitude ?? 0.0;
    final heading = widget.position?.heading ?? 0.0;
    final point = LatLng(lat, lng);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15), 
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), 
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4), 
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // --- LEFT SIDE: INFO ---
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. LOCATION (Street & Area)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.address != null 
                                ? "${widget.address!.street}, ${widget.address!.locality}"
                                : "Locating...",
                              style: const TextStyle(
                                color: Colors.white, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 13,
                                shadows: [Shadow(color: Colors.black, blurRadius: 2)]
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 4),

                      // 2. DAY & TIME (Added Day Name)
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.amber, size: 12),
                          const SizedBox(width: 6),
                          Text(
                            "$dayStr, $dateStr  |  $timeStr",
                            style: const TextStyle(
                              color: Colors.amber, 
                              fontSize: 11,
                              fontWeight: FontWeight.w600
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // 3. LAT/LNG + COMPASS (Added Direction)
                      Row(
                        children: [
                          const Icon(Icons.explore, color: Colors.cyanAccent, size: 12),
                          const SizedBox(width: 6),
                          Text(
                            "${_getDirection(heading)}  |  ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}",
                            style: const TextStyle(
                              color: Colors.white70, 
                              fontSize: 11,
                              fontFamily: 'monospace' 
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // --- RIGHT SIDE: MINI MAP (Google Hybrid) ---
                if (widget.position != null)
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: point,
                              initialZoom: 15.0,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                              onMapReady: () { _isMapReady = true; },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}', // Google Hybrid
                                userAgentPackageName: 'com.example.gps_camera',
                              ),
                            ],
                          ),
                          const Center(
                            child: Icon(Icons.location_pin, color: Colors.red, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}