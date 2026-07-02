// theme.dart — هوية «المصحف» منقولة حرفيًا من نسخة Expo (constants/colors.ts):
// حبر زمردي داكن على رقّ دافئ مع لمسات ذهبية.
import 'package:flutter/material.dart';

class Mushaf {
  static const background = Color(0xFFF6F1E7); // الخلفية — رقّ دافئ
  static const foreground = Color(0xFF10261D); // النص الأساسي
  static const card = Color(0xFFFFFDF8); // البطاقات
  static const primary = Color(0xFF0D7A52); // الأخضر الزمردي
  static const primaryForeground = Color(0xFFFFFDF8);
  static const secondary = Color(0xFFE3DAC4);
  static const secondaryForeground = Color(0xFF1C3B2E);
  static const muted = Color(0xFFECE4D3);
  static const mutedForeground = Color(0xFF7A7059);
  static const accent = Color(0xFFC79A3A); // الذهبي
  static const accentForeground = Color(0xFF1C1404);
  static const destructive = Color(0xFFB3372A);
  static const border = Color(0xFFDDD2BB);
  static const double radius = 14;
}

ThemeData mushafTheme() {
  const scheme = ColorScheme.light(
    primary: Mushaf.primary,
    onPrimary: Mushaf.primaryForeground,
    secondary: Mushaf.accent,
    onSecondary: Mushaf.accentForeground,
    surface: Mushaf.card,
    onSurface: Mushaf.foreground,
    error: Mushaf.destructive,
    onError: Mushaf.primaryForeground,
    outline: Mushaf.border,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Mushaf.radius),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Mushaf.background,
    dividerColor: Mushaf.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Mushaf.card,
      hintStyle: const TextStyle(color: Mushaf.mutedForeground),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Mushaf.radius),
        borderSide: const BorderSide(color: Mushaf.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Mushaf.radius),
        borderSide: const BorderSide(color: Mushaf.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Mushaf.radius),
        borderSide: const BorderSide(color: Mushaf.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Mushaf.primary,
        foregroundColor: Mushaf.primaryForeground,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Mushaf.foreground,
        side: const BorderSide(color: Mushaf.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Mushaf.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Mushaf.foreground,
      contentTextStyle: TextStyle(color: Mushaf.card),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// إطار متقطّع (لبطاقة رفع الملف) — يطابق uploadCard في نسخة Expo:
/// borderWidth 2 / dashed / radius 18.
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  const DashedBorder({
    super.key,
    required this.child,
    this.color = Mushaf.border,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
