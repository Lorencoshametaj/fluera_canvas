# fluera_canvas

A professional 2D canvas SDK for Flutter. Pressure-sensitive infinite canvas
with a native GPU live-stroke pipeline, a scene graph, and pluggable brush
engines.

> **Status:** 0.1.0 pre-release. API unstable until 1.0.0.

## Platforms

| Platform | Live-stroke backend | Status |
| --- | --- | --- |
| Android | Vulkan              | ✅ |
| iOS     | Metal               | ✅ |
| macOS   | Metal               | ✅ |
| Linux   | OpenGL              | Dart fallback (native tessellation differs) |
| Windows | Direct3D 11         | Dart fallback (native tessellation differs) |
| Web     | WebGPU              | Dart fallback (WebGPU path experimental) |

## License

MIT — see [LICENSE](LICENSE).
