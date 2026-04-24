// Web implementation of WebGPU overlay view.
// Uses HtmlElementView to embed the WebGPU <canvas> element.

// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const String _viewType = 'fluera-webgpu-overlay';
bool _registered = false;

void registerViewFactory() {
  if (_registered) return;
  _registered = true;

  ui_web.platformViewRegistry.registerViewFactory(
    _viewType,
    (int viewId, {Object? params}) {
      final div = web.document.createElement('div') as web.HTMLDivElement;
      div.style.width = '100%';
      div.style.height = '100%';
      div.style.position = 'absolute';
      div.style.top = '0';
      div.style.left = '0';
      div.style.pointerEvents = 'none';
      div.style.overflow = 'hidden';

      // The actual WebGPU canvas is managed by WebGpuStrokeOverlayService
      // and will be appended to this container when init() is called.
      div.id = 'fluera-webgpu-container';

      return div;
    },
  );
}

Widget buildOverlayView() {
  return const HtmlElementView(
    viewType: _viewType,
  );
}
