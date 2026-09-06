import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HeadToHeadIcon extends StatelessWidget {
  const HeadToHeadIcon({
    this.width = 44,
    this.height = 24,
    this.semanticLabel = 'Cara a cara',
    super.key,
  });

  static const assetPath = 'assets/bases/head_to_head_base.svg';

  final double width;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: SvgPicture.asset(
        assetPath,
        key: const ValueKey('head-to-head-svg'),
        width: width,
        height: height,
        fit: BoxFit.contain,
        semanticsLabel: semanticLabel,
      ),
    );
  }
}
