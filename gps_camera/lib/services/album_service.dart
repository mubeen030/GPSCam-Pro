import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class AlbumService {
  static final AlbumService _instance = AlbumService._internal();
  factory AlbumService() => _instance;
  static AlbumService get instance => _instance;
  AlbumService._internal();

  Directory? _photoDir;

  Future<Directory> _getPhotoDir() async {
    if (_photoDir != null && await _photoDir!.exists()) {
      return _photoDir!;
    }
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/captured_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _photoDir = dir;
    return dir;
  }

  /// Saves the composited photo to app storage and device Gallery album
  Future<File> savePhoto(Uint8List compositedBytes) async {
    final dir = await _getPhotoDir();
    final filePath = '${dir.path}/GPS_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(filePath);
    await file.writeAsBytes(compositedBytes);

    // Export to device gallery album
    try {
      await Gal.putImage(file.path, album: "GPS Camera Pro");
    } catch (e) {
      debugPrint("Gal.putImage error: $e");
    }

    return file;
  }

  /// Returns all captured photos sorted newest first
  Future<List<File>> getCapturedPhotos() async {
    try {
      final dir = await _getPhotoDir();
      final entities = dir.listSync();
      final photos = <File>[];

      for (final entity in entities) {
        if (entity is File &&
            (entity.path.endsWith('.png') ||
             entity.path.endsWith('.jpg') ||
             entity.path.endsWith('.jpeg'))) {
          photos.add(entity);
        }
      }

      photos.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return b.path.compareTo(a.path);
        }
      });

      return photos;
    } catch (e) {
      debugPrint("Error reading captured photos: $e");
      return [];
    }
  }

  /// Gets the most recent photo file
  Future<File?> getLatestPhoto() async {
    final photos = await getCapturedPhotos();
    return photos.isNotEmpty ? photos.first : null;
  }

  /// Deletes a captured photo file
  Future<bool> deletePhoto(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint("Error deleting photo: $e");
    }
    return false;
  }
}
