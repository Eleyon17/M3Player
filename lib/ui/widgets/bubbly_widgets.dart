import 'package:flutter/material.dart';

class BubblyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color;
  final double padding;
  final bool noShadow;

  const BubblyButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.color,
    this.padding = 16.0,
    this.noShadow = false,
  }) : super(key: key);

  @override
  State<BubblyButton> createState() => _BubblyButtonState();
}

class _BubblyButtonState extends State<BubblyButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null) {
      _controller.reverse();
      widget.onPressed!();
    }
  }

  void _onTapCancel() {
    if (widget.onPressed != null) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          padding: EdgeInsets.all(widget.padding),
          decoration: BoxDecoration(
            color: widget.color ?? Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class BubblyIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? iconColor;
  final double size;
  final bool noShadow;

  const BubblyIconButton({
    Key? key,
    this.icon,
    this.customIcon,
    this.onPressed,
    this.color,
    this.iconColor,
    this.size = 24.0,
    this.noShadow = false,
  }) : assert(icon != null || customIcon != null),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    return BubblyButton(
      onPressed: onPressed,
      color: color ?? Colors.transparent,
      padding: 12.0,
      noShadow: noShadow,
      child: customIcon ?? Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.onSurface, size: size),
    );
  }
}

class HollowPlayIcon extends StatelessWidget {
  final double size;
  final Color color;
  const HollowPlayIcon({Key? key, required this.size, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _HollowPlayPainter(color: color),
    );
  }
}

class _HollowPlayPainter extends CustomPainter {
  final Color color;
  _HollowPlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.35, size.height * 0.25);
    path.lineTo(size.width * 0.75, size.height * 0.5);
    path.lineTo(size.width * 0.35, size.height * 0.75);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HollowPauseIcon extends StatelessWidget {
  final double size;
  final Color color;
  const HollowPauseIcon({Key? key, required this.size, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _HollowPausePainter(color: color),
    );
  }
}

class _HollowPausePainter extends CustomPainter {
  final Color color;
  _HollowPausePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.addRect(Rect.fromLTRB(size.width * 0.3, size.height * 0.25, size.width * 0.45, size.height * 0.75));
    path.addRect(Rect.fromLTRB(size.width * 0.55, size.height * 0.25, size.width * 0.7, size.height * 0.75));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
