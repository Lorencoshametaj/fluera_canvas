// ════════════════════════════════════════════════════════════════════════════
// GpuStrokeBackend — abstract hook for a native GPU live-stroke renderer.
//
// The MIT `fluera_canvas` core does NOT ship a native backend. Consumers
// who want GPU-accelerated live strokes install the commercial
// `fluera_canvas_gpu` add-on, which exposes an implementation of this
// interface and registers it via [FlueraCanvasGpu.setBackend]. When no
// backend is registered the canvas transparently falls back to the Dart
// painter — the stroke is still visible, just with slightly higher
// latency (~12–16 ms vs ~8 ms on native).
//
// Rationale for the split:
//   • The native tessellator (Vulkan / Metal / OpenGL / D3D11 / WebGPU)
//     is several thousand lines of C++/Swift/HLSL/MSL that represent the
//     core IP of the Fluera engine. Publishing it MIT on pub.dev would
//     hand it over to forks.
//   • Keeping only the Dart pipeline in the free core means pub.dev gets
//     a complete canvas SDK (gesture, scene graph, spatial index, tools,
//     export, history) while the GPU path ships as a paid add-on.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui' show Color;

import '../../canvas/infinite_canvas_controller.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// Contract a commercial GPU backend must satisfy to plug into the free
/// `fluera_canvas` widget tree.
///
/// All methods are safe to call in any order; implementations should
/// no-op until [init] has returned a non-null texture id.
abstract class GpuStrokeBackend {
  /// True if this backend is runnable on the current platform + device.
  /// `false` must make the canvas fall back to Dart rendering silently.
  Future<bool> get isAvailable;

  /// Allocate the native surface. Returns a Flutter `textureId` the
  /// [NativeStrokeOverlay] will mount via a [Texture] widget, or `null`
  /// when the platform has no Texture concept (web → returns a
  /// non-null integer anyway; the overlay widget will route through
  /// [usesPlatformView] instead).
  Future<int?> init(int width, int height);

  /// Backends that render to an HTML element (WebGPU) instead of a
  /// Flutter `Texture` set this to `true` so the overlay mounts an
  /// `HtmlElementView` rather than `Texture(textureId:)`.
  bool get usesPlatformView => false;

  /// Stream a new batch of world-space stroke samples to the GPU and
  /// trigger a render. Implementations may coalesce consecutive calls
  /// at the native refresh rate.
  void updateAndRender(
    List<ProDrawingPoint> points,
    Color color,
    double strokeWidth, {
    bool force = false,
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
    double zoomScale = 1.0,
  });

  /// Push the current camera transform (pan / zoom / rotation) into the
  /// native renderer. Called on every camera tick.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
  ]);

  /// Allocate a new swapchain of the requested size. Returns `true` on
  /// success.
  Future<bool> resize(int width, int height);

  /// Clear the native surface to transparent. Called on pen-up and on
  /// every new pen-down.
  void clear();

  /// Free the native surface and any GPU resources.
  void dispose();
}

/// Holder for the (optional) process-wide GPU backend.
///
/// A commercial consumer wires the native implementation once at
/// app boot:
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   FlueraCanvasGpu.setBackend(FlueraCanvasGpuBackend());  // from fluera_canvas_gpu
///   runApp(const MyApp());
/// }
/// ```
///
/// The free pub.dev core ships no backend; the static slot stays `null`
/// and the canvas uses the Dart painter.
class FlueraCanvasGpu {
  FlueraCanvasGpu._();

  static GpuStrokeBackend? _backend;

  /// Register the GPU backend. Pass `null` to reset to the Dart
  /// fallback (useful in tests).
  static void setBackend(GpuStrokeBackend? backend) {
    _backend = backend;
  }

  /// Current backend, or `null` if no GPU add-on is installed.
  static GpuStrokeBackend? get backend => _backend;

  /// Convenience: true iff a backend is registered AND reports
  /// available on this device.
  static Future<bool> get isGpuAvailable async {
    final b = _backend;
    if (b == null) return false;
    return await b.isAvailable;
  }
}
