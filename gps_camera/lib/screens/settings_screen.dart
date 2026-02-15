import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final bool showMap;
  final bool isBottom;
  final Color textColor;

  const SettingsScreen({
    super.key,
    required this.showMap,
    required this.isBottom,
    required this.textColor,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _showMap;
  late bool _isBottom;
  late Color _textColor;

  @override
  void initState() {
    super.initState();
    _showMap = widget.showMap;
    _isBottom = widget.isBottom;
    _textColor = widget.textColor;
  }

  void _saveAndExit() {
    Navigator.pop(context, {
      'showMap': _showMap,
      'isBottom': _isBottom,
      'textColor': _textColor,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saveAndExit,
        ),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text("Show Map Thumbnail"),
            value: _showMap,
            onChanged: (val) => setState(() => _showMap = val),
          ),
          SwitchListTile(
            title: const Text("Overlay at Bottom"),
            subtitle: const Text("Show GPS info at bottom of photo"),
            value: _isBottom,
            onChanged: (val) => setState(() => _isBottom = val),
          ),
          ListTile(
            title: const Text("Text Color"),
            trailing: CircleAvatar(backgroundColor: _textColor, radius: 15),
            onTap: () {
              // Simple toggler for demo purposes
              setState(() {
                _textColor = _textColor == Colors.white ? Colors.yellow : Colors.white;
              });
            },
          ),
        ],
      ),
    );
  }
}