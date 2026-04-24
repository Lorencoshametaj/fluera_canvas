# fluera_canvas

A professional 2D canvas SDK for Flutter. Pressure-sensitive infinite canvas
with a native GPU live-stroke pipeline, a scene graph, and pluggable brush
engines.

> **Status:** 0.1.0 pre-release. API unstable until 1.0.0.

## Platforms

| Platform | Live-stroke backend | Status |
| --- | --- | --- |
| Android | Vulkan              | ✅ via `fluera_engine` |
| iOS     | Metal               | ✅ via `fluera_engine` |
| macOS   | Metal               | ✅ via `fluera_engine` |
| Linux   | OpenGL              | Dart fallback (native tessellation differs) |
| Windows | Direct3D 11         | Dart fallback (native tessellation differs) |
| Web     | WebGPU              | Dart fallback (WebGPU path experimental) |

## Architecture note — native plugin location

Until the native code (`vk_stroke_renderer.cpp`, `MetalStrokeRenderer.swift`,
`gl_stroke_overlay_plugin.cc`, `d3d11_stroke_overlay_plugin.cpp`) is
physically moved into this package, the full GPU live-stroke pipeline
still ships through the private `fluera_engine` plugin. Consumers that want
the 60 FPS native path should add both packages to their `pubspec.yaml`:

```yaml
dependencies:
  fluera_canvas: ^0.1.0
  # Required for the native live-stroke plugin registration.
  fluera_engine:
    path: # your engine location
```

Dart-only consumers (no native live-stroke) can depend on `fluera_canvas`
alone — the fallback Dart painter inside `NativeStrokeOverlay` takes over
automatically.

The Dart-side FFI bridge (`NativeStrokeFfi`,
`VulkanStrokeOverlayService`) already lives in this package; only the
C++/Kotlin/Swift renderers are still in `fluera_engine`. The
`MethodChannel` name remains `fluera_engine/vulkan_stroke` for now so
existing binaries keep working; it will be renamed to
`fluera_canvas/native_stroke` when the native code moves.

## License

MIT — see [LICENSE](LICENSE).
