import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart'; // Needed for LatLng
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart';

import '../services/ad_service.dart';
import '../services/location_service.dart';
import '../widgets/gps_overlay_card.dart';
import 'editor_screen.dart';
import 'location_picker_screen.dart';
import 'settings_screen.dart';

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
  final ScreenshotController _screenshotController = ScreenshotController();

  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  String _ratioName = "4:3";
  bool _isSavingPhoto = false;
  bool _showShutterFlash = false;

  // --- STAMP CONFIGURATION ---
  bool _showMapInOverlay = true;
  bool _overlayAtBottom = true;
  Color _overlayTextColor = Colors.white;
  String _mapStyle = 'Satellite';

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
  bool _permissionDenied = false;
  String? _permissionError;
  String? _cameraError;
  
  StreamSubscription<Position>? _positionStream;
  Timer? _timeTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    AdService.instance.loadInterstitialAd();
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
    AdService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only dispose the camera when actually paused/hidden, not on transient inactive states
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _controller?.dispose();
      _controller = null;
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      // Robust resume: always re-initialize if controller was released
      if (!_isCameraInitialized || _controller == null) {
        if (_cameras != null && _cameras!.isNotEmpty) {
          _initCamera(_cameras![_selectedCameraIndex]);
        } else {
          _initApp();
        }
      }
    }
  }

  Future<void> _initApp() async {
    final cameraStatus = await Permission.camera.request();
    await Permission.location.request();
    
    if (cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _permissionError = "Camera permission is required to capture photos.";
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _permissionDenied = false;
        _permissionError = null;
      });
    }

    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        await _initCamera(_cameras![0]);
      } else {
        if (mounted) {
          setState(() {
            _cameraError = "No camera found on this device.";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = "Failed to access camera: $e";
        });
      }
    }
    _startLocationStream();
  }

  Future<void> _initCamera(CameraDescription cameraDescription) async {
    if (!mounted) return;
    setState(() {
      _isSwitchingCamera = true;
      _cameraError = null;
    });

    final prevController = _controller;
    _controller = null;
    if (prevController != null) {
      try {
        await prevController.dispose();
      } catch (e) {
        debugPrint("Error disposing previous camera controller: $e");
      }
    }

    // Try ResolutionPreset.high for fast startup and rock-solid compatibility
    CameraController newController = CameraController(
      cameraDescription, 
      ResolutionPreset.high, 
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );

    try {
      await newController.initialize();
      _controller = newController;
      try {
        _minAvailableExposureOffset = await newController.getMinExposureOffset();
        _maxAvailableExposureOffset = await newController.getMaxExposureOffset();
      } catch (_) {}
      try {
        await newController.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
      }
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isSwitchingCamera = false;
          _cameraError = null;
        });
      }
    } catch (e) {
      debugPrint("Camera initialize error (ResolutionPreset.high): $e");
      try {
        await newController.dispose();
      } catch (_) {}

      // Fallback to ResolutionPreset.medium if high is not supported
      try {
        newController = CameraController(
          cameraDescription,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
        );
        await newController.initialize();
        _controller = newController;
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _isSwitchingCamera = false;
            _cameraError = null;
          });
        }
      } catch (e2) {
        debugPrint("Camera fallback to medium failed: $e2");
        if (mounted) {
          setState(() {
            _isCameraInitialized = false;
            _isSwitchingCamera = false;
            _cameraError = "Unable to start camera ($e2). Please tap retry.";
          });
        }
      }
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
      
      if (!mounted) return;
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
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
    try {
      FlashMode nextMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) { debugPrint("Flash error: $e"); }
  }

  Future<void> _openSettings() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          showMap: _showMapInOverlay,
          isBottom: _overlayAtBottom,
          textColor: _overlayTextColor,
          mapStyle: _mapStyle,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _showMapInOverlay = result['showMap'] ?? true;
        _overlayAtBottom = result['isBottom'] ?? true;
        _overlayTextColor = result['textColor'] ?? Colors.white;
        _mapStyle = result['mapStyle'] ?? 'Satellite';
      });
    }
  }

  Future<void> _takePhoto() async {
    if (!_isCameraInitialized || _controller == null || _controller!.value.isTakingPicture || _isSavingPhoto) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _showShutterFlash = true;
      _isSavingPhoto = true;
    });

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final targetRatio = _getAspectRatioValue(context);
    double previewHeight = screenWidth / targetRatio;
    if (_ratioName == "Full") {
      previewHeight = MediaQuery.of(context).size.height;
    }

    try {
      final XFile image = await _controller!.takePicture();

      // Immediately unlock the shutter button so the user can continue taking photos
      if (mounted) {
        setState(() => _isSavingPhoto = false);
      }

      // Snapshot current state for background processing
      final currentPos = _currentPosition;
      final currentAddr = _currentAddress;
      final currentTime = _currentTime;
      final showMap = _showMapInOverlay;
      final isBottom = _overlayAtBottom;
      final textColor = _overlayTextColor;
      final mapStyle = _mapStyle;

      // Process and save silently in the background (no loading delay, no popup message)
      _processAndSavePhoto(
        image: image,
        position: currentPos,
        address: currentAddr,
        dateTime: currentTime,
        showMap: showMap,
        isBottom: isBottom,
        textColor: textColor,
        mapStyle: mapStyle,
        screenWidth: screenWidth,
        previewHeight: previewHeight,
      );
    } catch (e) {
      debugPrint("Photo capture error: $e");
      if (mounted) {
        setState(() => _isSavingPhoto = false);
      }
    }
  }

  Future<void> _processAndSavePhoto({
    required XFile image,
    required Position? position,
    required Placemark? address,
    required DateTime dateTime,
    required bool showMap,
    required bool isBottom,
    required Color textColor,
    required String mapStyle,
    required double screenWidth,
    required double previewHeight,
  }) async {
    try {
      final Uint8List imageBytes = await image.readAsBytes();

      final Uint8List compositedBytes = await _screenshotController.captureFromWidget(
        Material(
          color: Colors.black,
          child: SizedBox(
            width: screenWidth,
            height: previewHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
                Align(
                  alignment: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: isBottom ? 20 : 0,
                      top: isBottom ? 0 : 20,
                    ),
                    child: GPSOverlayCard(
                      position: position,
                      address: address,
                      dateTime: dateTime,
                      showMap: showMap,
                      textColor: textColor,
                      mapStyle: mapStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        delay: const Duration(milliseconds: 40),
        pixelRatio: 2.0,
      );

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/GPS_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(compositedBytes);

      // Save directly to device gallery
      await Gal.putImage(file.path, album: "GPS Camera Pro");
      AdService.instance.onPhotoSaved(interval: 3);

      // Clean up temp files silently
      try { await File(image.path).delete(); } catch (_) {}
      try { await file.delete(); } catch (_) {}
    } catch (e) {
      debugPrint("Background photo composite/save error: $e");
    }
  }

  void _goToEditor(File imageFile) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(
      imageFile: imageFile, 
      initialPosition: _currentPosition, 
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
    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.amber, size: 64),
                const SizedBox(height: 16),
                Text(
                  _permissionError ?? "Camera permission is required.",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text("Open App Settings"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _initApp,
                  child: const Text("Retry", style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_cameraError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.amberAccent, size: 64),
                const SizedBox(height: 16),
                Text(
                  _cameraError!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_cameras != null && _cameras!.isNotEmpty) {
                      _initCamera(_cameras![_selectedCameraIndex]);
                    } else {
                      _initApp();
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("Retry Camera"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _isSwitchingCamera || _controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.amberAccent),
              const SizedBox(height: 20),
              const Text(
                "Starting Camera...",
                style: TextStyle(color: Colors.white70, fontSize: 15, letterSpacing: 0.5),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  if (_cameras != null && _cameras!.isNotEmpty) {
                    _initCamera(_cameras![_selectedCameraIndex]);
                  } else {
                    _initApp();
                  }
                },
                icon: const Icon(Icons.refresh_rounded, color: Colors.white60, size: 18),
                label: const Text("Taking too long? Tap to reload", style: TextStyle(color: Colors.white60, fontSize: 13)),
              ),
            ],
          ),
        ),
      );
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

          // 3. Overlay (Positioned based on user preference)
          Positioned(
            top: _overlayAtBottom ? null : 100,
            bottom: _overlayAtBottom ? 160 : null,
            left: 0, right: 0,
            child: GPSOverlayCard(
              position: _currentPosition,
              address: _currentAddress,
              dateTime: _currentTime,
              showMap: _showMapInOverlay,
              textColor: _overlayTextColor,
              mapStyle: _mapStyle,
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
            const Positioned(right: 20, bottom: 190, child: Icon(Icons.wb_sunny, color: Colors.yellowAccent, size: 20)),

          // 5. Shutter Flash Effect
          if (_showShutterFlash)
            Positioned.fill(
              child: Container(color: Colors.white.withValues(alpha: 0.85)),
            ),

          // 6. Top Bar (Wrapped in SafeArea)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    // Brand Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.gps_fixed, color: Colors.cyanAccent, size: 13),
                          SizedBox(width: 6),
                          Text(
                            "GPSCAM",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        HapticFeedback.selectionClick();
                        setState(() => _isSwitchingCamera = true);
                        _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
                        await _initCamera(_cameras![_selectedCameraIndex]);
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildGlassIcon(
                      icon: Icons.tune_rounded,
                      isActive: false,
                      onTap: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 7. Bottom Controls (Tactile Pro Layout)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 140,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gallery Button with rounded aesthetic
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final xfile = await _picker.pickImage(source: ImageSource.gallery);
                      if (xfile != null) _goToEditor(File(xfile.path));
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24, width: 1.2),
                      ),
                      child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                    ),
                  ),
                  
                  // Pro Shutter Button
                  GestureDetector(
                    onTap: _isSavingPhoto ? null : _takePhoto,
                    child: Container(
                      height: 82,
                      width: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        border: Border.all(color: Colors.white, width: 4), 
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: _isSavingPhoto ? 54 : 66, 
                          width: _isSavingPhoto ? 54 : 66, 
                          decoration: BoxDecoration(
                            color: _isSavingPhoto ? Colors.white70 : Colors.white, 
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.white24, blurRadius: 8, spreadRadius: 2)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Map Picker Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _handleMapButton();
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isManualLocation ? Colors.amber.withValues(alpha: 0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isManualLocation ? Colors.amberAccent : Colors.white24,
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        _isManualLocation ? Icons.gps_off_rounded : Icons.map_outlined,
                        color: _isManualLocation ? Colors.amberAccent : Colors.white,
                        size: 24,
                      ),
                    ),
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