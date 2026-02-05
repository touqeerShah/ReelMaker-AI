import 'dart:io';

import 'package:gal/gal.dart';

import 'permission_service.dart';

class GalleryExportService {
  static final GalleryExportService _instance =
      GalleryExportService._internal();
  factory GalleryExportService() => _instance;
  GalleryExportService._internal();

  /// Try to save a processed video to device gallery (non-fatal on failure).
  Future<bool> saveVideoToGallery(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return false;

      final permissionService = PermissionService();
      final granted = await permissionService.requestStoragePermission();
      if (!granted) return false;

      await Gal.putVideo(videoPath, album: 'ClipForge');
      return true;
    } catch (_) {
      return false;
    }
  }
}
