import 'package:flutter/material.dart';
import 'package:clipforge/services/permission_service.dart';

/// Dialog to request storage permissions from user
class PermissionRequestDialog extends StatelessWidget {
  final VoidCallback? onGranted;
  final VoidCallback? onDenied;

  const PermissionRequestDialog({
    Key? key,
    this.onGranted,
    this.onDenied,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_open, color: Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          const Text('Storage Permission'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This app needs access to your device storage to:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          _buildPermissionItem(
            icon: Icons.video_library,
            text: 'Read and select videos from your device',
          ),
          const SizedBox(height: 8),
          _buildPermissionItem(
            icon: Icons.save,
            text: 'Save processed video clips to your device',
          ),
          const SizedBox(height: 8),
          _buildPermissionItem(
            icon: Icons.folder,
            text: 'Create folders to organize your projects',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your files stay on your device. We never upload videos to the cloud.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onDenied?.call();
          },
          child: const Text('Not Now'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.of(context).pop();
            final permissionService = PermissionService();
            final granted = await permissionService.requestStoragePermission();
            
            if (granted) {
              onGranted?.call();
            } else {
              // Check if permanently denied
              final isPermanentlyDenied = 
                  await permissionService.isPermissionPermanentlyDenied();
              
              if (isPermanentlyDenied && context.mounted) {
                _showSettingsDialog(context);
              } else {
                onDenied?.call();
              }
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('Grant Access'),
        ),
      ],
    );
  }

  Widget _buildPermissionItem({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Storage permission is required to use this app. '
          'Please enable it in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await PermissionService().openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Widget to show permission status and request button
class PermissionStatusWidget extends StatefulWidget {
  const PermissionStatusWidget({Key? key}) : super(key: key);

  @override
  State<PermissionStatusWidget> createState() => _PermissionStatusWidgetState();
}

class _PermissionStatusWidgetState extends State<PermissionStatusWidget> {
  final _permissionService = PermissionService();
  bool _hasPermission = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    final hasPermission = await _permissionService.hasStoragePermission();
    setState(() {
      _hasPermission = hasPermission;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasPermission) {
      return Card(
        color: Colors.green.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700]),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Storage permissions granted',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange[700]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Storage permission required',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Grant storage access to read videos and save processed clips.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => PermissionRequestDialog(
                    onGranted: () {
                      _checkPermissions();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Storage permission granted'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    onDenied: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Storage permission denied'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                  ),
                );
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
