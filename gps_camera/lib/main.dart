import 'package:flutter/material.dart';
import 'screens/camera_screen.dart';

import 'services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GPSCameraApp());
  // Initialize AdMob in background without blocking camera startup
  AdService.initialize();
}

class GPSCameraApp extends StatelessWidget {
  const GPSCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Camera Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const CameraScreen(),
    );
  }
}