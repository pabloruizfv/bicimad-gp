import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.assetPath,
    this.radius = 28,
    this.isSelected = false,
    this.emphasizeSelection = false,
    this.borderColor,
    this.borderWidth = 1,
    super.key,
  });

  final String assetPath;
  final double radius;
  final bool isSelected;
  final bool emphasizeSelection;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBorderWidth = borderColor == null || isSelected
        ? 0.0
        : borderWidth.clamp(0.0, radius).toDouble();
    return AnimatedScale(
      scale: isSelected && emphasizeSelection ? 1.06 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                padding: EdgeInsets.all(effectiveBorderWidth),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? null : borderColor,
                ),
                child: ClipOval(
                  child: SizedBox.expand(
                    child: Image.asset(assetPath, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                left: -5,
                top: -5,
                right: -5,
                bottom: -5,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.primary, width: 5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
