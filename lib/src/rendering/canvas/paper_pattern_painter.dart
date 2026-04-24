import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Painter to draw paper patterns on the canvas
class PaperPatternPainter extends CustomPainter {
  final String paperType;
  final Color backgroundColor;
  final double scale;

  PaperPatternPainter({
    required this.paperType,
    required this.backgroundColor,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 🛡️ Protect from too large dimensions (max 200k x 200k)
    final safeSize = Size(
      size.width.clamp(0, 200000),
      size.height.clamp(0, 200000),
    );

    // Draw lo sfondo
    canvas.drawRect(
      Rect.fromLTWH(0, 0, safeSize.width, safeSize.height),
      Paint()..color = backgroundColor,
    );

    // Draw il pattern based onl tipo
    switch (paperType) {
      case 'blank':
        // Nessun pattern, solo sfondo
        break;
      case 'grid_5mm':
        _drawGrid(canvas, safeSize, 0.5 * scale); // 5mm reali
        break;
      case 'grid_1cm':
        _drawGrid(canvas, safeSize, 1.0 * scale); // 1cm reale
        break;
      case 'grid_2cm':
        _drawGrid(canvas, safeSize, 2.0 * scale); // 2cm reali
        break;
      case 'lines':
        _drawLines(
          canvas,
          safeSize,
          1.2 * scale,
        ); // ~12mm (righe larghe, stile college)
        break;
      case 'lines_narrow':
        _drawLines(
          canvas,
          safeSize,
          0.8 * scale,
        ); // ~8mm (righe strette, stile A4)
        break;
      case 'dots':
        _drawDots(canvas, safeSize, 1.0 * scale); // Dots every 1cm
        break;
      case 'dots_dense':
        _drawDots(canvas, safeSize, 0.5 * scale); // Dense dots every 5mm
        break;
      case 'graph':
        _drawGraphPaper(
          canvas,
          safeSize,
          1.0 * scale,
        ); // Griglia principale 1cm
        break;
      case 'hex':
        _drawHexGrid(canvas, safeSize, 1.5 * scale); // Esagoni ~15mm
        break;
      case 'isometric':
        _drawIsometricGrid(canvas, safeSize, 1.5 * scale); // Isometrica ~15mm
        break;
      case 'music':
        _drawMusicStaff(canvas, safeSize);
        break;
      case 'cornell':
        _drawCornellNotes(canvas, safeSize);
        break;
      case 'storyboard':
        _drawStoryboard(canvas, safeSize);
        break;
      case 'planner':
        _drawPlanner(canvas, safeSize);
        break;
      case 'calligraphy':
        _drawCalligraphy(canvas, safeSize);
        break;
      case 'dot_grid':
        _drawDotGrid(canvas, safeSize);
        break;
    }
  }

  /// Draws a grid of squares
  void _drawGrid(Canvas canvas, Size size, double gridSize) {
    final maxLines = 2000;
    final verticalLines = (size.width / gridSize).ceil().clamp(0, maxLines);
    final horizontalLines = (size.height / gridSize).ceil().clamp(0, maxLines);

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.3)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

    // Linee verticali — skip i=0 to avoid doppia linea ai bordi tile
    for (int i = 1; i < verticalLines; i++) {
      final x = i * gridSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Linee orizzontali — skip i=0 to avoid doppia linea ai bordi tile
    for (int i = 1; i < horizontalLines; i++) {
      final y = i * gridSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  /// Draws horizontal lines
  void _drawLines(Canvas canvas, Size size, double lineSpacing) {
    final maxLines = 2000;
    final totalLines = (size.height / lineSpacing).ceil().clamp(0, maxLines);

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.4)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    for (int i = 1; i < totalLines; i++) {
      final y = i * lineSpacing;
      if (y >= size.height) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  /// Draws dots
  void _drawDots(Canvas canvas, Size size, double dotSpacing) {
    // 🛡️ Limit max dots to avoid crash
    final maxDotsX = 1000;
    final maxDotsY = 1000;
    final dotsX = (size.width / dotSpacing).ceil().clamp(0, maxDotsX);
    final dotsY = (size.height / dotSpacing).ceil().clamp(0, maxDotsY);

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.4)
          ..style = PaintingStyle.fill;

    final dotRadius = 0.04 * scale; // ~1.5px a scala 37.8 (dots realistici)

    for (int i = 1; i <= dotsX; i++) {
      final x = i * dotSpacing;
      if (x >= size.width) break;
      for (int j = 1; j <= dotsY; j++) {
        final y = j * dotSpacing;
        if (y >= size.height) break;
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  /// Draws graph paper (main grid + sub-grid)
  void _drawGraphPaper(Canvas canvas, Size size, double mainGridSize) {
    final maxLines = 2000;

    // Sub-griglia more chiara (ogni mm)
    final subPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.15)
          ..strokeWidth = 0.3
          ..style = PaintingStyle.stroke;

    final subGridSize = mainGridSize / 10;

    final subLinesX = (size.width / subGridSize).ceil().clamp(0, maxLines);
    final subLinesY = (size.height / subGridSize).ceil().clamp(0, maxLines);

    for (int i = 1; i < subLinesX; i++) {
      final x = i * subGridSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), subPaint);
    }
    for (int i = 1; i < subLinesY; i++) {
      final y = i * subGridSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), subPaint);
    }

    // Griglia principale (ogni cm)
    final mainPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.4)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

    final mainLinesX = (size.width / mainGridSize).ceil().clamp(0, maxLines);
    final mainLinesY = (size.height / mainGridSize).ceil().clamp(0, maxLines);

    for (int i = 1; i < mainLinesX; i++) {
      final x = i * mainGridSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mainPaint);
    }
    for (int i = 1; i < mainLinesY; i++) {
      final y = i * mainGridSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), mainPaint);
    }
  }

  /// Draws a hexagonal grid
  void _drawHexGrid(Canvas canvas, Size size, double hexSize) {
    // 🛡️ Limit max hexagons to avoid crash
    final maxHexagons = 5000; // Totale esagoni massimi

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.3)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

    final hexWidth = hexSize * math.sqrt(3);
    final hexHeight = hexSize * 2;

    int hexCount = 0;

    for (
      double y = 0;
      y < size.height + hexHeight && hexCount < maxHexagons;
      y += hexHeight * 0.75
    ) {
      for (
        double x = 0;
        x < size.width + hexWidth && hexCount < maxHexagons;
        x += hexWidth
      ) {
        final offsetX =
            (y / (hexHeight * 0.75)).floor() % 2 == 0 ? 0.0 : hexWidth / 2;
        _drawHexagon(canvas, Offset(x + offsetX, y), hexSize, paint);
        hexCount++;
      }
    }
  }

  /// Draws un a hexagon
  void _drawHexagon(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i;
      final x = center.dx + size * math.cos(angle);
      final y = center.dy + size * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Draws an isometric grid
  void _drawIsometricGrid(Canvas canvas, Size size, double gridSize) {
    // 🛡️ Limit max lines to avoid crash
    final maxLines = 2000;

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.3)
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke;

    final angle1 = math.pi / 6; // 30 gradi
    final angle2 = -math.pi / 6; // -30 gradi

    // Diagonal lines to the right (30°) - limited
    int lineCount = 0;
    for (
      double start = -size.height;
      start < size.width && lineCount < maxLines;
      start += gridSize
    ) {
      final startPoint = Offset(start, 0);
      final endX = start + size.height * math.tan(angle1);
      final endPoint = Offset(endX, size.height);
      canvas.drawLine(startPoint, endPoint, paint);
      lineCount++;
    }

    // Linee diagonali verso sinistra (-30°) - limitate
    lineCount = 0;
    for (
      double start = 0;
      start < size.width + size.height && lineCount < maxLines;
      start += gridSize
    ) {
      final startPoint = Offset(start, 0);
      final endX = start + size.height * math.tan(angle2);
      final endPoint = Offset(endX, size.height);
      canvas.drawLine(startPoint, endPoint, paint);
      lineCount++;
    }

    // Linee verticali - limitate
    final verticalLines = (size.width / gridSize).ceil().clamp(0, maxLines);
    for (int i = 0; i <= verticalLines; i++) {
      final x = i * gridSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  /// Draws music staff
  void _drawMusicStaff(Canvas canvas, Size size) {
    final maxStaffs = 100;

    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.6)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    // Layout proporzionale alla size of the tile
    // Each pentagramma occupa ~12% dell'altezza, spaziato ogni ~16%
    final staffHeight = size.height * 0.10; // 10% of the tile per 5 linee
    final lineSpacing = staffHeight / 4; // 5 linee = 4 spazi
    final staffSpacing = size.height * 0.16; // 16% of the tile tra pentagrammi
    final topMargin = size.height * 0.05; // 5% margine superiore

    int staffCount = 0;
    for (
      double startY = topMargin;
      startY + staffHeight < size.height && staffCount < maxStaffs;
      startY += staffSpacing
    ) {
      // Draw le 5 linee del pentagramma
      for (int i = 0; i < 5; i++) {
        final y = startY + (i * lineSpacing);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }

      // Barre verticali (battuta iniziale e finale)
      final barPaint =
          Paint()
            ..color = _getPatternColor().withValues(alpha: 0.4)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      // Barline sinistra
      final barLeft = size.width * 0.015;
      canvas.drawLine(
        Offset(barLeft, startY),
        Offset(barLeft, startY + staffHeight),
        barPaint,
      );

      // Right barline (closing)
      final barRight = size.width * 0.985;
      canvas.drawLine(
        Offset(barRight, startY),
        Offset(barRight, startY + staffHeight),
        barPaint,
      );

      staffCount++;
    }
  }

  /// Draws Cornell Notes layout
  /// Struttura: margine sinistro (cue column) + divisore orizzontale a ~70%
  void _drawCornellNotes(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.35)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;

    final lightPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.2)
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke;

    // Cue column (left column for keywords) — ~25% of the width
    final cueWidth = size.width * 0.25;
    canvas.drawLine(
      Offset(cueWidth, 0),
      Offset(cueWidth, size.height * 0.70),
      paint,
    );

    // Divisore orizzontale a ~70% (separa notes da summary)
    final summaryY = size.height * 0.70;
    canvas.drawLine(Offset(0, summaryY), Offset(size.width, summaryY), paint);

    // Thin lines in the main area (note-taking area)
    final lineSpacing = 25.0 * scale;
    final maxLines = 200;
    int lineCount = 0;
    for (
      double y = lineSpacing;
      y < summaryY && lineCount < maxLines;
      y += lineSpacing
    ) {
      canvas.drawLine(
        Offset(cueWidth + 8, y),
        Offset(size.width - 8, y),
        lightPaint,
      );
      lineCount++;
    }

    // Lines in the summary area
    lineCount = 0;
    for (
      double y = summaryY + lineSpacing;
      y < size.height && lineCount < maxLines;
      y += lineSpacing
    ) {
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), lightPaint);
      lineCount++;
    }

    // Watermark labels
    final labelColor = _getPatternColor().withValues(alpha: 0.08);
    final labelStyle = TextStyle(
      color: labelColor,
      fontSize: size.height * 0.018,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.0,
    );

    // Label "CUES"
    _drawWatermarkLabel(
      canvas,
      'CUES',
      Offset(cueWidth * 0.12, size.height * 0.02),
      labelStyle,
    );

    // Label "NOTES"
    _drawWatermarkLabel(
      canvas,
      'NOTES',
      Offset(cueWidth + size.width * 0.02, size.height * 0.02),
      labelStyle,
    );

    // Label "SUMMARY"
    _drawWatermarkLabel(
      canvas,
      'SUMMARY',
      Offset(size.width * 0.02, summaryY + size.height * 0.01),
      labelStyle,
    );
  }

  /// Helper per disegnare label watermark
  void _drawWatermarkLabel(
    Canvas canvas,
    String text,
    Offset position,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, position);
  }

  /// Draws Storyboard layout (2×3 grid of frames)
  void _drawStoryboard(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.35)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

    final lightPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.15)
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke;

    const cols = 2;
    const rows = 3;
    // Layout proporzionale alla size of the tile
    final margin = size.width * 0.03; // 3% margine
    final gutterX = size.width * 0.02; // 2% gutter orizzontale
    final gutterY = size.height * 0.035; // 3.5% gutter verticale
    final actionLineHeight = size.height * 0.015; // 1.5% per action line

    final frameWidth = (size.width - margin * 2 - gutterX * (cols - 1)) / cols;
    final frameHeight =
        (size.height - margin * 2 - gutterY * (rows - 1)) / rows -
        actionLineHeight;

    if (frameWidth <= 0 || frameHeight <= 0) return;

    final radius = Radius.circular(size.width * 0.006);
    final maxFrames = 50;
    int frameCount = 0;

    for (int row = 0; row < rows && frameCount < maxFrames; row++) {
      for (int col = 0; col < cols && frameCount < maxFrames; col++) {
        final x = margin + col * (frameWidth + gutterX);
        final y = margin + row * (frameHeight + actionLineHeight + gutterY);

        // Frame rettangolare con angoli arrotondati
        final frameRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, frameWidth, frameHeight),
          radius,
        );
        canvas.drawRRect(frameRect, paint);

        // Crosshair al centro
        final cx = x + frameWidth / 2;
        final cy = y + frameHeight / 2;
        final chSize = size.width * 0.012;
        canvas.drawLine(
          Offset(cx - chSize, cy),
          Offset(cx + chSize, cy),
          lightPaint,
        );
        canvas.drawLine(
          Offset(cx, cy - chSize),
          Offset(cx, cy + chSize),
          lightPaint,
        );

        // Line for action/description below the frame
        final actionY = y + frameHeight + size.height * 0.008;
        canvas.drawLine(
          Offset(x, actionY),
          Offset(x + frameWidth, actionY),
          lightPaint,
        );

        frameCount++;
      }
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // NUOVI PATTERN: Planner, Calligraphy, DotGrid
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Draws weekly grid (planner/agenda)
  void _drawPlanner(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.3)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    final lightPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.15)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

    const cols = 7; // Days of the week
    final headerHeight = size.height * 0.08; // 8% per header
    final colWidth = size.width / cols;

    // Header row
    canvas.drawLine(
      Offset(0, headerHeight),
      Offset(size.width, headerHeight),
      paint,
    );

    // Colonne verticali
    for (int i = 1; i < cols; i++) {
      final x = i * colWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Righe orizzontali leggere (for the ore)
    final rowSpacing = size.height * 0.06;
    for (
      double y = headerHeight + rowSpacing;
      y < size.height;
      y += rowSpacing
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lightPaint);
    }

    // Day labels nel header (watermark)
    final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayStyle = TextStyle(
      color: _getPatternColor().withValues(alpha: 0.1),
      fontSize: size.height * 0.022,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    );
    for (int i = 0; i < cols; i++) {
      _drawWatermarkLabel(
        canvas,
        days[i],
        Offset(i * colWidth + colWidth * 0.15, headerHeight * 0.25),
        dayStyle,
      );
    }
  }

  /// Draws calligraphy lines (baseline, x-height, ascender)
  void _drawCalligraphy(Canvas canvas, Size size) {
    final basePaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.4)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    final guidePaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.18)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

    final accentPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.25)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke;

    // Each gruppo di righe occupa ~18% dell'altezza
    final groupHeight = size.height * 0.16;
    final baselineOffset = groupHeight * 0.75; // Baseline al 75%
    final xHeight = groupHeight * 0.40; // x-height al 40%
    final ascenderLine = groupHeight * 0.10; // Ascender al 10%
    final descenderLine = groupHeight * 0.95; // Descender al 95%
    final topMargin = size.height * 0.04;
    final groupSpacing = size.height * 0.20;

    for (
      double startY = topMargin;
      startY + groupHeight < size.height;
      startY += groupSpacing
    ) {
      // Baseline (linea more spessa)
      canvas.drawLine(
        Offset(0, startY + baselineOffset),
        Offset(size.width, startY + baselineOffset),
        basePaint,
      );

      // x-height (media height of thele lettere minuscole)
      canvas.drawLine(
        Offset(0, startY + xHeight),
        Offset(size.width, startY + xHeight),
        accentPaint,
      );

      // Ascender line (altezza lettere alte: b, d, f, h, k, l)
      canvas.drawLine(
        Offset(0, startY + ascenderLine),
        Offset(size.width, startY + ascenderLine),
        guidePaint,
      );

      // Descender line (coda lettere: g, j, p, q, y)
      canvas.drawLine(
        Offset(0, startY + descenderLine),
        Offset(size.width, startY + descenderLine),
        guidePaint,
      );
    }
  }

  /// Draws light grid with dots at intersections
  void _drawDotGrid(Canvas canvas, Size size) {
    final gridSpacing = 1.0 * scale; // 1cm reale
    final maxLines = 2000;
    final verticalLines = (size.width / gridSpacing).ceil().clamp(0, maxLines);
    final horizontalLines = (size.height / gridSpacing).ceil().clamp(
      0,
      maxLines,
    );

    // Griglia leggera
    final gridPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.08)
          ..strokeWidth = 0.3
          ..style = PaintingStyle.stroke;

    for (int i = 1; i < verticalLines; i++) {
      final x = i * gridSpacing;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 1; i < horizontalLines; i++) {
      final y = i * gridSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Dots alle intersezioni (more visibili)
    final dotPaint =
        Paint()
          ..color = _getPatternColor().withValues(alpha: 0.35)
          ..style = PaintingStyle.fill;

    final dotRadius =
        0.05 *
        scale; // ~1.9px a scala 37.8 (leggermente more grandi alle intersezioni)
    final maxDots = 1000;

    for (int i = 1; i < verticalLines && i < maxDots; i++) {
      final x = i * gridSpacing;
      for (int j = 1; j < horizontalLines && j < maxDots; j++) {
        final y = j * gridSpacing;
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }

  /// Gets the color del pattern based onllo sfondo
  Color _getPatternColor() {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  bool shouldRepaint(PaperPatternPainter oldDelegate) {
    return oldDelegate.paperType != paperType ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.scale != scale;
  }
}
