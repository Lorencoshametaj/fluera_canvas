import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'fluera_canvas example',
        theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
        home: const CanvasDemo(),
      );
}

class CanvasDemo extends StatefulWidget {
  const CanvasDemo({super.key});

  @override
  State<CanvasDemo> createState() => _CanvasDemoState();
}

class _CanvasDemoState extends State<CanvasDemo> {
  final InfiniteCanvasController controller = InfiniteCanvasController();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset>? _current;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InfiniteCanvasGestureDetector(
        controller: controller,
        onDrawStart: (pos, pressure, tiltX, tiltY) {
          setState(() {
            _current = <Offset>[pos];
            _strokes.add(_current!);
          });
        },
        onDrawUpdate: (pos, pressure, tiltX, tiltY) {
          setState(() => _current?.add(pos));
        },
        onDrawEnd: (pos) {
          setState(() {
            _current?.add(pos);
            _current = null;
          });
        },
        child: CustomPaint(
          painter: _CanvasPainter(_strokes, controller),
          size: Size.infinite,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _reset,
        icon: const Icon(Icons.refresh),
        label: const Text('Clear'),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.strokes, this.camera) : super(repaint: camera);

  final List<List<Offset>> strokes;
  final InfiniteCanvasController camera;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);

    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.rotate(camera.rotation);
    canvas.scale(camera.scale);

    final Paint paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.0 / camera.scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final List<Offset> stroke in strokes) {
      if (stroke.length < 2) continue;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) => true;
}
