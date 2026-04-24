// ═══════════════════════════════════════════════════════════════════
// 🌐 WebGpuOverlayView — HtmlElementView wrapper for WebGPU canvas
//
// Embeds the WebGPU <canvas> element into the Flutter widget tree.
// Equivalent to `Texture(textureId:)` used by native overlay renderers.
//
// The canvas has `pointer-events: none` so Flutter handles all input.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// Conditional import: only import web-specific code on web
import 'webgpu_overlay_view_stub.dart'
    if (dart.library.js_interop) 'webgpu_overlay_view_web.dart' as impl;

/// Widget that displays the WebGPU stroke overlay.
///
/// On web: renders an HtmlElementView wrapping the WebGPU canvas.
/// On non-web: renders SizedBox.shrink() (never shown).
class WebGpuOverlayView extends StatelessWidget {
  const WebGpuOverlayView({super.key});

  /// Register the platform view factory. Must be called before use.
  static void registerViewFactory() {
    impl.registerViewFactory();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return impl.buildOverlayView();
  }
}
