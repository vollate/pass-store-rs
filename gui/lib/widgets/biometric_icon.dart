import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../services/security_repository.dart';

/// Displays a Face ID glyph when [kind] is [BiometricKind.face], and a
/// fingerprint glyph otherwise.
class BiometricIcon extends StatelessWidget {
  const BiometricIcon({
    super.key,
    required this.kind,
    this.size,
    this.color,
  });

  final BiometricKind kind;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveSize = size ?? iconTheme.size ?? ParsSizes.icon;
    final effectiveColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    if (kind == BiometricKind.face) {
      return SizedBox.square(
        dimension: effectiveSize,
        child: CustomPaint(
          painter: _FaceIdIconPainter(color: effectiveColor),
        ),
      );
    }
    return Icon(
      Icons.fingerprint,
      size: effectiveSize,
      color: effectiveColor,
    );
  }
}

class _FaceIdIconPainter extends CustomPainter {
  const _FaceIdIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.085
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final pad = side * 0.08;
    final radius = side * 0.15;
    final arm = side * 0.28;
    final far = side - pad;

    // Four rounded corner brackets framing the face.
    final brackets =
        Path()
          // Top-left
          ..moveTo(pad, pad + arm)
          ..lineTo(pad, pad + radius)
          ..quadraticBezierTo(pad, pad, pad + radius, pad)
          ..lineTo(pad + arm, pad)
          // Top-right
          ..moveTo(far - arm, pad)
          ..lineTo(far - radius, pad)
          ..quadraticBezierTo(far, pad, far, pad + radius)
          ..lineTo(far, pad + arm)
          // Bottom-right
          ..moveTo(far, far - arm)
          ..lineTo(far, far - radius)
          ..quadraticBezierTo(far, far, far - radius, far)
          ..lineTo(far - arm, far)
          // Bottom-left
          ..moveTo(pad + arm, far)
          ..lineTo(pad + radius, far)
          ..quadraticBezierTo(pad, far, pad, far - radius)
          ..lineTo(pad, far - arm);
    canvas.drawPath(brackets, paint);

    // Eyes.
    canvas.drawLine(
      Offset(side * 0.34, side * 0.34),
      Offset(side * 0.34, side * 0.43),
      paint,
    );
    canvas.drawLine(
      Offset(side * 0.66, side * 0.34),
      Offset(side * 0.66, side * 0.43),
      paint,
    );

    // Nose.
    final nose =
        Path()
          ..moveTo(side * 0.50, side * 0.34)
          ..lineTo(side * 0.50, side * 0.52)
          ..quadraticBezierTo(
            side * 0.50,
            side * 0.56,
            side * 0.45,
            side * 0.56,
          );
    canvas.drawPath(nose, paint);

    // Smile.
    final smile =
        Path()
          ..moveTo(side * 0.35, side * 0.65)
          ..quadraticBezierTo(
            side * 0.50,
            side * 0.77,
            side * 0.65,
            side * 0.65,
          );
    canvas.drawPath(smile, paint);
  }

  @override
  bool shouldRepaint(_FaceIdIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
