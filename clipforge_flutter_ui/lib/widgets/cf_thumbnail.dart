import 'package:flutter/material.dart';
import 'dart:io';

import '../services/local_backend_api.dart';

class CfThumbnail extends StatelessWidget {
  const CfThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.overlayIcon,
    this.badge,
    this.opacity = 1,
  });

  final String url;
  final double? width;
  final double? height;
  final double borderRadius;
  final Widget? overlayIcon;
  final Widget? badge;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: opacity,
              child: _buildImage(),
            ),
            if (overlayIcon != null)
              Container(
                color: Colors.black.withOpacity(0.25),
                alignment: Alignment.center,
                child: overlayIcon,
              ),
            if (badge != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: badge!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (url.trim().isEmpty) {
      return _fallback();
    }

    final resolved = LocalBackendAPI().resolveMediaUrl(url);
    if (!_isImagePath(resolved)) {
      return _fallback();
    }

    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return Image.network(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return _fallback();
        },
      );
    }

    if (resolved.startsWith('/') || resolved.startsWith('file://')) {
      final path =
          resolved.startsWith('file://') ? resolved.substring(7) : resolved;
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return _fallback();
        },
      );
    }

    return Image.network(
      resolved,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) {
        return _fallback();
      },
    );
  }

  bool _isImagePath(String value) {
    final lower = value.toLowerCase();
    final parsed = Uri.tryParse(lower);
    final path = parsed?.path ?? lower;
    const exts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
    return exts.any(path.endsWith);
  }

  Widget _fallback() {
    return Container(
      color: Colors.black.withOpacity(0.25),
      alignment: Alignment.center,
      child: const Icon(Icons.videocam, size: 24),
    );
  }
}
