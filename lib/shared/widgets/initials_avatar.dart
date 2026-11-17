import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Circular avatar showing a network image or the name's initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.color = AppColors.forestGreen,
    this.icon,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color color;
  final IconData? icon;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.5)
          : Text(
              initialsOf(name),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
              ),
            ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.tint(color, 0.14), shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? fallback
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
