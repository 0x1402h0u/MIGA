import 'package:flutter/material.dart';

import '../models/card.dart';

class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    required this.width,
    required this.height,
    this.reveal = false,
  });

  final CardData card;
  final double width;
  final double height;
  final bool reveal;

  static const _baseHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    final s = height / _baseHeight;
    final textColor = Colors.black87;

    final face = Stack(
      clipBehavior: Clip.none,
      children: [
        // cost badge (top-right corner)
        Positioned(
          top: 6 * s,
          right: 6 * s,
          child: Container(
            width: 17 * s,
            height: 17 * s,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: textColor.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(2 * s),
                child: Text(
                  card.costText ?? '${card.cost}',
                  style: TextStyle(
                    fontSize: 9 * s,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        // name chip（与费用角标平行、水平居中）
        Positioned(
          top: 6 * s,
          left: 6 * s,
          right: 24 * s,
          child: Center(
            child: _LabelChip(
              child: Text(
                card.name,
                style: TextStyle(
                  fontSize: 11 * s,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        // skills（中间，自动换行，最多 3 行，避免吞字）
        Positioned(
          left: 6 * s,
          right: 6 * s,
          top: 30 * s,
          bottom: 30 * s,
          child: Align(
            alignment: Alignment.center,
            child: Text(
              card.skills.join('、'),
              style: TextStyle(
                fontSize: 7.5 * s,
                color: textColor.withValues(alpha: 0.8),
                height: 1.25,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // 底部数值（抬高 + 两个小背景）
        Positioned(
          left: 6 * s,
          right: 6 * s,
          bottom: 6 * s,
          child: Row(
            children: [
              Expanded(
                child: _StatBadge(
                  icon: Icons.bolt,
                  value: card.attackText ?? '${card.attack}',
                  scale: s,
                ),
              ),
              SizedBox(width: 4 * s),
              Expanded(
                child: _StatBadge(
                  icon: Icons.favorite,
                  value: card.healthText ?? '${card.health}',
                  scale: s,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!reveal) return face;
    return _CardFaceReveal(child: face);
  }
}

/// 带小背景的圆角标签（用于卡牌名称）
class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }
}

class _CardFaceReveal extends StatefulWidget {
  const _CardFaceReveal({required this.child});

  final Widget child;

  @override
  State<_CardFaceReveal> createState() => _CardFaceRevealState();
}

class _CardFaceRevealState extends State<_CardFaceReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      )..forward();
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.value,
    required this.scale,
  });

  final IconData icon;
  final String value;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 2 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5 * scale),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 10 * scale, color: Colors.black54),
          SizedBox(width: 2 * scale),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
