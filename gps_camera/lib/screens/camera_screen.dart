import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart'; // Needed for LatLng
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart';

import '../services/ad_service.dart';
import '../services/album_service.dart';
import '../services/location_service.dart';
import '../widgets/gps_overlay_card.dart';
import 'album_viewer_screen.dart';
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
  final ScreenshotController _screenshotController = ScreenshotController();
  final GlobalKey _overlayCardKey = GlobalKey();

  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  String _ratioName = "4:3";
  bool _isSavingPhoto = false;

  // --- STAMP CONFIGURATION ---
  bool _showMapInOverlay = true;
  bool _overlayAtBottom = true;
  Color _overlayTextColor = Colors.white;
  String _mapStyle = 'Satellite';

  // --- ZOOM & GRID ---
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseScale = 1.0;
  bool _showGrid = false;

  // --- SHUTTER FEEDBACK ---
  bool _showShutterCurtain = false;
  bool _showSavedIndicator = false;
  Timer? _savedIndicatorTimer;
  Uint8List? _lastCapturedThumbnail;

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
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier<DateTime>(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _loadLatestThumbnail();
    AdService.instance.loadInterstitialAd();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _currentTimeNotifier.value = DateTime.now();
    });
  }

  Future<void> _loadLatestThumbnail() async {
    try {
      final latest = await AlbumService.instance.getLatestPhoto();
      if (latest != null && await latest.exists()) {
        final bytes = await latest.readAsBytes();
        if (mounted) {
          setState(() => _lastCapturedThumbnail = bytes);
        }
      } else {
        if (mounted && _lastCapturedThumbnail != null) {
          setState(() => _lastCapturedThumbnail = null);
        }
      }
    } catch (e) {
      debugPrint("Error loading latest thumbnail: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _positionStream?.cancel();
    _timeTimer?.cancel();
    _currentTimeNotifier.dispose();
    _focusTimer?.cancel();
    _savedIndicatorTimer?.cancel();
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
      _startLocationStream();
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

    // Use ResolutionPreset.medium for buttery smooth 60 FPS preview without dropped frames
    CameraController newController = CameraController(
      cameraDescription, 
      ResolutionPreset.medium, 
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
        _minAvailableZoom = await newController.getMinZoomLevel();
        _maxAvailableZoom = await newController.getMaxZoomLevel();
      } catch (_) {
        _minAvailableZoom = 1.0;
        _maxAvailableZoom = 1.0;
      }
      _currentZoom = _minAvailableZoom;
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
        try {
          _minAvailableZoom = await newController.getMinZoomLevel();
          _maxAvailableZoom = await newController.getMaxZoomLevel();
        } catch (_) {
          _minAvailableZoom = 1.0;
          _maxAvailableZoom = 1.0;
        }
        _currentZoom = _minAvailableZoom;
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

  Future<void> _startLocationStream() async {
    // 1. Immediately fetch last known position so overlay displays coordinates right away
    try {
      final lastPos = await _locationService.getLastKnownPosition();
      if (lastPos != null && mounted && !_isManualLocation && _currentPosition == null) {
        setState(() => _currentPosition = lastPos);
        _updateAddress(lastPos.latitude, lastPos.longitude);
      }
    } catch (e) {
      debugPrint("Last known location fetch error: $e");
    }

    // 2. Concurrently fetch high-accuracy fresh current position
    try {
      final freshPos = await _locationService.getCurrentPosition();
      if (freshPos != null && mounted && !_isManualLocation) {
        setState(() => _currentPosition = freshPos);
        _updateAddress(freshPos.latitude, freshPos.longitude);
      }
    } catch (e) {
      debugPrint("Current location fetch error: $e");
    }

    // 3. Keep stream listening with lower distanceFilter so movements update
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((p) {
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

  void _toggleGrid() {
    HapticFeedback.selectionClick();
    setState(() => _showGrid = !_showGrid);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.selectionClick();
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await _controller!.setFlashMode(nextMode);
      if (mounted) setState(() => _flashMode = nextMode);
    } catch (e) {
      debugPrint("Flash error for $nextMode: $e");
      try {
        await _controller!.setFlashMode(FlashMode.off);
        if (mounted) setState(() => _flashMode = FlashMode.off);
      } catch (_) {}
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
      case FlashMode.off:
        return Icons.flash_off;
    }
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

    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() {
      _showShutterCurtain = true;
      _isSavingPhoto = true;
    });

    Future.delayed(const Duration(milliseconds: 70), () {
      if (mounted) setState(() => _showShutterCurtain = false);
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final targetRatio = _getAspectRatioValue(context);
    double previewHeight = screenWidth / targetRatio;
    if (_ratioName == "Full") {
      previewHeight = MediaQuery.of(context).size.height;
    }

    // Capture the on-screen rendered overlay GPU image in ~1ms (zero PNG encoding overhead on UI thread)
    ui.Image? capturedOverlayImage;
    try {
      final boundary = _overlayCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        capturedOverlayImage = await boundary.toImage(pixelRatio: 2.0);
      }
    } catch (e) {
      debugPrint("Overlay boundary capture error: $e");
    }

    try {
      final XFile image = await _controller!.takePicture();

      // Immediately unlock the shutter button so the user can continue taking photos
      if (mounted) {
        setState(() => _isSavingPhoto = false);
      }

      // Snapshot current state for background processing
      Position? currentPos = _currentPosition;
      Placemark? currentAddr = _currentAddress;

      // Fallback: If position is null, try to get last known immediately so stamp is guaranteed
      if (currentPos == null) {
        try {
          currentPos = await _locationService.getLastKnownPosition();
          if (currentPos != null && currentAddr == null) {
            currentAddr = await _locationService.getAddressFromLatLng(currentPos.latitude, currentPos.longitude);
          }
        } catch (_) {}
      }

      final currentTime = _currentTimeNotifier.value;
      final showMap = _showMapInOverlay;
      final isBottom = _overlayAtBottom;
      final textColor = _overlayTextColor;
      final mapStyle = _mapStyle;

      // Process and save silently in the background (no loading delay, no popup message)
      _processAndSavePhoto(
        image: image,
        overlayImage: capturedOverlayImage,
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
      capturedOverlayImage?.dispose();
      debugPrint("Photo capture error: $e");
      if (mounted) {
        setState(() => _isSavingPhoto = false);
      }
    }
  }

  Future<void> _waitForImageToDecode(Uint8List bytes) async {
    final completer = Completer<void>();
    final imageProvider = MemoryImage(bytes);
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete();
      },
      onError: (e, s) {
        stream.removeListener(listener);
        completer.complete();
      },
    );
    stream.addListener(listener);
    await completer.future;
  }

  Future<Uint8List> _compositeOverlay({
    required Uint8List photoBytes,
    required ui.Image overlayImage,
    required bool isBottom,
  }) async {
    final photoCodec = await ui.instantiateImageCodec(photoBytes);
    final photoFrame = await photoCodec.getNextFrame();
    final photoImage = photoFrame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, photoImage.width.toDouble(), photoImage.height.toDouble()),
    );

    // 1. Draw raw camera photo at native resolution
    canvas.drawImage(photoImage, Offset.zero, Paint());

    // 2. Draw overlay scaled proportionally to match photo width
    final double targetWidth = photoImage.width.toDouble();
    final double scale = targetWidth / overlayImage.width;
    final double targetHeight = overlayImage.height * scale;

    final double margin = 16.0 * scale;
    final double yPos = isBottom
        ? (photoImage.height - targetHeight - margin)
        : margin;

    final srcRect = Rect.fromLTWH(
      0, 
      0, 
      overlayImage.width.toDouble(), 
      overlayImage.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(
      0, 
      yPos, 
      targetWidth, 
      targetHeight,
    );

    canvas.drawImageRect(
      overlayImage,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(photoImage.width, photoImage.height);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

    photoImage.dispose();
    overlayImage.dispose();
    finalImage.dispose();

    return byteData!.buffer.asUint8List();
  }

  Future<void> _processAndSavePhoto({
    required XFile image,
    required ui.Image? overlayImage,
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
      Uint8List? compositedBytes;

      // Method 1: Ultra-fast Canvas compositing using on-screen overlay GPU image
      if (overlayImage != null) {
        try {
          compositedBytes = await _compositeOverlay(
            photoBytes: imageBytes,
            overlayImage: overlayImage,
            isBottom: isBottom,
          );
        } catch (e) {
          debugPrint("Canvas compositing error, falling back to captureFromWidget: $e");
        }
      }

      // Method 2: Fallback to widget rasterization if on-screen overlay capture failed
      if (compositedBytes == null) {
        await _waitForImageToDecode(imageBytes);
        compositedBytes = await _screenshotController.captureFromWidget(
          Material(
            color: Colors.transparent,
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
                    gaplessPlayback: true,
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
          delay: const Duration(milliseconds: 300),
          pixelRatio: 2.5,
        );
      }

      // Save directly to persistent app album and device gallery
      await AlbumService.instance.savePhoto(compositedBytes);
      AdService.instance.onPhotoSaved(interval: 3);

      if (mounted) {
        setState(() {
          _lastCapturedThumbnail = compositedBytes;
          _showSavedIndicator = true;
        });
        _savedIndicatorTimer?.cancel();
        _savedIndicatorTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _showSavedIndicator = false);
        });
      }

      // Clean up raw camera capture
      try { await File(image.path).delete(); } catch (_) {}
    } catch (e) {
      debugPrint("Background photo composite/save error: $e");
    }
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
                      child: RepaintBoundary(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                _baseScale = _currentZoom;
                              },
                              onScaleUpdate: (details) async {
                                if (details.pointerCount > 1) {
                                  if (_controller == null || !_controller!.value.isInitialized) return;
                                  final newZoom = (_baseScale * details.scale).clamp(_minAvailableZoom, _maxAvailableZoom);
                                  if ((newZoom - _currentZoom).abs() > 0.05) {
                                    _currentZoom = newZoom;
                                    await _controller!.setZoomLevel(_currentZoom);
                                    if (mounted) setState(() {});
                                  }
                                }
                              },
                              onTapUp: (details) => _onTapFocus(details, constraints),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CameraPreview(_controller!),
                                  if (_showGrid)
                                    const IgnorePointer(
                                      child: CustomPaint(
                                        painter: CameraGridPainter(),
                                      ),
                                    ),
                                  // Shutter curtain blade blink (natural camera optic feedback)
                                  if (_showShutterCurtain)
                                    IgnorePointer(
                                      child: Container(
                                        color: Colors.black.withValues(alpha: 0.85),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
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
            child: RepaintBoundary(
              key: _overlayCardKey,
              child: GPSOverlayCard(
                position: _currentPosition,
                address: _currentAddress,
                dateTime: _currentTimeNotifier.value,
                timeNotifier: _currentTimeNotifier,
                showMap: _showMapInOverlay,
                textColor: _overlayTextColor,
                mapStyle: _mapStyle,
              ),
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

          // 5. Top Bar (Wrapped in SafeArea)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    // Brand Badge with live GPS state (Compact & flexible to prevent overflow on startup)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.gps_fixed,
                              color: _currentPosition != null ? Colors.greenAccent : Colors.amberAccent,
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _currentPosition != null ? "GPS PRO" : "GPS...",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 0.6,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGlassButton(text: _ratioName, onTap: _cycleAspectRatio),
                        const SizedBox(width: 4),
                        _buildGlassIcon(
                          icon: _showGrid ? Icons.grid_3x3_rounded : Icons.grid_off_rounded,
                          isActive: _showGrid,
                          activeColor: Colors.cyanAccent,
                          onTap: _toggleGrid,
                        ),
                        const SizedBox(width: 4),
                        _buildGlassIcon(
                          icon: _getFlashIcon(),
                          isActive: _flashMode != FlashMode.off,
                          activeColor: Colors.amberAccent,
                          onTap: _toggleFlash,
                        ),
                        const SizedBox(width: 4),
                        _buildGlassIcon(
                          icon: Icons.flip_camera_ios_outlined,
                          isActive: false,
                          onTap: () async {
                            if (_isSwitchingCamera) return;
                            HapticFeedback.selectionClick();
                            setState(() => _isSwitchingCamera = true);
                            _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
                            await _initCamera(_cameras![_selectedCameraIndex]);
                          },
                        ),
                        const SizedBox(width: 4),
                        _buildGlassIcon(
                          icon: Icons.tune_rounded,
                          isActive: false,
                          onTap: _openSettings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. Photo Saved Notification Pill
          if (_showSavedIndicator)
            Positioned(
              top: 75,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                      SizedBox(width: 7),
                      Text(
                        "Photo Saved",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
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
                  // Gallery Button with live captured thumbnail (Direct Album Viewer)
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AlbumViewerScreen(),
                        ),
                      );
                      _loadLatestThumbnail();
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _lastCapturedThumbnail != null ? Colors.white70 : Colors.white24,
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (_lastCapturedThumbnail != null)
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _lastCapturedThumbnail != null
                            ? Image.memory(
                                _lastCapturedThumbnail!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                      ),
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
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIcon({
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive 
              ? (activeColor ?? Colors.amberAccent).withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive 
                ? (activeColor ?? Colors.amberAccent).withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? (activeColor ?? Colors.amberAccent) : Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class CameraGridPainter extends CustomPainter {
  const CameraGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.8;

    final dx = size.width / 3;
    final dy = size.height / 3;

    canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    canvas.drawLine(Offset(dx * 2, 0), Offset(dx * 2, size.height), paint);
    canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    canvas.drawLine(Offset(0, dy * 2), Offset(size.width, dy * 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}