/// 🌊 PHYSICS INK SIMULATION
///
/// Simula l'inerzia e l'elasticità dell'inchiostro:
/// - The stroke doesn't end abruptly but "follows" for a few milliseconds
/// - Effetto elastico come if the punta avesse massa
/// - Sensazione organica e naturale
///
/// Features:
/// - Spring physics for smooth ending
/// - Inertial trailing
/// - Configureble damping
library;

import 'dart:ui';

class PhysicsInkSimulator {
  /// Damping coefficient (0.0 = no damping, 1.0 = stops immediately)
  final double damping;

  /// Stiffness of the "spring" (higher = more rigid)
  final double stiffness;

  /// Virtual tip mass (higher = more inertia)
  /// 🌱 Mutable: pressure modulates mass dynamically
  double _mass;

  /// Speed corrente
  Offset _velocity = Offset.zero;

  /// Position corrente (simulata)
  Offset _position = Offset.zero;

  /// Target position (position reale del dito/penna)
  Offset _target = Offset.zero;

  /// Position precedente
  Offset _lastPosition = Offset.zero;

  /// Timestamp ultimo update
  DateTime? _lastUpdate;

  PhysicsInkSimulator({
    this.damping = 0.15,
    this.stiffness = 300.0,
    double mass = 1.0,
  }) : _mass = mass;

  /// 🌱 Dynamic mass (clamped to [0.3, 3.0]).
  double get mass => _mass;
  set mass(double value) => _mass = value.clamp(0.3, 3.0);

  /// Updates il target (position reale del dito)
  void updateTarget(Offset target, DateTime timestamp) {
    _target = target;

    // Prima volta: inizializza position
    if (_lastUpdate == null) {
      _position = target;
      _lastPosition = target;
      _velocity = Offset.zero;
      _lastUpdate = timestamp;
      return;
    }

    // Calculate delta time
    final dt = timestamp.difference(_lastUpdate!).inMicroseconds / 1000000.0;
    if (dt <= 0 || dt > 0.1) {
      // Skip se troppo tempo passato (>100ms)
      _lastUpdate = timestamp;
      return;
    }

    // Spring physics: F = -k * (x - target) - damping * velocity
    final displacement = _position - _target;
    final springForce = displacement * -stiffness;
    final dampingForce = _velocity * -damping * 100.0; // Scale damping

    // F = ma → a = F/m
    final acceleration = (springForce + dampingForce) / _mass;

    // Integra speed e position (Verlet integration)
    _velocity = _velocity + acceleration * dt;
    _lastPosition = _position;
    _position = _position + _velocity * dt;

    _lastUpdate = timestamp;
  }

  /// Get la position simulata (con inerzia)
  Offset getSimulatedPosition() {
    return _position;
  }

  /// Get i punti del trailing (coda inerziale)
  List<Offset> getTrailingPoints({int pointsCount = 5}) {
    if (_lastPosition == _position) {
      return [];
    }

    final points = <Offset>[];

    // Genera punti lungo la traiettoria
    for (int i = 1; i <= pointsCount; i++) {
      final t = i / (pointsCount + 1);
      final point = Offset.lerp(_lastPosition, _position, t)!;
      points.add(point);
    }

    return points;
  }

  /// Apply easing to transition (for "following" effect)
  Offset applyEasing(Offset current, Offset target, {double factor = 0.1}) {
    return Offset.lerp(current, target, factor)!;
  }

  /// Simula l'ending of the stroke con trailing
  List<Offset> simulateEnding({
    required Offset lastPoint,
    int steps = 10,
    double decayRate = 0.8,
  }) {
    final endingPoints = <Offset>[];

    Offset currentPos = lastPoint;
    Offset currentVel = _velocity;

    for (int i = 0; i < steps; i++) {
      // Applica decay alla speed
      currentVel = currentVel * decayRate;

      // If speed troppo bassa, ferma
      if (currentVel.distance < 0.1) break;

      currentPos = currentPos + currentVel;
      endingPoints.add(currentPos);
    }

    return endingPoints;
  }

  /// Calculates l'energia cinetica del sistema
  double getKineticEnergy() {
    // KE = 1/2 * m * v^2
    final speed = _velocity.distance;
    return 0.5 * _mass * speed * speed;
  }

  /// Checks if the sistema is a riposo
  bool isAtRest({double threshold = 0.5}) {
    final displacement = (_position - _target).distance;
    final speed = _velocity.distance;
    return displacement < threshold && speed < threshold;
  }

  /// Resets il simulatore
  void reset() {
    _velocity = Offset.zero;
    _position = Offset.zero;
    _target = Offset.zero;
    _lastPosition = Offset.zero;
    _lastUpdate = null;
  }

  /// Apply an impulse (for special effects)
  void applyImpulse(Offset impulse) {
    _velocity = _velocity + (impulse / _mass);
  }
}
