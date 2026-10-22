import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/album_service.dart';
import 'editor_screen.dart';

class AlbumViewerScreen extends StatefulWidget {
  final int initialIndex;

  const AlbumViewerScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<AlbumViewerScreen> createState() => _AlbumViewerScreenState();
}

class _AlbumViewerScreenState extends State<AlbumViewerScreen> {
  final AlbumService _albumService = AlbumService.instance;
  final ImagePicker _picker = ImagePicker();

  List<File> _photos = [];
  bool _isLoading = true;
  bool _isGridView = false;
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadPhotos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    final photos = await _albumService.getCapturedPhotos();
    if (mounted) {
      setState(() {
        _photos = photos;
        _isLoading = false;
        if (_currentIndex >= _photos.length) {
          _currentIndex = _photos.isNotEmpty ? _photos.length - 1 : 0;
        }
      });
      if (_photos.isNotEmpty && _pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    }
  }

  Future<void> _importPhotoForStamping() async {
    HapticFeedback.lightImpact();
    try {
      final xfile = await _picker.pickImage(source: ImageSource.gallery);
      if (xfile != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditorScreen(
              imageFile: File(xfile.path),
              aspectRatio: 3 / 4,
            ),
          ),
        ).then((_) => _loadPhotos());
      }
    } catch (e) {
      debugPrint("Error picking photo for stamping: $e");
    }
  }

  Future<void> _shareCurrentPhoto() async {
    if (_photos.isEmpty) return;
    HapticFeedback.lightImpact();
    final file = _photos[_currentIndex];
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Captured with GPS Camera Pro',
    );
  }

  Future<void> _confirmDeleteCurrentPhoto() async {
    if (_photos.isEmpty) return;
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Photo?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "This will remove the photo from the app's album.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final fileToDelete = _photos[_currentIndex];
      await _albumService.deletePhoto(fileToDelete);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Photo removed from album"),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.black87,
        ),
      );
      await _loadPhotos();
    }
  }

  void _showPhotoInfo() {
    if (_photos.isEmpty) return;
    HapticFeedback.lightImpact();
    final file = _photos[_currentIndex];
    DateTime? modTime;
    int sizeBytes = 0;
    try {
      final stat = file.statSync();
      modTime = stat.modified;
      sizeBytes = stat.size;
    } catch (_) {}

    final dateStr = modTime != null ? DateFormat('EEEE, dd MMM yyyy • hh:mm a').format(modTime) : 'Unknown';
    final sizeStr = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Photo Details",
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _buildInfoRow(Icons.calendar_today_rounded, "Captured", dateStr),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.insert_drive_file_outlined, "File Size", "$sizeStr MB"),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.folder_outlined, "Album", "GPS Camera Pro"),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _photos.isEmpty
              ? "GPS Album"
              : _isGridView
                  ? "All Photos (${_photos.length})"
                  : "${_currentIndex + 1} of ${_photos.length}",
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // 1. Grid/Single View Toggle
          if (_photos.isNotEmpty)
            IconButton(
              icon: Icon(
                _isGridView ? Icons.photo_size_select_actual_outlined : Icons.grid_view_rounded,
                color: Colors.white,
                size: 21,
              ),
              tooltip: _isGridView ? "Full Photo" : "Album Grid",
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _isGridView = !_isGridView);
              },
            ),

          // 2. Import & Stamp existing photo from device (Explicit Separate Flow)
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.amberAccent, size: 22),
            tooltip: "Import Photo to Stamp",
            onPressed: _importPhotoForStamping,
          ),

          // 3. Open System Gallery
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 21),
            tooltip: "Open Phone Gallery",
            onPressed: () async {
              try {
                await Gal.open();
              } catch (_) {}
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amberAccent))
          : _photos.isEmpty
              ? _buildEmptyState()
              : _isGridView
                  ? _buildGridView()
                  : _buildPageView(),
      bottomNavigationBar: (!_isLoading && _photos.isNotEmpty && !_isGridView)
          ? _buildBottomBar()
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1.5),
              ),
              child: const Icon(Icons.photo_library_outlined, color: Colors.white38, size: 54),
            ),
            const SizedBox(height: 22),
            const Text(
              "No Photos in Album",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Photos captured with GPS Camera Pro will appear here automatically.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _importPhotoForStamping,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: const Text("Import & Stamp Existing Photo"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _photos.length,
      onPageChanged: (idx) {
        setState(() => _currentIndex = idx);
      },
      itemBuilder: (context, idx) {
        final photo = _photos[idx];
        return Center(
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.file(
              photo,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, idx) {
        final photo = _photos[idx];
        final isSelected = idx == _currentIndex;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _currentIndex = idx;
              _isGridView = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageController.hasClients) {
                _pageController.jumpToPage(idx);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? Colors.amberAccent : Colors.white12,
                width: isSelected ? 2.0 : 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.file(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.white10,
                  child: const Icon(Icons.broken_image, color: Colors.white24),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Share Button
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white, size: 23),
            tooltip: "Share Photo",
            onPressed: _shareCurrentPhoto,
          ),

          // Info Button
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 23),
            tooltip: "Photo Details",
            onPressed: _showPhotoInfo,
          ),

          // Delete Button
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 23),
            tooltip: "Delete",
            onPressed: _confirmDeleteCurrentPhoto,
          ),
        ],
      ),
    );
  }
}
