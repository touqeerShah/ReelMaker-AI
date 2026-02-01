import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CfButton extends StatelessWidget {
  const CfButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.fullWidth = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primary.withOpacity(0.35),
        disabledForegroundColor: Colors.white.withOpacity(0.85),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: child,
    );

    if (!fullWidth) return button;

    // Makes it expand nicely in Rows/Columns when needed
    return SizedBox(width: double.infinity, child: button);
  }
}
