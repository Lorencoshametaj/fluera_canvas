// Stub implementation for non-web platforms.
// These functions are never called because the widget checks kIsWeb.

import 'package:flutter/widgets.dart';

void registerViewFactory() {
  // No-op on non-web platforms
}

Widget buildOverlayView() {
  return const SizedBox.shrink();
}
