import 'package:flutter/material.dart';

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
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) {
                  return Container(
                    color: Colors.black.withOpacity(0.25),
                    alignment: Alignment.center,
                    child: const Icon(Icons.videocam, size: 24),
                  );
                },
              ),
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
}
