import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.assetPath,
    this.radius = 28,
    this.isSelected = false,
    super.key,
  });

  final String assetPath;
  final double radius;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 3 : 1,
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.24),
              blurRadius: 12,
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(assetPath, fit: BoxFit.cover),
    );
  }
}
