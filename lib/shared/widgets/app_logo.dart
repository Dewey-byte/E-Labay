import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// E-Labay brand mark: a leaf inside a rounded recycling badge.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? Colors.white : AppColors.forestGreen,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.recycling,
            size: size * 0.78,
            color: (onDark ? AppColors.forestGreen : Colors.white).withValues(alpha: 0.22),
          ),
          Icon(Icons.eco, size: size * 0.48, color: onDark ? AppColors.forestGreen : Colors.white),
        ],
      ),
    );
  }
}
