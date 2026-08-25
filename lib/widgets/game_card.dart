import 'package:flutter/material.dart';

class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.color,
    required this.width,
    required this.height,
    this.elevation = 0,
    this.shadowElevation = 0,
  });

  final Color color;
  final double width;
  final double height;
  final double elevation;
  final double shadowElevation;

  @override
  Widget build(BuildContext context) {
    final shadow = elevation + shadowElevation;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD3D3D3), width: 1),
        boxShadow: shadow > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: shadow,
                  offset: Offset(0, shadow * 0.5),
                ),
              ]
            : null,
      ),
    );
  }
}
