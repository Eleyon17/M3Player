import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class WigglingProgressBar extends StatefulWidget {
  final double value;
  final double max;
  final bool isPlaying;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  const WigglingProgressBar({
    Key? key,
    required this.value,
    required this.max,
    required this.isPlaying,
    this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  }) : super(key: key);

  @override
  _WigglingProgressBarState createState() => _WigglingProgressBarState();
}

class _WigglingProgressBarState extends State<WigglingProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _amplitude = 0.0;
  Timer? _amplitudeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    if (widget.isPlaying) {
      _controller.repeat();
      _amplitude = 4.0;
    }
  }

  @override
  void didUpdateWidget(covariant WigglingProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
        _animateAmplitude(4.0);
      } else {
        _animateAmplitude(0.0);
      }
    }
  }
  
  void _animateAmplitude(double target) {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if ((_amplitude - target).abs() < 0.2) {
          _amplitude = target;
          timer.cancel();
          if (target == 0.0) _controller.stop();
        } else {
          _amplitude += (target - _amplitude) * 0.1;
        }
      });
    });
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleDrag(Offset localPosition, BoxConstraints constraints) {
    double percent = localPosition.dx / constraints.maxWidth;
    percent = percent.clamp(0.0, 1.0);
    if (widget.onChanged != null) {
      widget.onChanged!(percent * widget.max);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => _handleDrag(details.localPosition, constraints),
          onHorizontalDragUpdate: (details) => _handleDrag(details.localPosition, constraints),
          onHorizontalDragEnd: (details) {
             if (widget.onChangeEnd != null) {
                // We use the current value to seek since update already changed it
                widget.onChangeEnd!(widget.value);
             }
          },
          onTapDown: (details) => _handleDrag(details.localPosition, constraints),
          onTapUp: (details) {
            if (widget.onChangeEnd != null) widget.onChangeEnd!(widget.value);
          },
          child: SizedBox(
            height: 40,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _WigglePainter(
                    progress: widget.max > 0 ? (widget.value / widget.max).clamp(0.0, 1.0) : 0.0,
                    animationValue: _controller.value,
                    amplitude: _amplitude,
                    activeColor: widget.activeColor ?? Theme.of(context).colorScheme.primary,
                    inactiveColor: widget.inactiveColor ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                    thumbColor: widget.thumbColor ?? Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WigglePainter extends CustomPainter {
  final double progress;
  final double animationValue;
  final double amplitude;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;

  _WigglePainter({
    required this.progress,
    required this.animationValue,
    required this.amplitude,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final activeWidth = size.width * progress;

    // Draw active wiggling line
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, centerY);
    
    // Smooth transition from wiggle to straight line near the thumb and at the start
    for (double x = 0; x <= activeWidth; x++) {
      // Fade out amplitude as it gets close to thumb and at the start
      final distanceToThumb = activeWidth - x;
      final distanceToStart = x;
      
      double localAmp = amplitude;
      if (distanceToThumb < 20) localAmp *= (distanceToThumb / 20);
      if (distanceToStart < 20) localAmp *= (distanceToStart / 20);
      
      final y = centerY + math.sin((x / 15) - (animationValue * math.pi * 2)) * localAmp;
      path.lineTo(x, y);
    }
    
    if (activeWidth > 2.0) {
      canvas.drawPath(path, activePaint);
    }

    // Draw inactive straight line
    if (activeWidth < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(activeWidth, centerY), Offset(size.width, centerY), inactivePaint);
    }

    // Draw thumb
    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(activeWidth, centerY), 8.0, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _WigglePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
