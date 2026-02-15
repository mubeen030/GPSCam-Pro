import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart';
import '../widgets/gps_overlay_card.dart';

class EditorScreen extends StatefulWidget {
  final File imageFile;
  final Position initialPosition;
  final Placemark? initialAddress;
  final double aspectRatio;

  const EditorScreen({
    super.key,
    required this.imageFile,
    required this.initialPosition,
    this.initialAddress,
    required this.aspectRatio,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  late DateTime _displayDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _displayDate = DateTime.now();
  }

  Future<void> _pickDateTime() async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: _displayDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (date == null) return;

    TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_displayDate),
    );
    if (time == null) return;

    setState(() {
      _displayDate = DateTime(
        date.year, date.month, date.day, time.hour, time.minute
      );
    });
  }

  Future<String?> _generateImage() async {
    try {
      final directory = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
      
      // Capture the exact widget look
      return await _screenshotController.captureAndSave(
        directory.path,
        fileName: fileName,
        pixelRatio: 3.0, 
      );
    } catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }

  Future<void> _saveImage() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final path = await _generateImage();
    if (path != null) {
      await Gal.putImage(path, album: "GPS Camera Pro");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Saved to Gallery!"), backgroundColor: Colors.green),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _shareImage() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final path = await _generateImage();
    if (path != null) {
      await Share.shareXFiles([XFile(path)], text: " captured with GPS Camera Pro");
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Edit & Share", style: TextStyle(color: Colors.white)),
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar, color: Colors.white),
            onPressed: _pickDateTime,
            tooltip: "Change Date/Time",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Screenshot(
                controller: _screenshotController,
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          widget.imageFile,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: GPSOverlayCard(
                              position: widget.initialPosition,
                              address: widget.initialAddress,
                              dateTime: _displayDate,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _shareImage,
                    icon: const Icon(Icons.share),
                    label: const Text("Share"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveImage,
                    icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Icon(Icons.download),
                    label: Text(_isLoading ? "Saving..." : "Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}