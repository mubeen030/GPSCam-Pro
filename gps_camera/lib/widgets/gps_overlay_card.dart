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
  final ValueNotifier<DateTime>? timeNotifier;
  final bool showMap;
  final Color textColor;
  final String mapStyle;

  const GPSOverlayCard({
    super.key,
    required this.position,
    required this.address,
    required this.dateTime,
    this.timeNotifier,
    this.showMap = true,
    this.textColor = Colors.white,
    this.mapStyle = 'Satellite',
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
    if (widget.position != null && _isMapReady) {
      final oldPos = oldWidget.position;
      if (oldPos == null || 
          Geolocator.distanceBetween(
            oldPos.latitude, oldPos.longitude, 
            widget.position!.latitude, widget.position!.longitude
          ) > 5) {
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

  String _formatAddress(Placemark? address) {
    if (address == null) {
      return widget.position != null
          ? "Lat: ${widget.position!.latitude.toStringAsFixed(5)}, Lng: ${widget.position!.longitude.toStringAsFixed(5)}"
          : "Acquiring GPS location...";
    }

    final parts = <String>[];
    if (address.name != null && address.name!.trim().isNotEmpty) {
      parts.add(address.name!.trim());
    }
    final streetParts = [address.subThoroughfare, address.thoroughfare]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(" ");
    if (streetParts.isNotEmpty && !parts.contains(streetParts)) {
      parts.add(streetParts);
    }

    if (address.subLocality != null && address.subLocality!.trim().isNotEmpty && !parts.contains(address.subLocality!.trim())) {
      parts.add(address.subLocality!.trim());
    }
    if (address.locality != null && address.locality!.trim().isNotEmpty && !parts.contains(address.locality!.trim())) {
      parts.add(address.locality!.trim());
    }
    if (address.administrativeArea != null && address.administrativeArea!.trim().isNotEmpty && !parts.contains(address.administrativeArea!.trim())) {
      parts.add(address.administrativeArea!.trim());
    }

    if (parts.isEmpty) {
      return widget.position != null
          ? "Lat: ${widget.position!.latitude.toStringAsFixed(5)}, Lng: ${widget.position!.longitude.toStringAsFixed(5)}"
          : "Acquiring GPS location...";
    }
    return parts.join(", ");
  }

  Widget _buildDateTimeRow(DateTime dt) {
    final dayStr = DateFormat('EEEE').format(dt);
    final dateStr = DateFormat('dd MMM yyyy').format(dt);
    final timeStr = DateFormat('hh:mm:ss a').format(dt);
    return Row(
      children: [
        Icon(Icons.access_time_filled, color: Colors.amberAccent.shade400, size: 12),
        const SizedBox(width: 6),
        Text(
          "$dayStr, $dateStr  •  $timeStr",
          style: TextStyle(
            color: Colors.amberAccent.shade200, 
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.position?.latitude ?? 0.0;
    final lng = widget.position?.longitude ?? 0.0;
    final altitude = widget.position?.altitude ?? 0.0;
    final heading = widget.position?.heading ?? 0.0;
    final point = LatLng(lat, lng);

    final baseTextColor = widget.textColor;
    final addressText = _formatAddress(widget.address);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22), 
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- TELEMETRY DATA COLUMN ---
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. LOCATION (Formatted Street & City)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on, color: Colors.redAccent, size: 13),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                addressText,
                                style: TextStyle(
                                  color: baseTextColor, 
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 12.5,
                                  letterSpacing: 0.2,
                                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 5),

                        // 2. DAY & TIME (Isolated builder prevents re-rendering full overlay & map)
                        widget.timeNotifier != null
                            ? ValueListenableBuilder<DateTime>(
                                valueListenable: widget.timeNotifier!,
                                builder: (context, dt, _) => _buildDateTimeRow(dt),
                              )
                            : _buildDateTimeRow(widget.dateTime),

                        const SizedBox(height: 4),

                        // 3. LAT/LNG + COMPASS + ALTITUDE (Monospace telemetry)
                        Row(
                          children: [
                            const Icon(Icons.explore_outlined, color: Colors.cyanAccent, size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "${lat.toStringAsFixed(5)}°N, ${lng.toStringAsFixed(5)}°E  |  ${_getDirection(heading)}  |  ${altitude.toStringAsFixed(1)}m",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85), 
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- MINI MAP THUMBNAIL (Optional) ---
                  if (widget.showMap && widget.position != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
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
                                  urlTemplate: widget.mapStyle == 'Street Map'
                                      ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                                      : widget.mapStyle == 'Voyager'
                                          ? 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'
                                          : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                                  userAgentPackageName: 'com.mubeen.gpscampro',
                                  maxZoom: 18,
                                  tileDisplay: const TileDisplay.instantaneous(),
                                ),
                                if (widget.mapStyle == 'Satellite')
                                  TileLayer(
                                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'com.mubeen.gpscampro',
                                    maxZoom: 18,
                                    tileDisplay: const TileDisplay.instantaneous(),
                                  ),
                              ],
                            ),
                            // Radar pulse dot
                            Center(
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: Colors.red, blurRadius: 4, spreadRadius: 1)
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      );
    }
}