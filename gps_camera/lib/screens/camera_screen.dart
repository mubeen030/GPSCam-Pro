import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart'; // Needed for LatLng
import 'package:permission_handler/permission_handler.dart';

import '../services/location_service.dart';
import '../widgets/gps_overlay_card.dart';
import 'editor_screen.dart';
import 'location_picker_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final LocationService _locationService = LocationService();
  final ImagePicker _picker = ImagePicker();

  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  String _ratioName = "4:3";

  // --- FOCUS & EXPOSURE VARIABLES ---
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  bool _showFocusUI = false; 
  double _focusX = 0;
  double _focusY = 0;
  Timer? _focusTimer;

  Position? _currentPosition;
  Placemark? _currentAddress;
  bool _isCameraInitialized = false;
  bool _isManualLocation = false; // TRUE = Map Selection, FALSE = Live GPS
  bool _isSwitchingCamera = false;
  
  StreamSubscription<Position>? _positionStream;
  Timer? _timeTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _positionStream?.cancel();
    _timeTimer?.cancel();
    _focusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initApp() async {
    await [
      Permission.camera, 
      Permission.location, 
      Permission.microphone, 
      Permission.storage, 
      Permission.photos,
    ].request();
    
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      await _initCamera(_cameras![0]);
    }
    _startLocationStream();
  }

  Future<void> _initCamera(CameraDescription cameraDescription) async {
    setState(() { _isSwitchingCamera = true; _isCameraInitialized = false; });
    final prevController = _controller;
    if (prevController != null) await prevController.dispose();

    final newController = CameraController(
      cameraDescription, 
      ResolutionPreset.max, 
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );
    _controller = newController;

    try {
      await newController.initialize();
      _minAvailableExposureOffset = await newController.getMinExposureOffset();
      _maxAvailableExposureOffset = await newController.getMaxExposureOffset();
      try { await newController.setFlashMode(_flashMode); } catch (_) { _flashMode = FlashMode.off; }
      if (mounted) setState(() { _isCameraInitialized = true; _isSwitchingCamera = false; });
    } catch (e) {
      if(mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  void _startLocationStream() {
    // We keep the stream running in background, but only update UI if !_isManualLocation
    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((p) {
      // ONLY update if we are NOT in manual mode
      if (mounted && !_isManualLocation) {
        setState(() => _currentPosition = p);
        _updateAddress(p.latitude, p.longitude);
      }
    });
  }

  Future<void> _updateAddress(double lat, double lng) async {
    try {
      final address = await _locationService.getAddressFromLatLng(lat, lng);
      if (mounted) setState(() => _currentAddress = address);
    } catch (e) {
      debugPrint("Address Error: $e");
    }
  }

  // --- MAP / RESET LOGIC (FIXED) ---
  Future<void> _handleMapButton() async {
    if (_isManualLocation) {
      // --- RESET MODE: Switch back to Live GPS ---
      setState(() {
        _isManualLocation = false;
        _currentAddress = null; // Clear old address temporarily
      });
      
      // Force an immediate GPS read so user doesn't wait for stream
      try {
        Position p = await Geolocator.getCurrentPosition();
        if (mounted && !_isManualLocation) {
           setState(() => _currentPosition = p);
           _updateAddress(p.latitude, p.longitude);
        }
      } catch (_) {}
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Switched to Live GPS"), duration: Duration(seconds: 1)),
      );

    } else {
      // --- PICK MODE: Open Map ---
      final result = await Navigator.push(
        context, 
        MaterialPageRoute(builder: (_) => LocationPickerScreen(
          initialLat: _currentPosition?.latitude ?? 0, 
          initialLng: _currentPosition?.longitude ?? 0
        ))
      );

      // If user selected a location (result is LatLng)
      if (result != null && result is LatLng) {
        setState(() {
          _isManualLocation = true;
          // Create a "Fake" Position object from the map click
          _currentPosition = Position(
            latitude: result.latitude, 
            longitude: result.longitude,
            timestamp: DateTime.now(), 
            accuracy: 1, 
            altitude: 0, 
            heading: 0, 
            speed: 0, 
            speedAccuracy: 0,
            altitudeAccuracy: 0, 
            headingAccuracy: 0
          );
        });
        
        // IMMEDIATELY fetch address for this new location
        await _updateAddress(result.latitude, result.longitude);
      }
    }
  }

  // --- ACTIONS ---

  void _cycleAspectRatio() {
    setState(() {
      if (_ratioName == "4:3") {
        _ratioName = "16:9";
      } else if (_ratioName == "16:9") {
        _ratioName = "Full";
      } else if (_ratioName == "Full") {
        _ratioName = "1:1";
      } else {
        _ratioName = "4:3";
      }
    });
  }

  double _getAspectRatioValue(BuildContext context) {
    switch (_ratioName) {
      case "16:9": return 9 / 16;
      case "Full": return MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
      case "1:1": return 1.0;
      case "4:3":
      default: return 3 / 4;
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      FlashMode nextMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) { debugPrint("Flash error: $e"); }
  }

  Future<void> _takePhoto() async {
    if (!_isCameraInitialized || _controller == null || _controller!.value.isTakingPicture) return;
    try {
      final XFile image = await _controller!.takePicture();
      _goToEditor(File(image.path));
    } catch (e) { debugPrint("Error: $e"); }
  }

  void _goToEditor(File imageFile) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(
      imageFile: imageFile, 
      initialPosition: _currentPosition!, 
      initialAddress: _currentAddress,
      aspectRatio: _getAspectRatioValue(context),
    )));
  }

  // --- FOCUS & EXPOSURE ---
  Future<void> _onTapFocus(TapUpDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _focusTimer?.cancel();

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    setState(() {
      _showFocusUI = true; 
      _focusX = details.localPosition.dx;
      _focusY = details.localPosition.dy;
    });

    try {
      await _controller!.setFocusPoint(offset);
      await _controller!.setFocusMode(FocusMode.auto);
    } catch (e) { /* Ignore */ }

    _startHideTimer();
  }

  void _startHideTimer() {
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showFocusUI = false);
    });
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _isSwitchingCamera || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final targetRatio = _getAspectRatioValue(context);
    double previewHeight = screenWidth / targetRatio;
    
    if (_ratioName == "Full") {
      previewHeight = MediaQuery.of(context).size.height;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          Center(
            child: SizedBox(
              width: screenWidth,
              height: previewHeight,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: screenWidth,
                      height: screenWidth * _controller!.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _onTapFocus(details, constraints),
                            child: CameraPreview(_controller!),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // 2. Focus Square
          if (_showFocusUI)
            Positioned(
              top: _focusY - 25,
              left: _focusX - 25,
              child: Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(border: Border.all(color: Colors.yellowAccent, width: 2), borderRadius: BorderRadius.circular(5)),
              ),
            ),

          // 3. Overlay
          Positioned(
            bottom: 160, left: 0, right: 0,
            child: GPSOverlayCard(
              position: _currentPosition, address: _currentAddress, dateTime: _currentTime,
            ),
          ),

          // 4. Brightness Slider
          if (_showFocusUI)
            Positioned(
              right: 10, top: 150, bottom: 200,
              child: RotatedBox(
                quarterTurns: 3, 
                child: SizedBox(
                  height: 40,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10), overlayShape: const RoundSliderOverlayShape(overlayRadius: 20), trackHeight: 2),
                    child: Slider(
                      value: _currentExposureOffset,
                      min: _minAvailableExposureOffset,
                      max: _maxAvailableExposureOffset,
                      activeColor: Colors.yellowAccent,
                      inactiveColor: Colors.white24,
                      onChangeStart: (_) => _focusTimer?.cancel(),
                      onChangeEnd: (_) => _startHideTimer(),
                      onChanged: (value) async {
                        setState(() => _currentExposureOffset = value);
                        await _controller!.setExposureOffset(value);
                      },
                    ),
                  ),
                ),
              ),
            ),
          
          if (_showFocusUI)
            Positioned(right: 20, bottom: 190, child: const Icon(Icons.wb_sunny, color: Colors.yellowAccent, size: 20)),

          // 5. Top Bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, bottom: 20, left: 16, right: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              ),
              child: Row(
                children: [
                  Image.asset('assets/image_0.png', height: 40),
                  const SizedBox(width: 8),
                  const Spacer(),
                  _buildGlassButton(text: _ratioName, onTap: _cycleAspectRatio),
                  const SizedBox(width: 8),
                  _buildGlassIcon(
                    icon: _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
                    isActive: _flashMode == FlashMode.torch,
                    onTap: _toggleFlash,
                  ),
                  const SizedBox(width: 8),
                  _buildGlassIcon(
                    icon: Icons.flip_camera_ios,
                    isActive: false,
                    onTap: () async {
                      if (_isSwitchingCamera) return;
                      setState(() => _isSwitchingCamera = true);
                      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
                      await _initCamera(_cameras![_selectedCameraIndex]);
                    },
                  ),
                ],
              ),
            ),
          ),

          // 6. Bottom Controls (Fixed Map Logic)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 140,
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 30),
                    onPressed: () async {
                      final xfile = await _picker.pickImage(source: ImageSource.gallery);
                      if (xfile != null) _goToEditor(File(xfile.path));
                    },
                  ),
                  
                  // Shutter Button
                  GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      height: 80, width: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white24),
                      child: Center(child: Container(height: 65, width: 65, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                    ),
                  ),
                  
                  // MAP BUTTON (Updated)
                  IconButton(
                    // If Manual: Show "GPS Off" (Click to Reset)
                    // If Auto: Show "Map" (Click to Pick)
                    icon: Icon(_isManualLocation ? Icons.gps_off : Icons.map, color: Colors.white, size: 30),
                    onPressed: _handleMapButton, // CALL THE NEW FUNCTION
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({required String text, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGlassIcon({required IconData icon, required VoidCallback onTap, required bool isActive}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: isActive ? Colors.amber : Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 20),
      ),
    );
  }
}