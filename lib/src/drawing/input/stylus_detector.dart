import '../../utils/platform_guard.dart';
import 'package:flutter/gestures.dart';

/// 🖊️ STYLUS DETECTOR
/// Handles il rilevamento e la differenziazione among thenput stylus e touch
/// for all supported platforms and devices.
///
/// FEATURES:
/// - ✅ Samsung S Pen (Android)
/// - ✅ Apple Pencil (iOS/iPadOS)
/// - ✅ Surface Pen (Windows)
/// - ✅ Wacom Stylus
/// - ✅ Generic Stylus
/// - ✅ Finger touch detection
/// - ✅ Multi-finger gesture detection

class StylusDetector {
  static const double _stylusPressureThreshold = 0.1;

  /// Checks if the device supports the stylus
  static bool get isStylusSupported {
    if (PlatformGuard.isAndroid) {
      // Samsung, Wacom e altri Android devices
      return true;
    } else if (PlatformGuard.isIOS) {
      // Apple Pencil su iPad
      return true;
    } else if (PlatformGuard.isWindows) {
      // Surface Pen e altri Windows devices
      return true;
    }
    return false;
  }

  /// Determina se l'evento proviene da una stylus
  ///
  /// Logica di rilevamento:
  /// 1. PointerDeviceKind.stylus → stylus dedicata
  /// 2. pressure > threshold → probabilmente stylus (even if registrata come touch)
  /// 3. PointerDeviceKind.touch con low pressure → finger
  static bool isStylus(PointerEvent event) {
    // 1. Check diretto per device kind
    if (event.kind == PointerDeviceKind.stylus) {
      return true;
    }

    // 2. Samsung S Pen and Apple Pencil can be detected via pressure
    // even when registered as PointerDeviceKind.touch
    if (event.pressure > _stylusPressureThreshold) {
      // Pressure significativa suggerisce stylus
      // (the finger usually has pressure = 1.0 or very high)
      // The stylus has gradual values based on applied pressure
      return event.pressure < 0.9;
    }

    return false;
  }

  /// Determina se l'evento proviene da un dito
  static bool isFinger(PointerEvent event) {
    return event.kind == PointerDeviceKind.touch && !isStylus(event);
  }

  /// Returne il number of dita attualmente attive
  /// (excludes stylus from count)
  static int getActiveFingerCount(
    Set<int> activePointers,
    Map<int, PointerEvent> pointerCache,
  ) {
    int fingerCount = 0;
    for (final pointerId in activePointers) {
      final event = pointerCache[pointerId];
      if (event != null && isFinger(event)) {
        fingerCount++;
      }
    }
    return fingerCount;
  }

  /// Checks se c'è una stylus attiva
  static bool hasStylusActive(
    Set<int> activePointers,
    Map<int, PointerEvent> pointerCache,
  ) {
    for (final pointerId in activePointers) {
      final event = pointerCache[pointerId];
      if (event != null && isStylus(event)) {
        return true;
      }
    }
    return false;
  }

  /// Info di debug per l'evento
  static String getEventDebugInfo(PointerEvent event) {
    return 'Kind: ${event.kind}, Pressure: ${event.pressure.toStringAsFixed(3)}, '
        'IsStylus: ${isStylus(event)}, IsFinger: ${isFinger(event)}';
  }

  /// Type of input rilevato
  static StylusInputType getInputType(PointerEvent event) {
    if (isStylus(event)) {
      return StylusInputType.stylus;
    } else if (isFinger(event)) {
      return StylusInputType.finger;
    }
    return StylusInputType.unknown;
  }

  /// Informazioni specifiche per piattaforma
  static String getPlatformStylusInfo() {
    if (PlatformGuard.isAndroid) {
      return 'Android (Samsung S Pen, Wacom, Generic)';
    } else if (PlatformGuard.isIOS) {
      return 'iOS (Apple Pencil)';
    } else if (PlatformGuard.isWindows) {
      return 'Windows (Surface Pen, Wacom)';
    }
    return 'Platform not supported';
  }
}

/// Type of input rilevato
enum StylusInputType {
  stylus, // Penna stylus
  finger, // Dito
  unknown, // Do not determinato
}

/// 🎯 STYLUS INPUT MANAGER
/// Handles la logica di input basata sul modo stylus attivo/disattivo
///
/// MODALITÀ STYLUS ATTIVA:
/// - Stylus → Disegno
/// - 1 finger → Pan/movement
/// - 2 dita → Zoom (pinch)
///
/// MODALITÀ STYLUS DISATTIVA:
/// - 1 dito → Disegno
/// - 2 dita → Zoom (pinch)
class StylusInputManager {
  bool _stylusModeEnabled = false;
  final Set<int> _activePointers = {};
  final Map<int, PointerEvent> _pointerCache = {};

  bool get stylusModeEnabled => _stylusModeEnabled;

  /// Enable/disable stylus mode
  void setStylusMode(bool enabled) {
    _stylusModeEnabled = enabled;
  }

  /// Registra un nuovo pointer
  void addPointer(PointerEvent event) {
    _activePointers.add(event.pointer);
    _pointerCache[event.pointer] = event;
  }

  /// Updates un pointer esistente
  void updatePointer(PointerEvent event) {
    _pointerCache[event.pointer] = event;
  }

  /// Removes un pointer
  void removePointer(int pointerId) {
    _activePointers.remove(pointerId);
    _pointerCache.remove(pointerId);
  }

  /// Reset completo
  void reset() {
    _activePointers.clear();
    _pointerCache.clear();
  }

  /// Checks if the last active pointer can draw
  /// (to use in onPanStart where we don't have direct access to PointerEvent)
  bool canDrawWithCurrentPointer() {
    if (_activePointers.isEmpty) return false;

    // Prendi l'ultimo active pointer
    final lastPointerId = _activePointers.last;
    final lastEvent = _pointerCache[lastPointerId];

    if (lastEvent == null) return false;

    return shouldDraw(lastEvent);
  }

  /// Determina se l'input corrente dovrebbe disegnare
  bool shouldDraw(PointerEvent event) {
    if (_stylusModeEnabled) {
      // MODALITÀ STYLUS ATTIVA:
      // Only la stylus can disegnare
      return StylusDetector.isStylus(event);
    } else {
      // MODALITÀ STYLUS DISATTIVA:
      // Un singolo dito can disegnare (no multi-touch)
      final fingerCount = StylusDetector.getActiveFingerCount(
        _activePointers,
        _pointerCache,
      );
      return fingerCount == 1 && StylusDetector.isFinger(event);
    }
  }

  /// Determina se l'input corrente dovrebbe fare pan
  bool shouldPan(PointerEvent event) {
    if (_stylusModeEnabled) {
      // MODALITÀ STYLUS ATTIVA:
      // Un singolo dito fa pan
      final fingerCount = StylusDetector.getActiveFingerCount(
        _activePointers,
        _pointerCache,
      );
      return fingerCount == 1 && StylusDetector.isFinger(event);
    } else {
      // MODALITÀ STYLUS DISATTIVA:
      // Pan disabilitato (il dito disegna)
      return false;
    }
  }

  /// Determina se l'input corrente dovrebbe fare zoom
  bool shouldZoom() {
    // In entrambe le mode: 2 dita = zoom
    final fingerCount = StylusDetector.getActiveFingerCount(
      _activePointers,
      _pointerCache,
    );
    return fingerCount >= 2;
  }

  /// Gets lo current state dell'input
  StylusInputState getCurrentState(PointerEvent event) {
    if (shouldDraw(event)) {
      return StylusInputState.drawing;
    } else if (shouldPan(event)) {
      return StylusInputState.panning;
    } else if (shouldZoom()) {
      return StylusInputState.zooming;
    }
    return StylusInputState.idle;
  }

  /// Debug info
  String getDebugInfo() {
    final hasStylusActive = StylusDetector.hasStylusActive(
      _activePointers,
      _pointerCache,
    );
    final fingerCount = StylusDetector.getActiveFingerCount(
      _activePointers,
      _pointerCache,
    );

    return 'Mode: ${_stylusModeEnabled ? "STYLUS" : "NORMAL"}, '
        'Pointers: ${_activePointers.length}, '
        'Fingers: $fingerCount, '
        'HasStylus: $hasStylusActive';
  }
}

/// Stato dell'input corrente
enum StylusInputState {
  idle, // Nessun input attivo
  drawing, // Disegno attivo
  panning, // Pan attivo (movimento)
  zooming, // Zoom attivo (pinch)
}
