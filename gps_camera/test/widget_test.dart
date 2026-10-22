import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:gps_camera/main.dart';
import 'package:gps_camera/widgets/gps_overlay_card.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GPSCameraApp());
    expect(find.byType(GPSCameraApp), findsOneWidget);
  });

  testWidgets('GPSOverlayCard displays coordinates, address, and time', (WidgetTester tester) async {
    final testPos = Position(
      latitude: 37.4219983,
      longitude: -122.084,
      timestamp: DateTime(2026, 10, 22, 12, 0, 0),
      accuracy: 5.0,
      altitude: 15.2,
      heading: 90.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 1.0,
      headingAccuracy: 1.0,
    );

    const testPlacemark = Placemark(
      name: 'Googleplex',
      thoroughfare: 'Amphitheatre Pkwy',
      locality: 'Mountain View',
      administrativeArea: 'CA',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GPSOverlayCard(
            position: testPos,
            address: testPlacemark,
            dateTime: DateTime(2026, 10, 22, 12, 30, 0),
            showMap: false,
          ),
        ),
      ),
    );

    // Verify address is displayed
    expect(find.textContaining('Googleplex'), findsOneWidget);
    // Verify latitude and longitude are displayed
    expect(find.textContaining('37.42200°N'), findsOneWidget);
    expect(find.textContaining('-122.08400°E'), findsOneWidget);
    // Verify elevation is displayed
    expect(find.textContaining('15.2m'), findsOneWidget);
  });

  testWidgets('GPSOverlayCard handles null position gracefully', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GPSOverlayCard(
            position: null,
            address: null,
            dateTime: DateTime(2026, 10, 22, 12, 30, 0),
            showMap: false,
          ),
        ),
      ),
    );

    expect(find.text('Acquiring GPS location...'), findsOneWidget);
    expect(find.textContaining('0.00000°N'), findsOneWidget);
  });

  testWidgets('GPSOverlayCard builds with showMap: true', (WidgetTester tester) async {
    final testPos = Position(
      latitude: 19.0760,
      longitude: 72.8777,
      timestamp: DateTime(2026, 10, 22, 12, 0, 0),
      accuracy: 5.0,
      altitude: 10.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 1.0,
      headingAccuracy: 1.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GPSOverlayCard(
            position: testPos,
            address: null,
            dateTime: DateTime(2026, 10, 22, 12, 30, 0),
            showMap: true,
          ),
        ),
      ),
    );

    expect(find.byType(GPSOverlayCard), findsOneWidget);
  });
}
