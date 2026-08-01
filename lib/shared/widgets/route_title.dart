import 'package:flutter/material.dart';

class RouteTitle extends StatelessWidget {
  const RouteTitle({
    required this.origin,
    required this.destination,
    this.style,
    super.key,
  });

  final String origin;
  final String destination;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$origin → $destination',
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
