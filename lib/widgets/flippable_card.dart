import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Çift yüzlü (flippable) kart widget'ı
/// Tap ettiğinde ön ve arka yüz arasında geçiş yapar
/// Front: kronolojik yaşa göre persentil (genelde sabit)
/// Back: boy yaşına göre persentil (flippable)
class FlippableCard extends StatefulWidget {
  final Widget frontChild;
  final Widget backChild;
  final ValueChanged<bool>? onSideChanged;
  final bool initialIsFront;

  const FlippableCard({
    Key? key,
    required this.frontChild,
    required this.backChild,
    this.onSideChanged,
    this.initialIsFront = true,
  }) : super(key: key);

  @override
  State<FlippableCard> createState() => _FlippableCardState();
}

class _FlippableCardState extends State<FlippableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  late bool _isFront;

  @override
  void initState() {
    super.initState();
    _isFront = widget.initialIsFront;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    if (!_isFront) {
      _controller.value = 1;
    }
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    _controller.addStatusListener(_handleAnimationStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSideChanged?.call(_isFront);
    });
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onSideChanged?.call(false);
    } else if (status == AnimationStatus.dismissed) {
      widget.onSideChanged?.call(true);
    }
  }

  void _toggleFlip() {
    if (_controller.isAnimating) return;
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    setState(() {
      _isFront = !_isFront;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleFlip,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              // 3D döndürme efekti
              final progress = _animation.value;
              final rotationAngle = progress * math.pi;
              final isBackVisible = progress > 0.5;
              final tilt = 0.08 * math.sin(rotationAngle);

              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015) // Perspektif derinliği
                  ..rotateX(tilt)
                  ..rotateY(rotationAngle),
                child: isBackVisible
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: widget.backChild,
                      )
                    : widget.frontChild,
              );
            },
          ),
          // "Çevirmek için tıkla" yazısı - ortada, altında
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'Çevirmek için tıkla',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek yüzlü (non-flippable) kart widget'ı
class SingleSideCard extends StatelessWidget {
  final Widget child;

  const SingleSideCard({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
