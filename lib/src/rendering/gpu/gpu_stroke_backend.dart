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

import 'dart:ui' as ui;
import 'dart:ui' show Color;

import '../../canvas/infinite_canvas_controller.dart';
import '../../drawing/brush_config.dart';
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
  ///
  /// 0.5.0 BREAKING CHANGE: per-brush tuning moved out of the positional
  /// parameter list and into the [PencilConfig] / [FountainPenConfig]
  /// value classes. Callers that didn't tune anything migrate by
  /// dropping the old `pencilXxx` / `fountainXxx` arguments — the
  /// defaults of the new structs match the old positional defaults
  /// byte-for-byte.
  ///
  /// [transformSeq] is the producer's view of the camera-transform
  /// counter (incremented on every accepted [setTransform]). The
  /// native scoreboard rejects renders whose `transformSeq` is older
  /// than the most-recently-applied transform — this is what closes
  /// the historical race where a stroke could ship with a stale matrix
  /// for ~16 ms after a pan/zoom. Pass `0` from non-camera-aware
  /// callers; the native side treats `0` as "no scoreboard check".
  void updateAndRender(
    List<ProDrawingPoint> points,
    Color color,
    double strokeWidth, {
    bool force = false,
    int brushType = 0,
    PencilConfig pencil = PencilConfig.defaults,
    FountainPenConfig fountainPen = FountainPenConfig.defaults,
    double zoomScale = 1.0,
    int transformSeq = 0,
  });

  /// Push the current camera transform (pan / zoom / rotation) into the
  /// native renderer. Called on every camera tick.
  ///
  /// Returns the producer's monotonic transform sequence number. Pass
  /// it on the next [updateAndRender] call so the native side can
  /// reject stroke batches that were queued before this transform was
  /// applied. Implementations that don't (yet) scoreboard can return
  /// any monotonic value — the contract is that the value increases.
  int setTransform(
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

  // ────────────────────────────────────────────────────────────────────────
  // Committed-stroke renderer
  // ────────────────────────────────────────────────────────────────────────
  //
  // Optional override for `CanvasStroke.picture()`. The free core builds
  // its committed-stroke pictures with a vector polyline; consumers that
  // installed the commercial `fluera_canvas_gpu` add-on can register a
  // shader-backed renderer here so the post-pen-up appearance matches the
  // GPU live preview byte-for-byte. When unset (the pub.dev default) the
  // canvas keeps using its built-in vector renderer.

  static CanvasStrokeRenderer? _strokeRenderer;

  /// Register an override for the committed-stroke renderer. Pass `null`
  /// to revert to the built-in vector renderer.
  static void setStrokeRenderer(CanvasStrokeRenderer? renderer) {
    _strokeRenderer = renderer;
  }

  /// Currently registered committed-stroke renderer, or `null` if none.
  static CanvasStrokeRenderer? get strokeRenderer => _strokeRenderer;

  // ────────────────────────────────────────────────────────────────────────
  // Layer compositor (canvas 0.6.0+)
  // ────────────────────────────────────────────────────────────────────────
  //
  // Optional override for the per-layer `saveLayer` pass that the canvas-
  // core committed painter does. The free pub.dev core uses Flutter's
  // built-in `Canvas.saveLayer + ui.BlendMode` (8 standard blend modes).
  // Consumers that installed `fluera_canvas_gpu` register a GPU compositor
  // here that supports the full Photoshop-grade set (16 modes), layer
  // masks via stencil, and high-dpi compositing. When unset (the pub.dev
  // default) the canvas keeps using `Canvas.saveLayer`.

  static LayerCompositor? _layerCompositor;

  /// Register an override for the per-layer compositor. Pass `null` to
  /// revert to the built-in Dart `Canvas.saveLayer` path.
  static void setLayerCompositor(LayerCompositor? compositor) {
    _layerCompositor = compositor;
  }

  /// Currently registered layer compositor, or `null` if none. The
  /// committed-strokes painter checks this on every paint.
  static LayerCompositor? get layerCompositor => _layerCompositor;
}

/// Optional override for the per-layer composite pass.
///
/// The committed-strokes painter calls [compositeLayer] once per visible
/// layer that has on-screen strokes. Implementations are responsible for
/// compositing the layer onto [canvas] with the correct opacity and blend
/// mode; they MUST call [paintStrokes] exactly once to draw the stroke
/// content into their own offscreen surface, then composite that surface
/// onto [canvas] with the requested mixing.
///
/// The free pub.dev fallback (when no compositor is registered) is a
/// straight `canvas.saveLayer(viewport, Paint()..color..blendMode); paintStrokes(canvas); canvas.restore();`.
/// Commercial implementations may use GPU shaders to support
/// Photoshop-grade modes and layer masks that `ui.BlendMode` can't
/// express.
abstract class LayerCompositor {
  /// Composite a single layer onto [canvas].
  ///
  /// [paintStrokes] paints the on-screen strokes of the layer in
  /// canvas-world coordinates (the camera transform is already applied
  /// to [canvas]). Implementations must call this once.
  ///
  /// [opacity] is the per-layer alpha multiplier in `[0, 1]`.
  ///
  /// [blendMode] is the standard-set blend mode (one of the 17 modes
  /// Flutter exposes via `ui.BlendMode`). The free core uses this
  /// directly with `Canvas.saveLayer`.
  ///
  /// [extendedBlendModeCode] is non-null when the layer is set to one
  /// of the 9 Photoshop-grade extended modes that `ui.BlendMode` cannot
  /// express (LinearBurn, VividLight, LinearLight, PinLight, HardMix,
  /// DarkerColor, LighterColor, Subtract, Divide). The free fallback
  /// ignores this — the canvas-core has already substituted [blendMode]
  /// with `FlueraBlendMode.closestStandard` so the layer still renders.
  /// The commercial `fluera_canvas_gpu` compositor inspects the code and
  /// dispatches to a custom fragment shader that compositing-accurately
  /// reproduces the Photoshop result.
  ///
  /// [layerRect] is a bound that contains every visible stroke on the
  /// layer under the current camera — pass it to `saveLayer` calls to
  /// avoid full-screen alloc.
  void compositeLayer(
    ui.Canvas canvas, {
    required double opacity,
    required ui.BlendMode blendMode,
    required ui.Rect layerRect,
    required void Function(ui.Canvas) paintStrokes,
    int? extendedBlendModeCode,
    ui.Image? mask,
  });

  /// Composite a single layer that is on a Photoshop-grade extended
  /// blend mode (one of codes 100..108 in `FlueraBlendMode`), with a
  /// pre-computed [backdrop] snapshot of everything painted below this
  /// layer.
  ///
  /// The painter calls this overload (instead of [compositeLayer])
  /// only when:
  ///   1. `extendedBlendModeCode != null`, and
  ///   2. the registered compositor reports
  ///      [supportsBackdropAwareBlend] as `true`.
  ///
  /// Why a separate method: the math for these modes (LinearBurn,
  /// VividLight, …) needs both source and destination as shader
  /// samplers. The plain [compositeLayer] hands the compositor only a
  /// `paintStrokes` callback — it has no way to read the backdrop.
  ///
  /// The default implementation reuses [blendExtendedToImage] to keep
  /// the user canvas blit and any internal bookkeeping in sync — that
  /// way a compositor that wants both a "draw to canvas" path AND a
  /// "give me the result image so I can chain extended layers
  /// accurately" path only writes the shader dispatch once.
  ///
  /// [foregroundImageSize] is the pixel size of [backdrop]. The
  /// compositor produces a foreground image of the same size.
  void compositeLayerExtended(
    ui.Canvas canvas, {
    required double opacity,
    required ui.Rect layerRect,
    required void Function(ui.Canvas) paintStrokes,
    required int extendedBlendModeCode,
    required ui.Image backdrop,
    required ui.Size foregroundImageSize,
    required double devicePixelRatio,
    ui.Image? mask,
  }) {
    final result = blendExtendedToImage(
      opacity: opacity,
      layerRect: layerRect,
      paintStrokes: paintStrokes,
      extendedBlendModeCode: extendedBlendModeCode,
      backdrop: backdrop,
      foregroundImageSize: foregroundImageSize,
      devicePixelRatio: devicePixelRatio,
      mask: mask,
    );
    // (mask was passed to blendExtendedToImage; the implementor honours
    // it via the shader path. The default impl needs no further
    // handling.)
    if (result == null) {
      throw UnimplementedError(
        'Compositor opted into backdrop-aware blend but did not '
        'override blendExtendedToImage / compositeLayerExtended.',
      );
    }
    canvas.save();
    canvas.translate(layerRect.left, layerRect.top);
    canvas.scale(layerRect.width / foregroundImageSize.width);
    canvas.drawImage(
      result,
      ui.Offset.zero,
      ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, opacity),
    );
    canvas.restore();
    result.dispose();
  }

  /// Run the extended-mode shader (codes 100..108) over [backdrop] +
  /// the rasterised [paintStrokes] foreground and return the composited
  /// image in pixel space.
  ///
  /// Returning the image — instead of drawing it directly — lets the
  /// painter REUSE it as the running backdrop for a subsequent
  /// extended-mode layer, so chaining two or more Photoshop-grade
  /// blends in a row stays pixel-accurate. (Stage 2B used the
  /// closest-standard `ui.BlendMode` to mirror the layer into the
  /// running backdrop, which drifted the chain off the reference
  /// math after the second extended layer.)
  ///
  /// Caller owns the returned image — call `.dispose()` when done.
  /// The default implementation returns `null`; only compositors that
  /// can run the shader in image-space override this. When `null`, the
  /// painter falls back to [compositeLayerExtended] direct + a
  /// closest-standard mirror for the running backdrop.
  ui.Image? blendExtendedToImage({
    required double opacity,
    required ui.Rect layerRect,
    required void Function(ui.Canvas) paintStrokes,
    required int extendedBlendModeCode,
    required ui.Image backdrop,
    required ui.Size foregroundImageSize,
    required double devicePixelRatio,
    ui.Image? mask,
  }) => null;

  /// Whether this compositor can honour a Photoshop-grade extended
  /// blend mode by reading the parent backdrop. Defaults to `false` —
  /// the painter then routes extended layers through [compositeLayer]
  /// (which falls back to the closest-standard `ui.BlendMode`).
  ///
  /// Set to `true` only after [compositeLayerExtended] is implemented
  /// AND the underlying shader program has finished loading. The
  /// painter probes this on every paint, so flipping it from `false`
  /// to `true` once the GPU shader is ready (during async program
  /// load) is supported.
  bool get supportsBackdropAwareBlend => false;
}

/// Optional override for the committed-stroke renderer.
///
/// The free `fluera_canvas` core paints committed strokes with a flat
/// vector polyline (single average-pressure width, quadratic-Bézier
/// smoothing). Consumers that install the commercial `fluera_canvas_gpu`
/// add-on register an implementation of this interface via
/// [FlueraCanvasGpu.setStrokeRenderer] so that committed strokes get
/// the same shader-driven brush appearance as the live preview.
///
/// Implementations receive the stroke data as raw fields rather than a
/// `CanvasStroke` instance to avoid an upward dependency from this file
/// onto the widget layer where `CanvasStroke` lives.
abstract class CanvasStrokeRenderer {
  /// Paint [points] / [pressures] onto [canvas] in canvas-world
  /// coordinates. The caller has already applied the camera transform —
  /// implementations draw in the same coordinate space the live preview
  /// uses (no extra translate / scale needed).
  ///
  /// Implementations must be a no-op when [brushType] is the canvas-core
  /// vector default (typically `0`) — the caller will fall back to its
  /// built-in vector renderer in that case.
  void renderStroke(
    ui.Canvas canvas, {
    required List<ui.Offset> points,
    required List<double> pressures,
    required Color color,
    required double baseWidth,
    required bool smooth,
    required int brushType,
    PencilConfig pencilConfig,
    FountainPenConfig fountainConfig,
    double zoomScale,
  });
}
