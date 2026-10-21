import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<Color?> showColorWheelDialog(
  BuildContext context,
  Color initial,
) => showDialog<Color>(
  context: context,
  builder: (context) => _ColorWheelDialog(initial: initial),
);

class _ColorWheelDialog extends StatefulWidget {
  const _ColorWheelDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _update(double hue, double saturation) {
    setState(() {
      _hsv = HSVColor.fromAHSV(1, hue, saturation, _hsv.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    return AlertDialog(
      title: const Text('Choose colour'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _ColorWheel(
                hsv: _hsv,
                onChanged: _update,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('#$hex'),
                const Spacer(),
                const Icon(Icons.brightness_6_outlined, size: 20),
              ],
            ),
            Slider(
              value: _hsv.value,
              onChanged: (value) => setState(() {
                _hsv = _hsv.withValue(value);
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ColorWheel extends StatelessWidget {
  const _ColorWheel({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double hue, double saturation) onChanged;

  void _update(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final delta = local - center;
    final distance = delta.distance.clamp(0.0, radius);
    final angle = math.atan2(delta.dy, delta.dx);
    var hue = angle * 180 / math.pi;
    if (hue < 0) hue += 360;
    onChanged(hue, distance / radius);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (details) => _update(details.localPosition, size),
          onPanUpdate: (details) => _update(details.localPosition, size),
          child: CustomPaint(
            painter: _ColorWheelPainter(hsv),
            size: size,
          ),
        );
      },
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = SweepGradient(
      colors: [
        for (var hue = 0; hue < 360; hue += 60)
          HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
        HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
      ],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = sweep);
    final radial = RadialGradient(
      colors: [
        Colors.white,
        Colors.white.withValues(alpha: 0),
      ],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = radial);
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }
    final angle = hsv.hue * math.pi / 180;
    final marker = center +
        Offset(
          math.cos(angle) * hsv.saturation * radius,
          math.sin(angle) * hsv.saturation * radius,
        );
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ColorWheelPainter oldDelegate) => oldDelegate.hsv != hsv;
}
