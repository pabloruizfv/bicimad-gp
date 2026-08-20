import 'package:flutter/material.dart';

class MetricPill extends StatelessWidget {
  const MetricPill({
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.maxWidth,
    this.maxLines = 1,
    this.dense = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double? maxWidth;
  final int maxLines;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colorScheme.onSecondaryContainer;

    final labelWidget = Text(
      label,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w800,
      ),
    );

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.secondaryContainer,
        border: Border.all(color: borderColor ?? colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: dense ? 3 : 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
            ],
            if (maxWidth == null) labelWidget else Flexible(child: labelWidget),
          ],
        ),
      ),
    );

    if (maxWidth == null) {
      return pill;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: pill,
    );
  }
}
