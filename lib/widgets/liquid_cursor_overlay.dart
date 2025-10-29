import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class LiquidCursorOverlay extends StatefulWidget {
  const LiquidCursorOverlay({super.key});

  @override
  State<LiquidCursorOverlay> createState() => _LiquidCursorOverlayState();
}

class _LiquidCursorOverlayState extends State<LiquidCursorOverlay>
    with SingleTickerProviderStateMixin {
  Offset _position = Offset.zero;
  Offset _target = Offset.zero;
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..addListener(
        () => setState(() {
          final lerp = Curves.easeOut.transform(_controller.value);
          _position = Offset.lerp(_position, _target, lerp) ?? _target;
        }),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        (defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.linux &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return const SizedBox.shrink();
    }
    final accent = Theme.of(context).colorScheme.primary;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _moveTo(e.position),
      onPointerMove: (e) => _moveTo(e.position),
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: _position.dx - 14,
              top: _position.dy - 14,
              child: _LiquidOrb(color: accent),
            ),
          ],
        ),
      ),
    );
  }

  void _moveTo(Offset p) {
    _target = p;
    if (!_controller.isAnimating) {
      _controller
        ..reset()
        ..forward();
    }
  }
}

class _LiquidOrb extends StatelessWidget {
  const _LiquidOrb({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OCLiquidGlassGroup(
      settings: OCLiquidGlassSettings(
        refractStrength: -0.12,
        blurRadiusPx: 3.0,
        specStrength: 1.0,
        lightbandColor: Colors.white.withOpacity(0.9),
      ),
      child: OCLiquidGlass(
        width: 28,
        height: 28,
        borderRadius: 14,
        color: color.withOpacity(0.25),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.55),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
