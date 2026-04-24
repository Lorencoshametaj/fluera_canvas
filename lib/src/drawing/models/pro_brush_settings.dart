import 'dart:math' as math;
import './pressure_curve.dart';
import './velocity_curve.dart';
import './pro_drawing_point.dart';

/// 🎛️ Modello per i parametri personalizzabili di un pennello professionale
///
/// Each stroke salva i propri settings per garantire consistenza
/// during rendering and Firebase persistence.
///
/// v2.0: Added realism parameters (jitter, inkAccumulation, smoothPath)
class ProBrushSettings {
  // === FOUNTAIN PEN (Stilo) ===
  final double fountainMinPressure;
  final double fountainMaxPressure;
  final int fountainTaperEntry;
  final int fountainTaperExit;
  final double fountainVelocityInfluence;
  final double fountainCurvatureInfluence;
  // Tilt support
  final bool fountainTiltEnable;
  final double fountainTiltInfluence;
  final double fountainTiltEllipseRatio;
  // 🆕 Realismo v2.0
  final double fountainJitter; // Micro-variazione naturale (0.0-0.15)
  final double fountainVelocitySensitivity; // Soglia normalizzazione speed (px)
  final double fountainInkAccumulation; // Effetto accumulo su rallentamento
  final bool fountainSmoothPath; // Use spline per bordi morbidi
  // 🆕 Physics v3.0 (user-tunable from long-press)
  final double fountainThinning; // Pressure → width ratio (0.3-0.9)
  final double fountainPressureRate; // Accumulator speed (0.15-0.8)
  final double fountainNibAngleDeg; // Nib angle in degrees (0-90)
  final double fountainNibStrength; // Calligraphic effect (0.0-0.6)

  // === PENCIL (Matita) ===
  final double pencilBaseOpacity;
  final double pencilMaxOpacity;
  final double pencilBlurRadius;
  final double pencilMinPressure;
  final double pencilMaxPressure;

  // === HIGHLIGHTER (Evidenziatore) ===
  final double highlighterOpacity;
  final double highlighterWidthMultiplier;
  final bool highlighterAutoStraighten; // Auto-straighten near-horizontal lines

  // === BALLPOINT (Penna) ===
  final double ballpointMinPressure;
  final double ballpointMaxPressure;

  // === TEXTURE (Phase 3A) ===
  final String
  textureType; // 'none', 'pencilGrain', 'charcoal', 'watercolor', 'canvas', 'kraft'
  final double textureIntensity; // 0.0 = nessun effetto, 1.0 = pieno
  final String textureRotationMode; // 'fixed', 'followStroke', 'random'
  final double textureWetEdge; // 0.0-1.0 (edge darkening)
  final double textureScatterDensity; // 0.5-3.0 (dots per brush width)
  final double textureScatterJitter; // 0.0-1.0 (positional randomness)
  final double textureScatterSizeVar; // 0.0-0.5 (size randomness)

  // === STAMP DYNAMICS (Procreate-style) ===
  final double stampSpacing; // 0.1-1.0 (fraction of brush size)
  final double stampSizeJitter; // 0.0-0.5 (random size variation)
  final double stampRotationJitter; // 0.0-π (random rotation)
  final double stampScatter; // 0.0-2.0 (perpendicular offset)
  final double stampSoftness; // 0.2-1.0 (edge softness)
  final double stampElongation; // 1.0-3.0 (tilt stretch)
  final bool stampEnabled; // Use stamp-based rendering
  final double stampFlow; // 0.1-1.0 (per-stamp opacity contribution)
  final double stampOpacityJitter; // 0.0-0.5 (random opacity variation)
  final double stampWetEdges; // 0.0-1.0 (darker edge ring intensity)
  final double stampMinSize; // 0.05-0.5 (minimum size as % of base)
  final int stampTaperEntry; // 0-15 (entry taper in brush-widths)
  final int stampTaperExit; // 0-15 (exit taper in brush-widths)
  final double stampVelocitySize; // 0-1 (speed → size reduction)
  final double stampVelocityFlow; // 0-1 (speed → flow reduction)
  final bool stampGlazeMode; // true=cap opacity, false=accumulate
  final double stampHueJitter; // 0-30 (degrees of hue shift)
  final double stampSatJitter; // 0-0.3 (saturation jitter)
  final double stampBrightJitter; // 0-0.2 (brightness jitter)
  final double stampTiltRotation; // 0-1 (tilt azimuth → rotation)
  final double stampTiltElongation; // 0-1 (tilt altitude → elongation)
  final String stampDualTexture; // TextureType name for dual brush
  final double stampDualScale; // 0.5-3.0 (dual texture scale)
  final double stampDualBlend; // 0-1 (dual brush intensity)
  final double stampPressureColor; // 0-1 (pressure darkens color)
  final double stampWetMix; // 0-1 (color bleed between stamps)
  final double stampRoundnessJitter; // 0-1 (random elongation variation)
  final double stampColorGradient; // 0-1 (fg→bg along stroke)
  final double stampAccumCap; // 0-1 (max glaze opacity, 0=uncapped)
  final double stampSpacingPressure; // 0-1 (pressure tightens spacing)
  final double stampTransferVelocity; // 0-1 (slow→opaque)
  final int stampSymmetryAxes; // 0=off, 2=bilateral, 3+=radial
  final bool stampEraserMode; // Use stamps to erase
  final bool stampGrainScreenSpace; // true=paper-like grain
  final int stampShapeType; // 0=circle,1=square,2=diamond,3=star,4=leaf
  final double stampGrainScale; // <1=fine (pencil), >1=coarse (charcoal)
  final double
  stampColorPressure; // 0-1 (pressure shifts color toward secondary)

  // === PRESSURE CURVE (Phase 4A) ===
  final PressureCurve pressureCurve;

  // === VELOCITY CURVE (fountain pen only for now).
  // Remaps normalized velocity (distance/time/velocityReference) to the
  // speed factor that modulates stroke width.
  final VelocityCurve fountainVelocityCurve;

  // Reference velocity in px/ms that corresponds to "fast" (curve x=1.0).
  // Apple Pencil on ProMotion iPad Pro typically reaches ~2.0-3.0 px/ms on
  // fast handwriting, so 2.0 is a reasonable default.
  final double fountainVelocityReference;

  // === STABILIZER (Phase 4B) ===
  final int stabilizerLevel; // 0 = off, 10 = max smoothing

  // === WATERCOLOR ===
  final double watercolorSpread; // 0.0-2.0 (wet diffusion spread)

  // === MARKER ===
  final double markerFlatness; // 0.0-1.0 (chisel tip flatness)

  // === CHARCOAL ===
  final double charcoalGrain; // 0.0-1.0 (paper grain erosion)

  // === TECHNICAL PEN ===
  final bool techAngleSnap; // Snap lines to angle increments
  final double techSnapAngleDeg; // Snap resolution (15/30/45/90)
  final bool techEndpointSnap; // Close shape when end near start
  final double techCornerSharpening; // Corner sharpness threshold (0-1)
  final bool techGridSnap; // Snap to grid
  final double techGridSize; // Grid cell size in logical pixels
  final bool techStraightAssist; // Straighten slow straight segments
  final bool techShowGuides; // Show visual guides + measurements
  final bool techParallelSnap; // Snap to previous stroke angle
  final bool techPerpSnap; // Snap perpendicular to previous stroke
  final bool techMultiSegment; // Tap-to-place connected points mode

  // === COLOR MANAGEMENT (Phase 4D) ===
  final bool useWideGamut; // false = sRGB, true = Display P3

  const ProBrushSettings({
    // Fountain Pen defaults (bilanciati v2.0)
    this.fountainMinPressure = 0.35,
    this.fountainMaxPressure = 1.5,
    this.fountainTaperEntry = 6,
    this.fountainTaperExit = 8,
    this.fountainVelocityInfluence = 0.6,
    this.fountainCurvatureInfluence = 0.25,
    this.fountainTiltEnable = true,
    this.fountainTiltInfluence = 1.2,
    this.fountainTiltEllipseRatio = 2.5,
    // 🆕 Realismo v2.0 defaults
    this.fountainJitter = 0.08,
    this.fountainVelocitySensitivity = 10.0,
    this.fountainInkAccumulation = 0.15,
    this.fountainSmoothPath = true,
    // 🆕 Physics v3.0 defaults
    this.fountainThinning = 0.5,
    this.fountainPressureRate = 0.275,
    this.fountainNibAngleDeg = 30.0,
    this.fountainNibStrength = 0.2,
    // Pencil defaults
    this.pencilBaseOpacity = 0.4,
    this.pencilMaxOpacity = 0.8,
    this.pencilBlurRadius = 0.3,
    this.pencilMinPressure = 0.5,
    this.pencilMaxPressure = 1.2,
    // Highlighter defaults
    this.highlighterOpacity = 0.35,
    this.highlighterWidthMultiplier = 3.0,
    this.highlighterAutoStraighten = true,
    // Ballpoint defaults
    this.ballpointMinPressure = 0.7,
    this.ballpointMaxPressure = 1.1,
    // Texture defaults (Phase 3A)
    this.textureType = 'none',
    this.textureIntensity = 0.5,
    this.textureRotationMode = 'followStroke',
    this.textureWetEdge = 0.0,
    this.textureScatterDensity = 1.0,
    this.textureScatterJitter = 0.0,
    this.textureScatterSizeVar = 0.0,
    // Stamp dynamics defaults
    this.stampSpacing = 0.25,
    this.stampSizeJitter = 0.0,
    this.stampRotationJitter = 0.0,
    this.stampScatter = 0.0,
    this.stampSoftness = 0.6,
    this.stampElongation = 1.0,
    this.stampEnabled = false,
    this.stampFlow = 0.5,
    this.stampOpacityJitter = 0.0,
    this.stampWetEdges = 0.0,
    this.stampMinSize = 0.15,
    this.stampTaperEntry = 6,
    this.stampTaperExit = 6,
    this.stampVelocitySize = 0.0,
    this.stampVelocityFlow = 0.0,
    this.stampGlazeMode = true,
    this.stampHueJitter = 0.0,
    this.stampSatJitter = 0.0,
    this.stampBrightJitter = 0.0,
    this.stampTiltRotation = 0.0,
    this.stampTiltElongation = 0.0,
    this.stampDualTexture = 'none',
    this.stampDualScale = 1.0,
    this.stampDualBlend = 0.0,
    this.stampPressureColor = 0.0,
    this.stampWetMix = 0.0,
    this.stampRoundnessJitter = 0.0,
    this.stampColorGradient = 0.0,
    this.stampAccumCap = 0.0,
    this.stampSpacingPressure = 0.0,
    this.stampTransferVelocity = 0.0,
    this.stampSymmetryAxes = 0,
    this.stampEraserMode = false,
    this.stampGrainScreenSpace = false,
    this.stampShapeType = 0,
    this.stampGrainScale = 1.0,
    this.stampColorPressure = 0.0,
    // Pressure Curve (Phase 4A)
    this.pressureCurve = PressureCurve.linear,
    // Velocity Curve (fountain pen) — goodnotes preset by default for a
    // perceptual swoosh closer to GoodNotes. Override with .linear via
    // copyWith if the old feel is desired.
    this.fountainVelocityCurve = VelocityCurve.goodnotes,
    this.fountainVelocityReference = 2.0,
    // Stabilizer (Phase 4B)
    this.stabilizerLevel = 0,
    // Watercolor
    this.watercolorSpread = 1.0,
    // Marker
    this.markerFlatness = 0.4,
    // Charcoal
    this.charcoalGrain = 0.5,
    // Technical Pen
    this.techAngleSnap = false,
    this.techSnapAngleDeg = 45.0,
    this.techEndpointSnap = false,
    this.techCornerSharpening = 0.5,
    this.techGridSnap = false,
    this.techGridSize = 20.0,
    this.techStraightAssist = false,
    this.techShowGuides = true,
    this.techParallelSnap = false,
    this.techPerpSnap = false,
    this.techMultiSegment = false,
    // Color Management (Phase 4D)
    this.useWideGamut = false,
  });

  /// Settings di default (singleton per ottimizzazione)
  static const ProBrushSettings defaultSettings = ProBrushSettings();

  /// Creates una copia con valori modificati
  ProBrushSettings copyWith({
    double? fountainMinPressure,
    double? fountainMaxPressure,
    int? fountainTaperEntry,
    int? fountainTaperExit,
    double? fountainVelocityInfluence,
    double? fountainCurvatureInfluence,
    bool? fountainTiltEnable,
    double? fountainTiltInfluence,
    double? fountainTiltEllipseRatio,
    // 🆕 Realismo v2.0
    double? fountainJitter,
    double? fountainVelocitySensitivity,
    double? fountainInkAccumulation,
    bool? fountainSmoothPath,
    // 🆕 Physics v3.0
    double? fountainThinning,
    double? fountainPressureRate,
    double? fountainNibAngleDeg,
    double? fountainNibStrength,
    double? pencilBaseOpacity,
    double? pencilMaxOpacity,
    double? pencilBlurRadius,
    double? pencilMinPressure,
    double? pencilMaxPressure,
    double? highlighterOpacity,
    double? highlighterWidthMultiplier,
    bool? highlighterAutoStraighten,
    double? ballpointMinPressure,
    double? ballpointMaxPressure,
    // Texture (Phase 3A)
    String? textureType,
    double? textureIntensity,
    String? textureRotationMode,
    double? textureWetEdge,
    double? textureScatterDensity,
    double? textureScatterJitter,
    double? textureScatterSizeVar,
    // Stamp dynamics
    double? stampSpacing,
    double? stampSizeJitter,
    double? stampRotationJitter,
    double? stampScatter,
    double? stampSoftness,
    double? stampElongation,
    bool? stampEnabled,
    double? stampFlow,
    double? stampOpacityJitter,
    double? stampWetEdges,
    double? stampMinSize,
    int? stampTaperEntry,
    int? stampTaperExit,
    double? stampVelocitySize,
    double? stampVelocityFlow,
    bool? stampGlazeMode,
    double? stampHueJitter,
    double? stampSatJitter,
    double? stampBrightJitter,
    double? stampTiltRotation,
    double? stampTiltElongation,
    String? stampDualTexture,
    double? stampDualScale,
    double? stampDualBlend,
    double? stampPressureColor,
    double? stampWetMix,
    double? stampRoundnessJitter,
    double? stampColorGradient,
    double? stampAccumCap,
    double? stampSpacingPressure,
    double? stampTransferVelocity,
    int? stampSymmetryAxes,
    bool? stampEraserMode,
    bool? stampGrainScreenSpace,
    int? stampShapeType,
    double? stampGrainScale,
    double? stampColorPressure,
    // Pressure Curve (Phase 4A)
    PressureCurve? pressureCurve,
    // Velocity Curve (fountain pen)
    VelocityCurve? fountainVelocityCurve,
    double? fountainVelocityReference,
    // Stabilizer (Phase 4B)
    int? stabilizerLevel,
    // Watercolor
    double? watercolorSpread,
    // Marker
    double? markerFlatness,
    // Charcoal
    double? charcoalGrain,
    // Technical Pen
    bool? techAngleSnap,
    double? techSnapAngleDeg,
    bool? techEndpointSnap,
    double? techCornerSharpening,
    bool? techGridSnap,
    double? techGridSize,
    bool? techStraightAssist,
    bool? techShowGuides,
    bool? techParallelSnap,
    bool? techPerpSnap,
    bool? techMultiSegment,
    // Color Management (Phase 4D)
    bool? useWideGamut,
  }) {
    return ProBrushSettings(
      fountainMinPressure: fountainMinPressure ?? this.fountainMinPressure,
      fountainMaxPressure: fountainMaxPressure ?? this.fountainMaxPressure,
      fountainTaperEntry: fountainTaperEntry ?? this.fountainTaperEntry,
      fountainTaperExit: fountainTaperExit ?? this.fountainTaperExit,
      fountainVelocityInfluence:
          fountainVelocityInfluence ?? this.fountainVelocityInfluence,
      fountainCurvatureInfluence:
          fountainCurvatureInfluence ?? this.fountainCurvatureInfluence,
      fountainTiltEnable: fountainTiltEnable ?? this.fountainTiltEnable,
      fountainTiltInfluence:
          fountainTiltInfluence ?? this.fountainTiltInfluence,
      fountainTiltEllipseRatio:
          fountainTiltEllipseRatio ?? this.fountainTiltEllipseRatio,
      // 🆕 Realismo v2.0
      fountainJitter: fountainJitter ?? this.fountainJitter,
      fountainVelocitySensitivity:
          fountainVelocitySensitivity ?? this.fountainVelocitySensitivity,
      fountainInkAccumulation:
          fountainInkAccumulation ?? this.fountainInkAccumulation,
      fountainSmoothPath: fountainSmoothPath ?? this.fountainSmoothPath,
      // 🆕 Physics v3.0
      fountainThinning: fountainThinning ?? this.fountainThinning,
      fountainPressureRate: fountainPressureRate ?? this.fountainPressureRate,
      fountainNibAngleDeg: fountainNibAngleDeg ?? this.fountainNibAngleDeg,
      fountainNibStrength: fountainNibStrength ?? this.fountainNibStrength,
      pencilBaseOpacity: pencilBaseOpacity ?? this.pencilBaseOpacity,
      pencilMaxOpacity: pencilMaxOpacity ?? this.pencilMaxOpacity,
      pencilBlurRadius: pencilBlurRadius ?? this.pencilBlurRadius,
      pencilMinPressure: pencilMinPressure ?? this.pencilMinPressure,
      pencilMaxPressure: pencilMaxPressure ?? this.pencilMaxPressure,
      highlighterOpacity: highlighterOpacity ?? this.highlighterOpacity,
      highlighterWidthMultiplier:
          highlighterWidthMultiplier ?? this.highlighterWidthMultiplier,
      highlighterAutoStraighten:
          highlighterAutoStraighten ?? this.highlighterAutoStraighten,
      ballpointMinPressure: ballpointMinPressure ?? this.ballpointMinPressure,
      ballpointMaxPressure: ballpointMaxPressure ?? this.ballpointMaxPressure,
      textureType: textureType ?? this.textureType,
      textureIntensity: textureIntensity ?? this.textureIntensity,
      textureRotationMode: textureRotationMode ?? this.textureRotationMode,
      textureWetEdge: textureWetEdge ?? this.textureWetEdge,
      textureScatterDensity:
          textureScatterDensity ?? this.textureScatterDensity,
      textureScatterJitter: textureScatterJitter ?? this.textureScatterJitter,
      textureScatterSizeVar:
          textureScatterSizeVar ?? this.textureScatterSizeVar,
      stampSpacing: stampSpacing ?? this.stampSpacing,
      stampSizeJitter: stampSizeJitter ?? this.stampSizeJitter,
      stampRotationJitter: stampRotationJitter ?? this.stampRotationJitter,
      stampScatter: stampScatter ?? this.stampScatter,
      stampSoftness: stampSoftness ?? this.stampSoftness,
      stampElongation: stampElongation ?? this.stampElongation,
      stampEnabled: stampEnabled ?? this.stampEnabled,
      stampFlow: stampFlow ?? this.stampFlow,
      stampOpacityJitter: stampOpacityJitter ?? this.stampOpacityJitter,
      stampWetEdges: stampWetEdges ?? this.stampWetEdges,
      stampMinSize: stampMinSize ?? this.stampMinSize,
      stampTaperEntry: stampTaperEntry ?? this.stampTaperEntry,
      stampTaperExit: stampTaperExit ?? this.stampTaperExit,
      stampVelocitySize: stampVelocitySize ?? this.stampVelocitySize,
      stampVelocityFlow: stampVelocityFlow ?? this.stampVelocityFlow,
      stampGlazeMode: stampGlazeMode ?? this.stampGlazeMode,
      stampHueJitter: stampHueJitter ?? this.stampHueJitter,
      stampSatJitter: stampSatJitter ?? this.stampSatJitter,
      stampBrightJitter: stampBrightJitter ?? this.stampBrightJitter,
      stampTiltRotation: stampTiltRotation ?? this.stampTiltRotation,
      stampTiltElongation: stampTiltElongation ?? this.stampTiltElongation,
      stampDualTexture: stampDualTexture ?? this.stampDualTexture,
      stampDualScale: stampDualScale ?? this.stampDualScale,
      stampDualBlend: stampDualBlend ?? this.stampDualBlend,
      stampPressureColor: stampPressureColor ?? this.stampPressureColor,
      stampWetMix: stampWetMix ?? this.stampWetMix,
      stampRoundnessJitter: stampRoundnessJitter ?? this.stampRoundnessJitter,
      stampColorGradient: stampColorGradient ?? this.stampColorGradient,
      stampAccumCap: stampAccumCap ?? this.stampAccumCap,
      stampSpacingPressure: stampSpacingPressure ?? this.stampSpacingPressure,
      stampTransferVelocity:
          stampTransferVelocity ?? this.stampTransferVelocity,
      stampSymmetryAxes: stampSymmetryAxes ?? this.stampSymmetryAxes,
      stampEraserMode: stampEraserMode ?? this.stampEraserMode,
      stampGrainScreenSpace:
          stampGrainScreenSpace ?? this.stampGrainScreenSpace,
      stampShapeType: stampShapeType ?? this.stampShapeType,
      stampGrainScale: stampGrainScale ?? this.stampGrainScale,
      stampColorPressure: stampColorPressure ?? this.stampColorPressure,
      pressureCurve: pressureCurve ?? this.pressureCurve,
      fountainVelocityCurve:
          fountainVelocityCurve ?? this.fountainVelocityCurve,
      fountainVelocityReference:
          fountainVelocityReference ?? this.fountainVelocityReference,
      stabilizerLevel: stabilizerLevel ?? this.stabilizerLevel,
      watercolorSpread: watercolorSpread ?? this.watercolorSpread,
      markerFlatness: markerFlatness ?? this.markerFlatness,
      charcoalGrain: charcoalGrain ?? this.charcoalGrain,
      techAngleSnap: techAngleSnap ?? this.techAngleSnap,
      techSnapAngleDeg: techSnapAngleDeg ?? this.techSnapAngleDeg,
      techEndpointSnap: techEndpointSnap ?? this.techEndpointSnap,
      techCornerSharpening: techCornerSharpening ?? this.techCornerSharpening,
      techGridSnap: techGridSnap ?? this.techGridSnap,
      techGridSize: techGridSize ?? this.techGridSize,
      techStraightAssist: techStraightAssist ?? this.techStraightAssist,
      techShowGuides: techShowGuides ?? this.techShowGuides,
      techParallelSnap: techParallelSnap ?? this.techParallelSnap,
      techPerpSnap: techPerpSnap ?? this.techPerpSnap,
      techMultiSegment: techMultiSegment ?? this.techMultiSegment,
      useWideGamut: useWideGamut ?? this.useWideGamut,
    );
  }

  /// 🛡️ Settings format version — increment when parameter semantics change
  static const int currentFormatVersion = 1;

  /// Serializezione JSON compatta per Firebase
  Map<String, dynamic> toJson() => {
    'sfv': currentFormatVersion, // 🛡️ Settings format version
    // Fountain
    'fMinP': fountainMinPressure,
    'fMaxP': fountainMaxPressure,
    'fTapE': fountainTaperEntry,
    'fTapX': fountainTaperExit,
    'fVel': fountainVelocityInfluence,
    'fCurv': fountainCurvatureInfluence,
    'fTiltE': fountainTiltEnable,
    'fTiltI': fountainTiltInfluence,
    'fTiltER': fountainTiltEllipseRatio,
    // 🆕 Realismo v2.0
    'fJit': fountainJitter,
    'fVelS': fountainVelocitySensitivity,
    'fInkA': fountainInkAccumulation,
    'fSmP': fountainSmoothPath,
    // 🆕 Physics v3.0
    'fThin': fountainThinning,
    'fPRate': fountainPressureRate,
    'fNibA': fountainNibAngleDeg,
    'fNibS': fountainNibStrength,
    // Pencil
    'pBaseO': pencilBaseOpacity,
    'pMaxO': pencilMaxOpacity,
    'pBlur': pencilBlurRadius,
    'pMinP': pencilMinPressure,
    'pMaxP': pencilMaxPressure,
    // Highlighter
    'hOp': highlighterOpacity,
    'hWid': highlighterWidthMultiplier,
    if (highlighterAutoStraighten) 'hAutoStr': true,
    // Ballpoint
    'bMinP': ballpointMinPressure,
    'bMaxP': ballpointMaxPressure,
    // Texture (Phase 3A)
    if (textureType != 'none') 'texT': textureType,
    if (textureIntensity != 0.5) 'texI': textureIntensity,
    if (textureRotationMode != 'followStroke') 'texRM': textureRotationMode,
    if (textureWetEdge > 0) 'texWE': textureWetEdge,
    if (textureScatterDensity != 1.0) 'texSD': textureScatterDensity,
    if (textureScatterJitter > 0) 'texSJ': textureScatterJitter,
    if (textureScatterSizeVar > 0) 'texSV': textureScatterSizeVar,
    // Stamp dynamics — omit defaults
    if (stampEnabled) 'stmE': true,
    if (stampSpacing != 0.25) 'stmS': stampSpacing,
    if (stampSizeJitter > 0) 'stmSJ': stampSizeJitter,
    if (stampRotationJitter > 0) 'stmRJ': stampRotationJitter,
    if (stampScatter > 0) 'stmSc': stampScatter,
    if (stampSoftness != 0.6) 'stmSo': stampSoftness,
    if (stampElongation != 1.0) 'stmEl': stampElongation,
    if (stampFlow != 0.5) 'stmFl': stampFlow,
    if (stampOpacityJitter > 0) 'stmOJ': stampOpacityJitter,
    if (stampWetEdges > 0) 'stmWE': stampWetEdges,
    if (stampMinSize != 0.15) 'stmMS': stampMinSize,
    if (stampTaperEntry != 6) 'stmTE': stampTaperEntry,
    if (stampTaperExit != 6) 'stmTX': stampTaperExit,
    if (stampVelocitySize > 0) 'stmVS': stampVelocitySize,
    if (stampVelocityFlow > 0) 'stmVF': stampVelocityFlow,
    if (!stampGlazeMode) 'stmGM': false,
    if (stampHueJitter > 0) 'stmHJ': stampHueJitter,
    if (stampSatJitter > 0) 'stmSJ2': stampSatJitter,
    if (stampBrightJitter > 0) 'stmBJ': stampBrightJitter,
    if (stampTiltRotation > 0) 'stmTR': stampTiltRotation,
    if (stampTiltElongation > 0) 'stmTEl': stampTiltElongation,
    if (stampDualTexture != 'none') 'stmDT': stampDualTexture,
    if (stampDualScale != 1.0) 'stmDS': stampDualScale,
    if (stampDualBlend > 0) 'stmDB': stampDualBlend,
    if (stampPressureColor > 0) 'stmPC': stampPressureColor,
    if (stampWetMix > 0) 'stmWM': stampWetMix,
    if (stampRoundnessJitter > 0) 'stmRJ': stampRoundnessJitter,
    if (stampColorGradient > 0) 'stmCG': stampColorGradient,
    if (stampAccumCap > 0) 'stmAC': stampAccumCap,
    if (stampSpacingPressure > 0) 'stmSP': stampSpacingPressure,
    if (stampTransferVelocity > 0) 'stmTV': stampTransferVelocity,
    if (stampSymmetryAxes > 0) 'stmSA': stampSymmetryAxes,
    if (stampEraserMode) 'stmER': true,
    if (stampGrainScreenSpace) 'stmGS': true,
    if (stampShapeType > 0) 'stmST': stampShapeType,
    if (stampGrainScale != 1.0) 'stmGSc': stampGrainScale,
    if (stampColorPressure > 0) 'stmCP': stampColorPressure,
    // Pressure Curve (Phase 4A) — omit if linear
    if (!pressureCurve.isLinear) 'pCurve': pressureCurve.toJson(),
    if (!fountainVelocityCurve.isLinear)
      'fVCurve': fountainVelocityCurve.toJson(),
    if (fountainVelocityReference != 2.0) 'fVRef': fountainVelocityReference,
    // Stabilizer (Phase 4B) — omit if 0
    if (stabilizerLevel > 0) 'stab': stabilizerLevel,
    // Color Management (Phase 4D) — omit if false
    // Watercolor
    if (watercolorSpread != 1.0) 'wcSpr': watercolorSpread,
    // Marker
    if (markerFlatness != 0.4) 'mkFlt': markerFlatness,
    // Charcoal
    if (charcoalGrain != 0.5) 'chGrn': charcoalGrain,
    // Technical Pen
    if (techAngleSnap) 'tASnap': true,
    if (techSnapAngleDeg != 45.0) 'tSADeg': techSnapAngleDeg,
    if (techEndpointSnap) 'tESnap': true,
    if (techCornerSharpening != 0.5) 'tCShrp': techCornerSharpening,
    if (techGridSnap) 'tGSnap': true,
    if (techGridSize != 20.0) 'tGSize': techGridSize,
    if (techStraightAssist) 'tSAssist': true,
    if (!techShowGuides) 'tSGuides': false,
    if (techParallelSnap) 'tParSnap': true,
    if (techPerpSnap) 'tPerpSnap': true,
    if (techMultiSegment) 'tMultiSeg': true,
    if (useWideGamut) 'wGam': true,
  };

  /// Deserializzazione JSON
  factory ProBrushSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ProBrushSettings();

    return ProBrushSettings(
      // Fountain (default v2.0)
      fountainMinPressure: (json['fMinP'] as num?)?.toDouble() ?? 0.35,
      fountainMaxPressure: (json['fMaxP'] as num?)?.toDouble() ?? 1.5,
      fountainTaperEntry: (json['fTapE'] as num?)?.toInt() ?? 6,
      fountainTaperExit: (json['fTapX'] as num?)?.toInt() ?? 8,
      fountainVelocityInfluence: (json['fVel'] as num?)?.toDouble() ?? 0.6,
      fountainCurvatureInfluence: (json['fCurv'] as num?)?.toDouble() ?? 0.25,
      fountainTiltEnable: (json['fTiltE'] as bool?) ?? true,
      fountainTiltInfluence: (json['fTiltI'] as num?)?.toDouble() ?? 1.2,
      fountainTiltEllipseRatio: (json['fTiltER'] as num?)?.toDouble() ?? 2.5,
      // 🆕 Realismo v2.0
      fountainJitter: (json['fJit'] as num?)?.toDouble() ?? 0.08,
      fountainVelocitySensitivity: (json['fVelS'] as num?)?.toDouble() ?? 10.0,
      fountainInkAccumulation: (json['fInkA'] as num?)?.toDouble() ?? 0.15,
      fountainSmoothPath: (json['fSmP'] as bool?) ?? true,
      // 🆕 Physics v3.0
      fountainThinning: (json['fThin'] as num?)?.toDouble() ?? 0.5,
      fountainPressureRate: (json['fPRate'] as num?)?.toDouble() ?? 0.275,
      fountainNibAngleDeg: (json['fNibA'] as num?)?.toDouble() ?? 30.0,
      fountainNibStrength: (json['fNibS'] as num?)?.toDouble() ?? 0.2,
      // Pencil
      pencilBaseOpacity: (json['pBaseO'] as num?)?.toDouble() ?? 0.4,
      pencilMaxOpacity: (json['pMaxO'] as num?)?.toDouble() ?? 0.8,
      pencilBlurRadius: (json['pBlur'] as num?)?.toDouble() ?? 0.3,
      pencilMinPressure: (json['pMinP'] as num?)?.toDouble() ?? 0.5,
      pencilMaxPressure: (json['pMaxP'] as num?)?.toDouble() ?? 1.2,
      // Highlighter
      highlighterOpacity: (json['hOp'] as num?)?.toDouble() ?? 0.35,
      highlighterWidthMultiplier: (json['hWid'] as num?)?.toDouble() ?? 3.0,
      highlighterAutoStraighten: (json['hAutoStr'] as bool?) ?? true,
      // Ballpoint - clamp to valid slider range (0.5-1.0)
      ballpointMinPressure: ((json['bMinP'] as num?)?.toDouble() ?? 0.7).clamp(
        0.5,
        1.0,
      ),
      ballpointMaxPressure: ((json['bMaxP'] as num?)?.toDouble() ?? 1.1).clamp(
        1.0,
        1.5,
      ),
      // Texture (Phase 3A)
      textureType: (json['texT'] as String?) ?? 'none',
      textureIntensity: (json['texI'] as num?)?.toDouble() ?? 0.5,
      textureRotationMode: (json['texRM'] as String?) ?? 'followStroke',
      textureWetEdge: (json['texWE'] as num?)?.toDouble() ?? 0.0,
      textureScatterDensity: (json['texSD'] as num?)?.toDouble() ?? 1.0,
      textureScatterJitter: (json['texSJ'] as num?)?.toDouble() ?? 0.0,
      textureScatterSizeVar: (json['texSV'] as num?)?.toDouble() ?? 0.0,
      // Stamp dynamics
      stampEnabled: (json['stmE'] as bool?) ?? false,
      stampSpacing: (json['stmS'] as num?)?.toDouble() ?? 0.25,
      stampSizeJitter: (json['stmSJ'] as num?)?.toDouble() ?? 0.0,
      stampRotationJitter: (json['stmRJ'] as num?)?.toDouble() ?? 0.0,
      stampScatter: (json['stmSc'] as num?)?.toDouble() ?? 0.0,
      stampSoftness: (json['stmSo'] as num?)?.toDouble() ?? 0.6,
      stampElongation: (json['stmEl'] as num?)?.toDouble() ?? 1.0,
      stampFlow: (json['stmFl'] as num?)?.toDouble() ?? 0.5,
      stampOpacityJitter: (json['stmOJ'] as num?)?.toDouble() ?? 0.0,
      stampWetEdges: (json['stmWE'] as num?)?.toDouble() ?? 0.0,
      stampMinSize: (json['stmMS'] as num?)?.toDouble() ?? 0.15,
      stampTaperEntry: (json['stmTE'] as num?)?.toInt() ?? 6,
      stampTaperExit: (json['stmTX'] as num?)?.toInt() ?? 6,
      stampVelocitySize: (json['stmVS'] as num?)?.toDouble() ?? 0.0,
      stampVelocityFlow: (json['stmVF'] as num?)?.toDouble() ?? 0.0,
      stampGlazeMode: json['stmGM'] as bool? ?? true,
      stampHueJitter: (json['stmHJ'] as num?)?.toDouble() ?? 0.0,
      stampSatJitter: (json['stmSJ2'] as num?)?.toDouble() ?? 0.0,
      stampBrightJitter: (json['stmBJ'] as num?)?.toDouble() ?? 0.0,
      stampTiltRotation: (json['stmTR'] as num?)?.toDouble() ?? 0.0,
      stampTiltElongation: (json['stmTEl'] as num?)?.toDouble() ?? 0.0,
      stampDualTexture: json['stmDT'] as String? ?? 'none',
      stampDualScale: (json['stmDS'] as num?)?.toDouble() ?? 1.0,
      stampDualBlend: (json['stmDB'] as num?)?.toDouble() ?? 0.0,
      stampPressureColor: (json['stmPC'] as num?)?.toDouble() ?? 0.0,
      stampWetMix: (json['stmWM'] as num?)?.toDouble() ?? 0.0,
      stampRoundnessJitter: (json['stmRJ'] as num?)?.toDouble() ?? 0.0,
      stampColorGradient: (json['stmCG'] as num?)?.toDouble() ?? 0.0,
      stampAccumCap: (json['stmAC'] as num?)?.toDouble() ?? 0.0,
      stampSpacingPressure: (json['stmSP'] as num?)?.toDouble() ?? 0.0,
      stampTransferVelocity: (json['stmTV'] as num?)?.toDouble() ?? 0.0,
      stampSymmetryAxes: (json['stmSA'] as num?)?.toInt() ?? 0,
      stampEraserMode: json['stmER'] as bool? ?? false,
      stampGrainScreenSpace: json['stmGS'] as bool? ?? false,
      stampShapeType: (json['stmST'] as num?)?.toInt() ?? 0,
      stampGrainScale: (json['stmGSc'] as num?)?.toDouble() ?? 1.0,
      stampColorPressure: (json['stmCP'] as num?)?.toDouble() ?? 0.0,
      // Pressure Curve (Phase 4A)
      pressureCurve: PressureCurve.fromJson(
        json['pCurve'] is Map
            ? Map<String, dynamic>.from(json['pCurve'] as Map)
            : null,
      ),
      // Velocity Curve (fountain pen)
      fountainVelocityCurve: VelocityCurve.fromJson(
        json['fVCurve'] is Map
            ? Map<String, dynamic>.from(json['fVCurve'] as Map)
            : null,
      ),
      fountainVelocityReference: (json['fVRef'] as num?)?.toDouble() ?? 2.0,
      // Stabilizer (Phase 4B)
      stabilizerLevel: (json['stab'] as num?)?.toInt() ?? 0,
      // Watercolor
      watercolorSpread: (json['wcSpr'] as num?)?.toDouble() ?? 1.0,
      // Marker
      markerFlatness: (json['mkFlt'] as num?)?.toDouble() ?? 0.4,
      // Charcoal
      charcoalGrain: (json['chGrn'] as num?)?.toDouble() ?? 0.5,
      // Technical Pen
      techAngleSnap: (json['tASnap'] as bool?) ?? false,
      techSnapAngleDeg: (json['tSADeg'] as num?)?.toDouble() ?? 45.0,
      techEndpointSnap: (json['tESnap'] as bool?) ?? false,
      techCornerSharpening: (json['tCShrp'] as num?)?.toDouble() ?? 0.5,
      techGridSnap: (json['tGSnap'] as bool?) ?? false,
      techGridSize: (json['tGSize'] as num?)?.toDouble() ?? 20.0,
      techStraightAssist: (json['tSAssist'] as bool?) ?? false,
      techShowGuides: (json['tSGuides'] as bool?) ?? true,
      techParallelSnap: (json['tParSnap'] as bool?) ?? false,
      techPerpSnap: (json['tPerpSnap'] as bool?) ?? false,
      techMultiSegment: (json['tMultiSeg'] as bool?) ?? false,
      // Color Management (Phase 4D)
      useWideGamut: (json['wGam'] as bool?) ?? false,
    );
  }

  /// Checks if these are the default values (to optimize storage)
  bool get isDefault =>
      fountainMinPressure == 0.35 &&
      fountainMaxPressure == 1.5 &&
      fountainTaperEntry == 6 &&
      fountainTaperExit == 8 &&
      fountainVelocityInfluence == 0.6 &&
      fountainCurvatureInfluence == 0.25 &&
      fountainTiltEnable == true &&
      fountainTiltInfluence == 1.2 &&
      fountainTiltEllipseRatio == 2.5 &&
      fountainJitter == 0.08 &&
      fountainVelocitySensitivity == 10.0 &&
      fountainInkAccumulation == 0.15 &&
      fountainSmoothPath == true &&
      fountainThinning == 0.5 &&
      fountainPressureRate == 0.275 &&
      fountainNibAngleDeg == 30.0 &&
      fountainNibStrength == 0.2 &&
      pencilBaseOpacity == 0.4 &&
      pencilMaxOpacity == 0.8 &&
      pencilBlurRadius == 0.3 &&
      pencilMinPressure == 0.5 &&
      pencilMaxPressure == 1.2 &&
      highlighterOpacity == 0.35 &&
      highlighterWidthMultiplier == 3.0 &&
      highlighterAutoStraighten == true &&
      ballpointMinPressure == 0.7 &&
      ballpointMaxPressure == 1.1 &&
      textureType == 'none' &&
      textureIntensity == 0.5 &&
      textureRotationMode == 'followStroke' &&
      textureWetEdge == 0.0 &&
      textureScatterDensity == 1.0 &&
      textureScatterJitter == 0.0 &&
      textureScatterSizeVar == 0.0 &&
      !stampEnabled &&
      stampSpacing == 0.25 &&
      stampSizeJitter == 0.0 &&
      stampRotationJitter == 0.0 &&
      stampScatter == 0.0 &&
      stampSoftness == 0.6 &&
      stampElongation == 1.0 &&
      stampFlow == 0.5 &&
      stampOpacityJitter == 0.0 &&
      stampWetEdges == 0.0 &&
      stampMinSize == 0.15 &&
      stampTaperEntry == 6 &&
      stampTaperExit == 6 &&
      stampVelocitySize == 0.0 &&
      stampVelocityFlow == 0.0 &&
      stampGlazeMode == true &&
      stampHueJitter == 0.0 &&
      stampSatJitter == 0.0 &&
      stampBrightJitter == 0.0 &&
      stampTiltRotation == 0.0 &&
      stampTiltElongation == 0.0 &&
      stampDualTexture == 'none' &&
      stampDualScale == 1.0 &&
      stampDualBlend == 0.0 &&
      stampPressureColor == 0.0 &&
      stampWetMix == 0.0 &&
      stampRoundnessJitter == 0.0 &&
      stampColorGradient == 0.0 &&
      stampAccumCap == 0.0 &&
      stampSpacingPressure == 0.0 &&
      stampTransferVelocity == 0.0 &&
      stampSymmetryAxes == 0 &&
      !stampEraserMode &&
      !stampGrainScreenSpace &&
      stampShapeType == 0 &&
      stampGrainScale == 1.0 &&
      stampColorPressure == 0.0 &&
      pressureCurve.isLinear &&
      fountainVelocityCurve == VelocityCurve.goodnotes &&
      fountainVelocityReference == 2.0 &&
      stabilizerLevel == 0 &&
      watercolorSpread == 1.0 &&
      markerFlatness == 0.4 &&
      charcoalGrain == 0.5 &&
      useWideGamut == false;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProBrushSettings &&
        other.fountainMinPressure == fountainMinPressure &&
        other.fountainMaxPressure == fountainMaxPressure &&
        other.fountainTaperEntry == fountainTaperEntry &&
        other.fountainTaperExit == fountainTaperExit &&
        other.fountainVelocityInfluence == fountainVelocityInfluence &&
        other.fountainCurvatureInfluence == fountainCurvatureInfluence &&
        other.fountainTiltEnable == fountainTiltEnable &&
        other.fountainTiltInfluence == fountainTiltInfluence &&
        other.fountainTiltEllipseRatio == fountainTiltEllipseRatio &&
        other.fountainJitter == fountainJitter &&
        other.fountainVelocitySensitivity == fountainVelocitySensitivity &&
        other.fountainInkAccumulation == fountainInkAccumulation &&
        other.fountainSmoothPath == fountainSmoothPath &&
        other.fountainThinning == fountainThinning &&
        other.fountainPressureRate == fountainPressureRate &&
        other.fountainNibAngleDeg == fountainNibAngleDeg &&
        other.fountainNibStrength == fountainNibStrength &&
        other.pencilBaseOpacity == pencilBaseOpacity &&
        other.pencilMaxOpacity == pencilMaxOpacity &&
        other.pencilBlurRadius == pencilBlurRadius &&
        other.pencilMinPressure == pencilMinPressure &&
        other.pencilMaxPressure == pencilMaxPressure &&
        other.highlighterOpacity == highlighterOpacity &&
        other.highlighterWidthMultiplier == highlighterWidthMultiplier &&
        other.highlighterAutoStraighten == highlighterAutoStraighten &&
        other.ballpointMinPressure == ballpointMinPressure &&
        other.ballpointMaxPressure == ballpointMaxPressure &&
        other.textureType == textureType &&
        other.textureIntensity == textureIntensity &&
        other.textureRotationMode == textureRotationMode &&
        other.textureWetEdge == textureWetEdge &&
        other.textureScatterDensity == textureScatterDensity &&
        other.textureScatterJitter == textureScatterJitter &&
        other.textureScatterSizeVar == textureScatterSizeVar &&
        other.stampEnabled == stampEnabled &&
        other.stampSpacing == stampSpacing &&
        other.stampSizeJitter == stampSizeJitter &&
        other.stampRotationJitter == stampRotationJitter &&
        other.stampScatter == stampScatter &&
        other.stampSoftness == stampSoftness &&
        other.stampElongation == stampElongation &&
        other.stampFlow == stampFlow &&
        other.stampOpacityJitter == stampOpacityJitter &&
        other.stampWetEdges == stampWetEdges &&
        other.stampMinSize == stampMinSize &&
        other.stampTaperEntry == stampTaperEntry &&
        other.stampTaperExit == stampTaperExit &&
        other.stampVelocitySize == stampVelocitySize &&
        other.stampVelocityFlow == stampVelocityFlow &&
        other.stampGlazeMode == stampGlazeMode &&
        other.stampHueJitter == stampHueJitter &&
        other.stampSatJitter == stampSatJitter &&
        other.stampBrightJitter == stampBrightJitter &&
        other.stampTiltRotation == stampTiltRotation &&
        other.stampTiltElongation == stampTiltElongation &&
        other.stampDualTexture == stampDualTexture &&
        other.stampDualScale == stampDualScale &&
        other.stampDualBlend == stampDualBlend &&
        other.stampPressureColor == stampPressureColor &&
        other.stampWetMix == stampWetMix &&
        other.stampRoundnessJitter == stampRoundnessJitter &&
        other.stampColorGradient == stampColorGradient &&
        other.stampAccumCap == stampAccumCap &&
        other.stampSpacingPressure == stampSpacingPressure &&
        other.stampTransferVelocity == stampTransferVelocity &&
        other.stampSymmetryAxes == stampSymmetryAxes &&
        other.stampEraserMode == stampEraserMode &&
        other.stampGrainScreenSpace == stampGrainScreenSpace &&
        other.stampShapeType == stampShapeType &&
        other.stampGrainScale == stampGrainScale &&
        other.stampColorPressure == stampColorPressure &&
        other.pressureCurve == pressureCurve &&
        other.fountainVelocityCurve == fountainVelocityCurve &&
        other.fountainVelocityReference == fountainVelocityReference &&
        other.stabilizerLevel == stabilizerLevel &&
        other.watercolorSpread == watercolorSpread &&
        other.markerFlatness == markerFlatness &&
        other.charcoalGrain == charcoalGrain &&
        other.techAngleSnap == techAngleSnap &&
        other.techSnapAngleDeg == techSnapAngleDeg &&
        other.techEndpointSnap == techEndpointSnap &&
        other.techCornerSharpening == techCornerSharpening &&
        other.techGridSnap == techGridSnap &&
        other.techGridSize == techGridSize &&
        other.techStraightAssist == techStraightAssist &&
        other.techShowGuides == techShowGuides &&
        other.techParallelSnap == techParallelSnap &&
        other.techPerpSnap == techPerpSnap &&
        other.techMultiSegment == techMultiSegment &&
        other.useWideGamut == useWideGamut;
  }

  @override
  int get hashCode => Object.hashAll([
    fountainMinPressure,
    fountainMaxPressure,
    fountainTaperEntry,
    fountainTaperExit,
    fountainVelocityInfluence,
    fountainCurvatureInfluence,
    fountainTiltEnable,
    fountainTiltInfluence,
    fountainTiltEllipseRatio,
    fountainJitter,
    fountainVelocitySensitivity,
    fountainInkAccumulation,
    fountainSmoothPath,
    fountainThinning,
    fountainPressureRate,
    fountainNibAngleDeg,
    fountainNibStrength,
    pencilBaseOpacity,
    pencilMaxOpacity,
    pencilBlurRadius,
    pencilMinPressure,
    pencilMaxPressure,
    highlighterOpacity,
    highlighterWidthMultiplier,
    highlighterAutoStraighten,
    ballpointMinPressure,
    ballpointMaxPressure,
    textureType,
    textureIntensity,
    textureRotationMode,
    textureWetEdge,
    textureScatterDensity,
    textureScatterJitter,
    textureScatterSizeVar,
    stampEnabled,
    stampSpacing,
    stampSizeJitter,
    stampRotationJitter,
    stampScatter,
    stampSoftness,
    stampElongation,
    stampFlow,
    stampOpacityJitter,
    stampWetEdges,
    stampMinSize,
    stampTaperEntry,
    stampTaperExit,
    stampVelocitySize,
    stampVelocityFlow,
    stampGlazeMode,
    stampHueJitter,
    stampSatJitter,
    stampBrightJitter,
    stampTiltRotation,
    stampTiltElongation,
    stampDualTexture,
    stampDualScale,
    stampDualBlend,
    stampPressureColor,
    stampWetMix,
    stampRoundnessJitter,
    stampColorGradient,
    stampAccumCap,
    stampSpacingPressure,
    stampTransferVelocity,
    stampSymmetryAxes,
    stampEraserMode,
    stampGrainScreenSpace,
    stampShapeType,
    stampGrainScale,
    stampColorPressure,
    pressureCurve,
    fountainVelocityCurve,
    fountainVelocityReference,
    stabilizerLevel,
    watercolorSpread,
    markerFlatness,
    charcoalGrain,
    techAngleSnap,
    techSnapAngleDeg,
    techEndpointSnap,
    techCornerSharpening,
    techGridSnap,
    techGridSize,
    techStraightAssist,
    techShowGuides,
    techParallelSnap,
    techPerpSnap,
    techMultiSegment,
    useWideGamut,
  ]);
}
