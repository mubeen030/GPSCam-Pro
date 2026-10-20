import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapThumbnail extends StatelessWidget {
  final double lat;
  final double lng;

  const MapThumbnail({super.key, required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: 15.0,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none), // Static map
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.mubeen.gpscampro',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 20,
              height: 20,
              child: const Icon(Icons.location_on, color: Colors.red, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}