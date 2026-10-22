import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  static LocationService get instance => _instance;
  LocationService._internal();

  double? _cachedLat;
  double? _cachedLng;
  Placemark? _cachedPlacemark;
  DateTime? _lastFetchTime;

  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint("Error fetching last known location: $e");
      return null;
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return await getLastKnownPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permissions are denied.");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permissions are permanently denied.");
        return null;
      }

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        return await getLastKnownPosition();
      }
    } catch (e) {
      debugPrint("Error fetching location: $e");
      return await getLastKnownPosition();
    }
  }

  Future<Placemark?> getAddressFromLatLng(double lat, double lng) async {
    // 1. Return cached address if moved less than 25m within the last 2 minutes
    if (_cachedPlacemark != null && _cachedLat != null && _cachedLng != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!).inMinutes < 2) {
        final distance = Geolocator.distanceBetween(_cachedLat!, _cachedLng!, lat, lng);
        if (distance < 25) {
          return _cachedPlacemark;
        }
      }
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        _cachedLat = lat;
        _cachedLng = lng;
        _cachedPlacemark = placemarks[0];
        _lastFetchTime = DateTime.now();
        return _cachedPlacemark;
      }
    } catch (e) {
      debugPrint("Error getting address: $e");
    }
    return _cachedPlacemark;
  }
}