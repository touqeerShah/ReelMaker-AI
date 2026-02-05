import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service to handle storage / media permissions consistently across Android versions.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// ✅ Used by UI: checks if permission is granted
  Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      if (sdk >= 33) {
        return (await Permission.videos.status).isGranted;
      }
      return (await Permission.storage.status).isGranted;
    }

    if (Platform.isIOS) {
      return (await Permission.photos.status).isGranted;
    }

    return true;
  }

  /// ✅ Used by UI: requests the needed permission
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      if (sdk >= 33) {
        final status = await Permission.videos.request();
        return status.isGranted;
      }
      final status = await Permission.storage.request();
      return status.isGranted;
    }

    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }

    return true;
  }

  /// ✅ Used by UI
  Future<bool> isPermissionPermanentlyDenied() async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      if (sdk >= 33) {
        return (await Permission.videos.status).isPermanentlyDenied;
      }
      return (await Permission.storage.status).isPermanentlyDenied;
    }

    if (Platform.isIOS) {
      return (await Permission.photos.status).isPermanentlyDenied;
    }

    return false;
  }

  /// ✅ Used by UI
  Future<void> openSettings() async {
    await openAppSettings();
  }

  // ---------------------------------------------------------------------------
  // ✅ Compatibility aliases for existing code
  // ---------------------------------------------------------------------------

  Future<bool> requestVideoReadPermission() => requestStoragePermission();
  Future<bool> hasVideoReadPermission() => hasStoragePermission();

  // Optional older aliases you already had
  Future<bool> hasPermission() => hasStoragePermission();
  Future<bool> requestPermission() => requestStoragePermission();
  Future<void> openAppPermissionSettings() => openSettings();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<int> _androidSdkInt() async {
    try {
      await Permission.videos.status;
      return 33;
    } catch (_) {
      return 32;
    }
  }
}
