import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/ad_banner_widget.dart';
import 'editor_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool showMap;
  final bool isBottom;
  final Color textColor;
  final String mapStyle;

  const SettingsScreen({
    super.key,
    required this.showMap,
    required this.isBottom,
    required this.textColor,
    this.mapStyle = 'Satellite',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _showMap;
  late bool _isBottom;
  late Color _textColor;
  late String _mapStyle;

  final List<Color> _curatedColors = [
    Colors.white,
    Colors.amberAccent,
    Colors.cyanAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
  ];

  final List<Map<String, dynamic>> _availableMapStyles = [
    {'name': 'Satellite', 'icon': Icons.satellite_alt_rounded, 'desc': 'High-res aerial imagery'},
    {'name': 'Street Map', 'icon': Icons.terrain, 'desc': 'Clean vector street layout'},
    {'name': 'Voyager', 'icon': Icons.map, 'desc': 'Minimal CartoDB cartography'},
  ];

  @override
  void initState() {
    super.initState();
    _showMap = widget.showMap;
    _isBottom = widget.isBottom;
    _textColor = widget.textColor;
    _mapStyle = widget.mapStyle;
  }

  void _saveAndExit() {
    Navigator.pop(context, {
      'showMap': _showMap,
      'isBottom': _isBottom,
      'textColor': _textColor,
      'mapStyle': _mapStyle,
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          title: const Text(
            "Stamp Settings",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: _saveAndExit,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "STAMP CUSTOMIZATION",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ),
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text("Show Map Thumbnail", style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: const Text("Embeds a mini satellite/road map on photo", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: _showMap,
                    activeThumbColor: Colors.blueAccent,
                    onChanged: (val) => setState(() => _showMap = val),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  SwitchListTile(
                    title: const Text("Stamp at Bottom", style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text(
                      _isBottom ? "Positioned at bottom of photo" : "Positioned at top of photo",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    value: _isBottom,
                    activeThumbColor: Colors.blueAccent,
                    onChanged: (val) => setState(() => _isBottom = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "MAP STYLE",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ),
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: _availableMapStyles.map((style) {
                  final isSelected = _mapStyle == style['name'];
                  final isLast = _availableMapStyles.last == style;
                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            style['icon'] as IconData,
                            color: isSelected ? Colors.blueAccent : Colors.white70,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          style['name'] as String,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          style['desc'] as String,
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Colors.blueAccent, size: 22)
                            : const Icon(Icons.circle_outlined, color: Colors.white24, size: 22),
                        onTap: () => setState(() => _mapStyle = style['name'] as String),
                      ),
                      if (!isLast) const Divider(color: Colors.white10, height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "TELEMETRY TEXT COLOR",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ),
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _curatedColors.map((color) {
                    final isSelected = _textColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => setState(() => _textColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.blueAccent : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(Icons.check, color: color == Colors.white ? Colors.black : Colors.black87, size: 22)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "PHOTO UTILITIES",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ),
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_photo_alternate_rounded, color: Colors.amberAccent, size: 22),
                ),
                title: const Text("Import Photo from Device", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text("Select an existing gallery photo to add GPS watermark", style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                onTap: () async {
                  try {
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(source: ImageSource.gallery);
                    if (xfile != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditorScreen(
                            imageFile: File(xfile.path),
                            aspectRatio: 3 / 4,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint("Import error: $e");
                  }
                },
              ),
            ),

            const SizedBox(height: 32),

            Center(
              child: Column(
                children: [
                  Icon(Icons.camera_alt_outlined, color: Colors.grey.shade600, size: 32),
                  const SizedBox(height: 8),
                  const Text("GPSCam Pro", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text("Version 1.0.0", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SafeArea(child: AdBannerWidget()),
      ),
    );
  }
}