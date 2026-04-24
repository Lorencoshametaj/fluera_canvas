// stroke_tessellation.h — Shared CPU-only tessellation for all GPU backends
// Used by: Vulkan (Android), D3D11 (Windows), Metal (iOS via Swift port)
//
// All functions are pure math — no GPU API calls, no platform dependencies.
// Input: raw touch points (stride 5: x, y, pressure, tiltX, tiltY)
// Output: triangle list appended to outVerts vector

#pragma once

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include "simd_math.h"

struct StrokeVertex {
  float x, y;
  float r, g, b, a;
};

namespace stroke {

// ─── LOD: Zoom-aware sample step for adaptive vertex density ────
// At scale >= 1.0: 1.5px (full quality, ~8 vertices per segment)
// At scale  0.5 : 3.0px (half vertices, invisible at this zoom)
// At scale  0.25: 6.0px (quarter vertices)
// Cap: 8px max to preserve gross shape at extreme zoom-out.
inline float lodSampleStep(float zoomScale) {
  if (zoomScale >= 1.0f) return 1.5f;
  float step = 1.5f / std::max(zoomScale, 0.1f);
  return std::min(step, 8.0f);
}

// Forward declaration (defined below, called by tessellateStroke)
inline void generateCircle(float cx, float cy, float radius, float r,
                           float g, float b, float a,
                           std::vector<StrokeVertex> &outVerts);

inline void tessellateStroke(const float *points, int pointCount,
                                        float r, float g, float b, float a,
                                        float strokeWidth, int pointStartIndex,
                                        int totalPoints,
                                        std::vector<StrokeVertex> &outVerts,
                                        float minPressure, float maxPressure) {
  if (pointCount < 2) return;

  // ─── Ballpoint: width formula matching Dart exactly ────────────
  // adjustedWidth = strokeWidth * (minP + 0.5 * (maxP - minP))
  // Constant width — no taper (start and end are symmetric)
  float adjustedWidth = strokeWidth * (minPressure + 0.5f * (maxPressure - minPressure));
  float baseHalfW = adjustedWidth * 0.5f;

  const int n = pointCount;

  // ─── Pass 1: Extract positions ─────────────────────────────────
  std::vector<float> px(n), py(n);
  for (int i = 0; i < n; i++) {
    px[i] = points[i * 5];
    py[i] = points[i * 5 + 1];
  }

  // ─── Pass 2: Smooth positions (2-pass bi-directional EMA) ─────
  // Eliminates digitizer noise that causes sawtooth at quad edges.
  // 🚀 SIMD: interleave X/Y into pairs for vectorized EMA
  if (n >= 4) {
    const float alpha = 0.25f;
    std::vector<float> xy(n * 2);
    for (int i = 0; i < n; i++) { xy[i*2] = px[i]; xy[i*2+1] = py[i]; }
    for (int pass = 0; pass < 2; pass++) {
      simd::emaForward2(xy.data() + 2, n - 2, alpha); // skip first/last
      simd::emaBackward2(xy.data() + 2, n - 2, alpha);
    }
    for (int i = 0; i < n; i++) { px[i] = xy[i*2]; py[i] = xy[i*2+1]; }
  }
  // ─── Pass 4: Catmull-Rom dense sampling of smoothed centerline ───
  // Instead of building quads from sparse smoothed points (visible segments
  // at speed), densely sample a Catmull-Rom spline at ~1.5px intervals.
  // Produces inherently smooth geometry — matches Dart BallpointBrush.
  struct Vec2 { float x, y; };
  std::vector<Vec2> dense;
  dense.reserve(n * 10);

  constexpr float SAMPLE_STEP = 1.5f;

  for (int seg = 0; seg < n - 1; seg++) {
    int i0 = (seg > 0) ? seg - 1 : 0;
    int i1 = seg;
    int i2 = seg + 1;
    int i3 = (seg + 2 < n) ? seg + 2 : n - 1;

    float x0 = px[i0], y0 = py[i0];
    float x1 = px[i1], y1 = py[i1];
    float x2 = px[i2], y2 = py[i2];
    float x3 = px[i3], y3 = py[i3];

    float segDx = x2 - x1, segDy = y2 - y1;
    float segLen = std::sqrt(segDx * segDx + segDy * segDy);
    int nSamples = std::max(2, (int)(segLen / SAMPLE_STEP) + 1);

    for (int s = 0; s < nSamples; s++) {
      if (seg < n - 2 && s == nSamples - 1) continue;

      float t = (float)s / (float)(nSamples - 1);
      float t2 = t * t;
      float t3 = t2 * t;

      float cx = 0.5f * ((2.0f * x1) +
                         (-x0 + x2) * t +
                         (2.0f * x0 - 5.0f * x1 + 4.0f * x2 - x3) * t2 +
                         (-x0 + 3.0f * x1 - 3.0f * x2 + x3) * t3);
      float cy = 0.5f * ((2.0f * y1) +
                         (-y0 + y2) * t +
                         (2.0f * y0 - 5.0f * y1 + 4.0f * y2 - y3) * t2 +
                         (-y0 + 3.0f * y1 - 3.0f * y2 + y3) * t3);
      dense.push_back({cx, cy});
    }
  }
  // Add final point
  dense.push_back({px[n - 1], py[n - 1]});

  int denseCount = (int)dense.size();
  if (denseCount < 2) return;

  // ─── Pass 5: Perpendicular offsets on dense samples ─────────────
  // With ~1.5px spacing, the normal direction changes gradually → smooth border.
  for (int i = 0; i < denseCount; i++) {
    float dtx = 0, dty = 0;
    if (i > 0) { dtx += dense[i].x - dense[i-1].x; dty += dense[i].y - dense[i-1].y; }
    if (i < denseCount - 1) { dtx += dense[i+1].x - dense[i].x; dty += dense[i+1].y - dense[i].y; }
    float tLen = std::sqrt(dtx * dtx + dty * dty);
    if (tLen < 0.0001f) { dtx = 1; dty = 0; tLen = 1; }
    dtx /= tLen; dty /= tLen;

    // Circles at caps
    if (i == 0 || i == denseCount - 1) {
      generateCircle(dense[i].x, dense[i].y, baseHalfW, r, g, b, a, outVerts);
    }

    // Quad strip to next point
    if (i < denseCount - 1) {
      float perpX = -dty, perpY = dtx;

      // Next point tangent
      float ntx = 0, nty = 0;
      if (i + 1 > 0) { ntx += dense[i+1].x - dense[i].x; nty += dense[i+1].y - dense[i].y; }
      if (i + 1 < denseCount - 1) { ntx += dense[i+2].x - dense[i+1].x; nty += dense[i+2].y - dense[i+1].y; }
      float nLen = std::sqrt(ntx * ntx + nty * nty);
      if (nLen < 0.0001f) { ntx = 1; nty = 0; nLen = 1; }
      ntx /= nLen; nty /= nLen;
      float perpX2 = -nty, perpY2 = ntx;

      outVerts.push_back({dense[i].x + perpX * baseHalfW, dense[i].y + perpY * baseHalfW, r, g, b, a});
      outVerts.push_back({dense[i].x - perpX * baseHalfW, dense[i].y - perpY * baseHalfW, r, g, b, a});
      outVerts.push_back({dense[i+1].x + perpX2 * baseHalfW, dense[i+1].y + perpY2 * baseHalfW, r, g, b, a});
      outVerts.push_back({dense[i].x - perpX * baseHalfW, dense[i].y - perpY * baseHalfW, r, g, b, a});
      outVerts.push_back({dense[i+1].x + perpX2 * baseHalfW, dense[i+1].y + perpY2 * baseHalfW, r, g, b, a});
      outVerts.push_back({dense[i+1].x - perpX2 * baseHalfW, dense[i+1].y - perpY2 * baseHalfW, r, g, b, a});
    }
  }
}

inline void generateCircle(float cx, float cy, float radius, float r,

                                      float g, float b, float a,

                                      std::vector<StrokeVertex> &outVerts) {

  // Adaptive segment count based on radius (more segments for larger strokes)
  // OPT-2: Reduced from max(8..24, r*2) — under MSAA 4x, fewer segments are
  // visually identical for small-to-medium strokes.
  int segments = std::max(6, std::min(16, (int)(radius * 1.5f)));

  for (int i = 0; i < segments; i++) {

    float a0 = 2.0f * (float)M_PI * (float)i / (float)segments;

    float a1 = 2.0f * (float)M_PI * (float)(i + 1) / (float)segments;

    float x0 = cx + radius * std::cos(a0);

    float y0 = cy + radius * std::sin(a0);

    float x1 = cx + radius * std::cos(a1);

    float y1 = cy + radius * std::sin(a1);

    // Triangle fan: center + two arc points

    outVerts.push_back({cx, cy, r, g, b, a});

    outVerts.push_back({x0, y0, r, g, b, a});

    outVerts.push_back({x1, y1, r, g, b, a});

  }

}

// ═══════════════════════════════════════════════════════════════════

// TESSELLATE MARKER (aligned with MarkerBrush.dart)

// ═══════════════════════════════════════════════════════════════════

inline void tessellateMarker(const float *points, int pointCount,
                                         float r, float g, float b, float a,
                                         float strokeWidth,
                                         std::vector<StrokeVertex> &outVerts) {
  if (pointCount < 2) return;

  // MarkerBrush.dart: constant width x2.5, opacity 0.7
  // ⚠️ Opacity 0.7 is applied Flutter-side via Opacity widget on the Texture.
  // Rendering at alpha=1.0 prevents Vulkan alpha-blending artifacts at edges.
  constexpr float WIDTH_MULT = 2.5f;
  float halfW = strokeWidth * WIDTH_MULT * 0.5f;
  float ma = a;  // Full alpha — marker opacity handled by Flutter Opacity widget

  // ── Step 1: Extract raw positions ──
  std::vector<float> px(pointCount), py(pointCount);
  for (int i = 0; i < pointCount; i++) {
    px[i] = points[i * 5];
    py[i] = points[i * 5 + 1];
  }

  // ── Step 2: Catmull-Rom spline dense sampling ──
  // Instead of offsetting sparse input points (→ saw-tooth), we densely
  // sample a smooth cubic spline through ALL input points at ~1px intervals.
  // This produces an inherently smooth centerline — no post-smoothing needed.
  struct Vec2 { float x, y; };
  std::vector<Vec2> dense;
  dense.reserve(pointCount * 10);

  constexpr float SAMPLE_STEP = 1.5f; // Sample every ~1.5 pixels along the curve

  for (int seg = 0; seg < pointCount - 1; seg++) {
    // Catmull-Rom control points: P0, P1, P2, P3
    // P1 and P2 are the segment endpoints; P0 and P3 are neighbors (clamped)
    int i0 = (seg > 0) ? seg - 1 : 0;
    int i1 = seg;
    int i2 = seg + 1;
    int i3 = (seg + 2 < pointCount) ? seg + 2 : pointCount - 1;

    float x0 = px[i0], y0 = py[i0];
    float x1 = px[i1], y1 = py[i1];
    float x2 = px[i2], y2 = py[i2];
    float x3 = px[i3], y3 = py[i3];

    // Estimate segment length for number of samples
    float segDx = x2 - x1, segDy = y2 - y1;
    float segLen = std::sqrt(segDx * segDx + segDy * segDy);
    int nSamples = std::max(2, (int)(segLen / SAMPLE_STEP) + 1);

    for (int s = 0; s < nSamples; s++) {
      // Don't duplicate the last point (it's the first point of next segment)
      if (seg < pointCount - 2 && s == nSamples - 1) continue;

      float t = (float)s / (float)(nSamples - 1);
      float t2 = t * t;
      float t3 = t2 * t;

      // Catmull-Rom basis (tension = 0.5)
      float cx = 0.5f * ((2.0f * x1) +
                         (-x0 + x2) * t +
                         (2.0f * x0 - 5.0f * x1 + 4.0f * x2 - x3) * t2 +
                         (-x0 + 3.0f * x1 - 3.0f * x2 + x3) * t3);
      float cy = 0.5f * ((2.0f * y1) +
                         (-y0 + y2) * t +
                         (2.0f * y0 - 5.0f * y1 + 4.0f * y2 - y3) * t2 +
                         (-y0 + 3.0f * y1 - 3.0f * y2 + y3) * t3);
      dense.push_back({cx, cy});
    }
  }
  // Add final point
  dense.push_back({px[pointCount - 1], py[pointCount - 1]});

  int denseCount = (int)dense.size();
  if (denseCount < 2) return;

  // ── Step 3: 🚀 SIMD perpendicular offsets on dense spline samples ──
  std::vector<Vec2> leftPts(denseCount), rightPts(denseCount);

  // Pre-compute tangent normals
  std::vector<float> normX(denseCount), normY(denseCount), halfWArr(denseCount, halfW);
  for (int i = 0; i < denseCount; i++) {
    float tx = 0, ty = 0;
    if (i > 0) { tx += dense[i].x - dense[i-1].x; ty += dense[i].y - dense[i-1].y; }
    if (i < denseCount - 1) { tx += dense[i+1].x - dense[i].x; ty += dense[i+1].y - dense[i].y; }
    float tLen = std::sqrt(tx * tx + ty * ty);
    if (tLen < 0.0001f) { tx = 1; ty = 0; tLen = 1; }
    tx /= tLen; ty /= tLen;
    normX[i] = -ty; normY[i] = tx; // perpendicular
  }

  // 🚀 Batch 4-wide perpendicular offsets via SIMD
  std::vector<float> denseX(denseCount), denseY(denseCount);
  std::vector<float> lxArr(denseCount), lyArr(denseCount), rxArr(denseCount), ryArr(denseCount);
  for (int i = 0; i < denseCount; i++) { denseX[i] = dense[i].x; denseY[i] = dense[i].y; }

  int i = 0;
  for (; i + 3 < denseCount; i += 4) {
    simd::perpOffset4(denseX.data() + i, denseY.data() + i,
                      normX.data() + i, normY.data() + i,
                      halfWArr.data() + i,
                      lxArr.data() + i, lyArr.data() + i,
                      rxArr.data() + i, ryArr.data() + i);
  }
  // Scalar remainder
  for (; i < denseCount; i++) {
    lxArr[i] = denseX[i] + normX[i] * halfW;
    lyArr[i] = denseY[i] + normY[i] * halfW;
    rxArr[i] = denseX[i] - normX[i] * halfW;
    ryArr[i] = denseY[i] - normY[i] * halfW;
  }

  for (int i = 0; i < denseCount; i++) {
    leftPts[i] = {lxArr[i], lyArr[i]};
    rightPts[i] = {rxArr[i], ryArr[i]};
  }

  // ── Step 4: Triangle strip ──
  for (int i = 0; i < denseCount - 1; i++) {
    outVerts.push_back({leftPts[i].x, leftPts[i].y, r, g, b, ma});
    outVerts.push_back({rightPts[i].x, rightPts[i].y, r, g, b, ma});
    outVerts.push_back({leftPts[i+1].x, leftPts[i+1].y, r, g, b, ma});
    outVerts.push_back({rightPts[i].x, rightPts[i].y, r, g, b, ma});
    outVerts.push_back({leftPts[i+1].x, leftPts[i+1].y, r, g, b, ma});
    outVerts.push_back({rightPts[i+1].x, rightPts[i+1].y, r, g, b, ma});
  }
}
// ═══════════════════════════════════════════════════════════════════
// TESSELLATE PENCIL (aligned with PencilBrush.dart)
// ═══════════════════════════════════════════════════════════════════

inline void tessellatePencil(const float *points, int pointCount,
                                         float r, float g, float b, float a,
                                         float strokeWidth, int pointStartIndex,
                                         int totalPoints,
                                         std::vector<StrokeVertex> &outVerts,
                                         float pencilBaseOpacity, float pencilMaxOpacity,
                                         float pencilMinPressure, float pencilMaxPressure) {
  if (pointCount < 2) return;

  // PencilBrush.dart alignment — use dynamic settings from Dart
  const float MIN_PRESSURE = pencilMinPressure;
  const float MAX_PRESSURE = pencilMaxPressure;
  constexpr int TAPER_POINTS = 4;
  constexpr float TAPER_START_FRAC = 0.15f;
  const float BASE_OPACITY = pencilBaseOpacity;
  const float MAX_OPACITY = pencilMaxOpacity;
  // Reserved for future grain/tilt effects (matches Dart pencil brush params)
  // constexpr float GRAIN_INTENSITY = 0.08f;
  // constexpr float TILT_WIDTH_BOOST = 0.5f;
  // constexpr float TILT_OPACITY_DROP = 0.15f;
  // constexpr float VELOCITY_ALPHA_DROP = 0.10f;
  float baseHalfW = strokeWidth * 0.5f;

  // No EMA on GPU — applied only in Dart committed stroke (all points at once).

  // ── Per-point outline with miter joins ──
  struct OutPt { float lx, ly, rx, ry, alpha; };
  std::vector<OutPt> outline(pointCount);

  for (int i = 0; i < pointCount; i++) {
    float px = points[i*5], py = points[i*5+1];
    float pp = points[i*5+2];
    int globalIdx = pointStartIndex + i;

    float halfW = baseHalfW * (MIN_PRESSURE + pp * (MAX_PRESSURE - MIN_PRESSURE));
    if (globalIdx < TAPER_POINTS) {
      float t = (float)globalIdx / (float)TAPER_POINTS;
      float ease = t * (2.0f - t);
      halfW *= TAPER_START_FRAC + ease * (1.0f - TAPER_START_FRAC);
    }

    // Alpha: simple per-point from pressure (matches Dart exactly)
    float pa = a * (BASE_OPACITY + (MAX_OPACITY - BASE_OPACITY) * pp);

    // Miter tangent from smoothed positions
    float tx = 0, ty = 0;
    if (i > 0) { tx += px - points[(i-1)*5]; ty += py - points[(i-1)*5+1]; }
    if (i < pointCount-1) { tx += points[(i+1)*5] - px; ty += points[(i+1)*5+1] - py; }
    float tLen = std::sqrt(tx*tx + ty*ty);
    if (tLen < 0.0001f) { tx = 1; ty = 0; tLen = 1; }
    tx /= tLen; ty /= tLen;
    float perpX = -ty, perpY = tx;

    outline[i] = {px + perpX*halfW, py + perpY*halfW,
                  px - perpX*halfW, py - perpY*halfW, pa};
  }

  // ── Triangle strip (NO caps) ──
  for (int i = 0; i < pointCount - 1; i++) {
    float pa = outline[i].alpha, na = outline[i+1].alpha;
    outVerts.push_back({outline[i].lx, outline[i].ly, r, g, b, pa});
    outVerts.push_back({outline[i].rx, outline[i].ry, r, g, b, pa});
    outVerts.push_back({outline[i+1].lx, outline[i+1].ly, r, g, b, na});
    outVerts.push_back({outline[i].rx, outline[i].ry, r, g, b, pa});
    outVerts.push_back({outline[i+1].lx, outline[i+1].ly, r, g, b, na});
    outVerts.push_back({outline[i+1].rx, outline[i+1].ry, r, g, b, na});
  }
}

// ═══════════════════════════════════════════════════════════════════

// SET TRANSFORM

// ═══════════════════════════════════════════════════════════════════


inline void tessellateTechnicalPen(const float *points, int pointCount,
                                              float r, float g, float b, float a,
                                              float strokeWidth,
                                              std::vector<StrokeVertex> &outVerts) {
  if (pointCount < 2) return;

  // Technical pen: constant half-width, no pressure, no taper
  const float halfW = strokeWidth * 0.5f;

  // Dense Catmull-Rom spline sampling at ~1.5px intervals
  const float SAMPLE_SPACING = 1.5f;
  std::vector<float> splineX, splineY;
  splineX.reserve(pointCount * 4);
  splineY.reserve(pointCount * 4);

  for (int i = 0; i < pointCount - 1; i++) {
    float x0 = (i > 0) ? points[(i - 1) * 5] : points[i * 5];
    float y0 = (i > 0) ? points[(i - 1) * 5 + 1] : points[i * 5 + 1];
    float x1 = points[i * 5];
    float y1 = points[i * 5 + 1];
    float x2 = points[(i + 1) * 5];
    float y2 = points[(i + 1) * 5 + 1];
    float x3 = (i < pointCount - 2) ? points[(i + 2) * 5] : x2;
    float y3 = (i < pointCount - 2) ? points[(i + 2) * 5 + 1] : y2;

    float segDx = x2 - x1;
    float segDy = y2 - y1;
    float segLen = std::sqrt(segDx * segDx + segDy * segDy);
    int steps = std::max(1, (int)(segLen / SAMPLE_SPACING));

    for (int s = 0; s < steps; s++) {
      float t = (float)s / (float)steps;
      float t2 = t * t;
      float t3 = t2 * t;
      // Catmull-Rom basis
      float sx = 0.5f * ((-t3 + 2*t2 - t) * x0 +
                         (3*t3 - 5*t2 + 2) * x1 +
                         (-3*t3 + 4*t2 + t) * x2 +
                         (t3 - t2) * x3);
      float sy = 0.5f * ((-t3 + 2*t2 - t) * y0 +
                         (3*t3 - 5*t2 + 2) * y1 +
                         (-3*t3 + 4*t2 + t) * y2 +
                         (t3 - t2) * y3);
      splineX.push_back(sx);
      splineY.push_back(sy);
    }
  }
  // Add endpoint
  splineX.push_back(points[(pointCount - 1) * 5]);
  splineY.push_back(points[(pointCount - 1) * 5 + 1]);

  int n = (int)splineX.size();
  if (n < 2) return;

  // Generate quads with perpendicular offset (constant width)
  for (int i = 0; i < n - 1; i++) {
    float px = splineX[i], py = splineY[i];
    float nx = splineX[i + 1], ny = splineY[i + 1];
    float dx = nx - px, dy = ny - py;
    float len = std::sqrt(dx * dx + dy * dy);
    if (len < 0.001f) continue;

    float perpX = -dy / len;
    float perpY = dx / len;

    // Quad: two triangles per segment
    outVerts.push_back({px + perpX * halfW, py + perpY * halfW, r, g, b, a});
    outVerts.push_back({px - perpX * halfW, py - perpY * halfW, r, g, b, a});
    outVerts.push_back({nx + perpX * halfW, ny + perpY * halfW, r, g, b, a});

    outVerts.push_back({px - perpX * halfW, py - perpY * halfW, r, g, b, a});
    outVerts.push_back({nx + perpX * halfW, ny + perpY * halfW, r, g, b, a});
    outVerts.push_back({nx - perpX * halfW, ny - perpY * halfW, r, g, b, a});
  }
}

// ═══════════════════════════════════════════════════════════════════
// FOUNTAIN PEN (STILOGRAFICA) TESSELLATION
// Circle+quad approach (proven gap-free, same as ballpoint) with
// variable width from full calligraphic pipeline: pressure accumulator,
// nib angle, thinning, tapering, EMA smoothing, rate limiting.
// ═══════════════════════════════════════════════════════════════════

inline void tessellateFountainPen(
    const float *points, int pointCount,
    float r, float g, float b, float a,
    float strokeWidth, int totalPoints,
    std::vector<StrokeVertex> &outVerts,
    float thinning, float nibAngleRad,
    float nibStrength, float pressureRate,
    int taperEntry) {

  if (pointCount < 2) return;

  const int n = pointCount;

  // ── Detect finger input (constant pressure) ──────────────────
  bool isFingerInput = true;
  {
    double firstP = (double)points[2];
    int checkLen = std::min(n, 10);
    double minP = firstP, maxP = firstP;
    for (int i = 1; i < checkLen; i++) {
      double p = (double)points[i * 5 + 2];
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }
    double range = maxP - minP;
    isFingerInput = (range < 0.15);
  }

  // ── Streamline + pressure accumulator + width calculation ─────
  // ALL computation in double to match Dart precision exactly
  std::vector<double> widths(n);
  std::vector<double> px(n), py(n);

  {
    const double streamT = 0.575; // Dart: 0.15 + (1 - 0.5) * 0.85
    double prevSX = (double)points[0], prevSY = (double)points[1];
    double accPressure = 0.25;
    double prevSp = 0.0;
    const double dStrokeWidth = (double)strokeWidth;
    const double dThinning = (double)thinning;
    const double dNibAngleRad = (double)nibAngleRad;
    const double dPressureRate = (double)pressureRate;
    const double effNibStr = isFingerInput
        ? std::min((double)nibStrength * 0.7, 0.7)
        : std::min((double)nibStrength * 0.75, 0.75);

    for (int i = 0; i < n; i++) {
      double rawX = (double)points[i * 5];
      double rawY = (double)points[i * 5 + 1];

      // Streamline EMA
      double sx, sy;
      if (i == 0) { sx = rawX; sy = rawY; }
      else {
        sx = prevSX + (rawX - prevSX) * streamT;
        sy = prevSY + (rawY - prevSY) * streamT;
      }
      double dist = (i > 0) ? std::sqrt((sx - prevSX) * (sx - prevSX) +
                                        (sy - prevSY) * (sy - prevSY)) : 0.0;
      px[i] = rawX; py[i] = rawY;
      prevSX = sx; prevSY = sy;

      // Direction
      double dirX = 0, dirY = 0;
      if (i > 0 && dist > 0.01) {
        double dx = rawX - (double)points[(i - 1) * 5];
        double dy = rawY - (double)points[(i - 1) * 5 + 1];
        double dlen = std::sqrt(dx * dx + dy * dy);
        if (dlen > 0) { dirX = dx / dlen; dirY = dy / dlen; }
      }

      // Pressure accumulator
      double pressure;
      double acceleration = 0.0;
      if (isFingerInput) {
        double sp = std::min(1.0, dist / (dStrokeWidth * 0.55));
        double rp = std::min(1.0, 1.0 - sp);
        accPressure = std::min(1.0,
            accPressure + (rp - accPressure) * sp * dPressureRate);
        pressure = accPressure;
        acceleration = sp - prevSp;
        prevSp = sp;
      } else {
        pressure = (double)points[i * 5 + 2];
      }

      // Thinning
      double thinned = std::clamp(0.5 - dThinning * (0.5 - pressure), 0.02, 1.0);
      double w = dStrokeWidth * thinned;

      // Finger acceleration modulation
      if (isFingerInput) {
        double accelMod = std::clamp(1.0 - acceleration * 0.6, 0.88, 1.12);
        w *= accelMod;
      }

      // Nib angle
      if (dirX != 0 || dirY != 0) {
        double strokeAngle = std::atan2(dirY, dirX);
        double angleDiff = std::fmod(std::abs(strokeAngle - dNibAngleRad), M_PI);
        double perp = std::sin(angleDiff);
        w *= (1.0 - effNibStr + perp * effNibStr * 2.0);
      }

      // Curvature modulation
      if (i >= 2) {
        double p0x = (double)points[(i - 2) * 5], p0y = (double)points[(i - 2) * 5 + 1];
        double p1x = (double)points[(i - 1) * 5], p1y = (double)points[(i - 1) * 5 + 1];
        double d1x = p1x - p0x, d1y = p1y - p0y;
        double d2x = rawX - p1x, d2y = rawY - p1y;
        double cross = std::abs(d1x * d2y - d1y * d2x);
        double dot = d1x * d2x + d1y * d2y;
        double angle = std::atan2(cross, dot);
        double curv = std::clamp(angle / M_PI, 0.0, 1.0);
        w *= 1.0 + curv * 0.35;
      }

      // Velocity modifier (stylus only)
      if (!isFingerInput && dist > 0) {
        double sp = std::min(1.0, dist / dStrokeWidth);
        double velMod = std::clamp(1.15 - sp * 0.5 * 0.6, 0.5, 1.3);
        w *= velMod;
      }

      widths[i] = std::clamp(w, dStrokeWidth * 0.12, dStrokeWidth * 3.5);
    }
  }

  // ── Tapering (entry only, easeInOutCubic) ─────────────────────
  {
    int entryLen = std::min(taperEntry, n - 1);
    for (int i = 0; i < entryLen; i++) {
      double t = (double)i / taperEntry;
      double factor;
      if (t < 0.5) factor = 4.0 * t * t * t;
      else { double v = -2.0 * t + 2.0; factor = 1.0 - (v * v * v) / 2.0; }
      widths[i] *= std::clamp(factor, 0.0, 1.0);
    }
  }

  // ── 2-pass EMA smoothing on widths (alpha=0.35) ───────────────
  {
    const double alpha = 0.35;
    double sm = widths[0];
    for (int i = 1; i < n; i++) {
      sm = sm * alpha + widths[i] * (1.0 - alpha);
      widths[i] = sm;
    }
    sm = widths[n - 1];
    for (int i = n - 2; i >= 0; i--) {
      sm = sm * alpha + widths[i] * (1.0 - alpha);
      widths[i] = sm;
    }
  }

  // ── Rate limiting (maxChangeRate=0.12) ────────────────────────
  {
    const double mcr = 0.12;
    for (int i = 1; i < n; i++) {
      double prev = widths[i - 1];
      widths[i] = std::clamp(widths[i], prev * (1.0 - mcr), prev * (1.0 + mcr));
    }
    for (int i = n - 2; i >= 0; i--) {
      double next = widths[i + 1];
      widths[i] = std::clamp(widths[i], next * (1.0 - mcr), next * (1.0 + mcr));
    }
  }

  // Post-smooth: SKIPPED for live strokes (matches Dart: if (!liveStroke))

  // ── Position smoothing (2-pass bi-directional) ────────────────
  if (n >= 4) {
    const double posAlpha = 0.3;
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 1; i < n - 1; i++) {
        px[i] = px[i - 1] * posAlpha + px[i] * (1.0 - posAlpha);
        py[i] = py[i - 1] * posAlpha + py[i] * (1.0 - posAlpha);
      }
      for (int i = n - 2; i > 0; i--) {
        px[i] = px[i + 1] * posAlpha + px[i] * (1.0 - posAlpha);
        py[i] = py[i + 1] * posAlpha + py[i] * (1.0 - posAlpha);
      }
    }
  }

  // ── Curvature-adaptive smoothing (extra smooth at sharp turns) ─
  if (n >= 5) {
    for (int i = 2; i < n - 2; i++) {
      double v1x = px[i] - px[i - 1], v1y = py[i] - py[i - 1];
      double v2x = px[i + 1] - px[i], v2y = py[i + 1] - py[i];
      double crossV = std::abs(v1x * v2y - v1y * v2x);
      double dotV = v1x * v2x + v1y * v2y;
      double angle = std::atan2(crossV, dotV);
      double blend = std::clamp(angle / M_PI, 0.0, 1.0) * 0.4;
      if (blend > 0.02) {
        double avgX = (px[i - 1] + px[i + 1]) * 0.5;
        double avgY = (py[i - 1] + py[i + 1]) * 0.5;
        px[i] = px[i] * (1.0 - blend) + avgX * blend;
        py[i] = py[i] * (1.0 - blend) + avgY * blend;
      }
    }
  }

  // ── Arc-length reparameterization ─────────────────────────────
  if (n >= 10) {
    std::vector<double> arcLen(n);
    arcLen[0] = 0.0;
    for (int i = 1; i < n; i++) {
      double dx = px[i] - px[i - 1], dy = py[i] - py[i - 1];
      arcLen[i] = arcLen[i - 1] + std::sqrt(dx * dx + dy * dy);
    }
    double totalLen = arcLen[n - 1];
    if (totalLen > 1.0) {
      int numSamples = n;
      double step = totalLen / (numSamples - 1);
      std::vector<double> rPx(numSamples), rPy(numSamples), rW(numSamples);
      rPx[0] = px[0]; rPy[0] = py[0]; rW[0] = widths[0];
      int seg = 0;
      for (int s = 1; s < numSamples - 1; s++) {
        double targetLen = s * step;
        while (seg < n - 2 && arcLen[seg + 1] < targetLen) seg++;
        double segLen = arcLen[seg + 1] - arcLen[seg];
        double frac = (segLen > 0.001) ? (targetLen - arcLen[seg]) / segLen : 0.0;
        rPx[s] = px[seg] + (px[seg + 1] - px[seg]) * frac;
        rPy[s] = py[seg] + (py[seg + 1] - py[seg]) * frac;
        rW[s] = widths[seg] + (widths[seg + 1] - widths[seg]) * frac;
      }
      rPx[numSamples - 1] = px[n - 1]; rPy[numSamples - 1] = py[n - 1];
      rW[numSamples - 1] = widths[n - 1];
      for (int i = 0; i < numSamples; i++) {
        px[i] = rPx[i]; py[i] = rPy[i]; widths[i] = rW[i];
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // OUTLINE TESSELLATION (calligraphic flat edges, like Dart)
  // ═══════════════════════════════════════════════════════════════

  // ── 7-point weighted tangent computation ──────────────────────
  std::vector<double> tanX(n), tanY(n);
  for (int i = 0; i < n; i++) {
    double tx, ty;
    if (i == 0) { tx = px[1] - px[0]; ty = py[1] - py[0]; }
    else if (i == n - 1) { tx = px[n - 1] - px[n - 2]; ty = py[n - 1] - py[n - 2]; }
    else {
      tx = px[i + 1] - px[i - 1]; ty = py[i + 1] - py[i - 1];
      if (i >= 2 && i < n - 2) {
        double fx = px[i + 2] - px[i - 2], fy = py[i + 2] - py[i - 2];
        tx = tx * 0.6 + fx * 0.3; ty = ty * 0.6 + fy * 0.3;
        if (i >= 3 && i < n - 3) {
          double vfx = px[i + 3] - px[i - 3], vfy = py[i + 3] - py[i - 3];
          tx += vfx * 0.1; ty += vfy * 0.1;
        }
      }
    }
    double tlen = std::sqrt(tx * tx + ty * ty);
    if (tlen > 0) { tanX[i] = tx / tlen; tanY[i] = ty / tlen; }
    else { tanX[i] = 1; tanY[i] = 0; }
  }

  // ── 🚀 SIMD Outline generation (left/right from tangent normals) ───
  std::vector<double> leftX(n), leftY(n), rightX(n), rightY(n);
  {
    // Prepare float arrays for SIMD batch processing
    std::vector<float> fPx(n), fPy(n), fNx(n), fNy(n), fHw(n);
    std::vector<float> fLx(n), fLy(n), fRx(n), fRy(n);
    for (int i = 0; i < n; i++) {
      fPx[i] = (float)px[i]; fPy[i] = (float)py[i];
      fNx[i] = (float)(-tanY[i]); fNy[i] = (float)tanX[i];
      fHw[i] = (float)(widths[i] * 0.5);
    }
    // SIMD batch: 4 points at a time
    int si = 0;
    for (; si + 3 < n; si += 4) {
      simd::perpOffset4(fPx.data() + si, fPy.data() + si,
                        fNx.data() + si, fNy.data() + si,
                        fHw.data() + si,
                        fLx.data() + si, fLy.data() + si,
                        fRx.data() + si, fRy.data() + si);
    }
    // Scalar remainder
    for (; si < n; si++) {
      fLx[si] = fPx[si] + fNx[si] * fHw[si];
      fLy[si] = fPy[si] + fNy[si] * fHw[si];
      fRx[si] = fPx[si] - fNx[si] * fHw[si];
      fRy[si] = fPy[si] - fNy[si] * fHw[si];
    }
    for (int i = 0; i < n; i++) {
      leftX[i] = fLx[i]; leftY[i] = fLy[i];
      rightX[i] = fRx[i]; rightY[i] = fRy[i];
    }
  }

  // ── Outline smoothing (bi-directional) ────────────────────────
  {
    double avgW = 0;
    for (int i = 0; i < n; i++) avgW += widths[i];
    avgW /= n;
    double alpha = std::clamp(0.35 + avgW / 40.0, 0.35, 0.65);
    int passes = (avgW > 8.0) ? 3 : 2;
    for (int pass = 0; pass < passes; pass++) {
      for (int i = 1; i < n - 1; i++) {
        leftX[i] = leftX[i - 1] * alpha + leftX[i] * (1.0 - alpha);
        leftY[i] = leftY[i - 1] * alpha + leftY[i] * (1.0 - alpha);
        rightX[i] = rightX[i - 1] * alpha + rightX[i] * (1.0 - alpha);
        rightY[i] = rightY[i - 1] * alpha + rightY[i] * (1.0 - alpha);
      }
      for (int i = n - 2; i > 0; i--) {
        leftX[i] = leftX[i + 1] * alpha + leftX[i] * (1.0 - alpha);
        leftY[i] = leftY[i + 1] * alpha + leftY[i] * (1.0 - alpha);
        rightX[i] = rightX[i + 1] * alpha + rightX[i] * (1.0 - alpha);
        rightY[i] = rightY[i + 1] * alpha + rightY[i] * (1.0 - alpha);
      }
    }
  }

  // ── 🚀 SIMD Chaikin corner-cutting subdivision (1 iteration) ─────
  {
    int outLen = 2 * (n - 1) + 2;
    std::vector<double> cLX(outLen), cLY(outLen), cRX(outLen), cRY(outLen);
    int ci = 0;
    cLX[ci] = leftX[0]; cLY[ci] = leftY[0]; cRX[ci] = rightX[0]; cRY[ci] = rightY[0]; ci++;

    // Prepare float arrays for SIMD Chaikin
    std::vector<float> flx(n), fly(n), frx(n), fry(n);
    for (int i = 0; i < n; i++) {
      flx[i] = (float)leftX[i]; fly[i] = (float)leftY[i];
      frx[i] = (float)rightX[i]; fry[i] = (float)rightY[i];
    }

    // SIMD batch: 4 pairs at a time
    int si = 0;
    for (; si + 3 < n - 1; si += 4) {
      float out75lx[4], out25lx[4], out75ly[4], out25ly[4];
      float out75rx[4], out25rx[4], out75ry[4], out25ry[4];
      simd::chaikin4(flx.data() + si, flx.data() + si + 1, out75lx, out25lx);
      simd::chaikin4(fly.data() + si, fly.data() + si + 1, out75ly, out25ly);
      simd::chaikin4(frx.data() + si, frx.data() + si + 1, out75rx, out25rx);
      simd::chaikin4(fry.data() + si, fry.data() + si + 1, out75ry, out25ry);
      for (int j = 0; j < 4; j++) {
        cLX[ci] = out75lx[j]; cLY[ci] = out75ly[j];
        cRX[ci] = out75rx[j]; cRY[ci] = out75ry[j]; ci++;
        cLX[ci] = out25lx[j]; cLY[ci] = out25ly[j];
        cRX[ci] = out25rx[j]; cRY[ci] = out25ry[j]; ci++;
      }
    }
    // Scalar remainder
    for (; si < n - 1; si++) {
      cLX[ci] = leftX[si] * 0.75 + leftX[si + 1] * 0.25;
      cLY[ci] = leftY[si] * 0.75 + leftY[si + 1] * 0.25;
      cRX[ci] = rightX[si] * 0.75 + rightX[si + 1] * 0.25;
      cRY[ci] = rightY[si] * 0.75 + rightY[si + 1] * 0.25; ci++;
      cLX[ci] = leftX[si] * 0.25 + leftX[si + 1] * 0.75;
      cLY[ci] = leftY[si] * 0.25 + leftY[si + 1] * 0.75;
      cRX[ci] = rightX[si] * 0.25 + rightX[si + 1] * 0.75;
      cRY[ci] = rightY[si] * 0.25 + rightY[si + 1] * 0.75; ci++;
    }
    cLX[ci] = leftX[n - 1]; cLY[ci] = leftY[n - 1];
    cRX[ci] = rightX[n - 1]; cRY[ci] = rightY[n - 1]; ci++;
    leftX.resize(ci); leftY.resize(ci); rightX.resize(ci); rightY.resize(ci);
    for (int i = 0; i < ci; i++) {
      leftX[i] = cLX[i]; leftY[i] = cLY[i];
      rightX[i] = cRX[i]; rightY[i] = cRY[i];
    }
  }

  const int outN = (int)leftX.size();

  // ── Crossed-outline fix ───────────────────────────────────────
  for (int i = 1; i < outN; i++) {
    double pLRx = rightX[i - 1] - leftX[i - 1], pLRy = rightY[i - 1] - leftY[i - 1];
    double cLRx = rightX[i] - leftX[i], cLRy = rightY[i] - leftY[i];
    double cross = pLRx * cLRy - pLRy * cLRx;
    double dot = pLRx * cLRx + pLRy * cLRy;
    double pD = std::sqrt(pLRx * pLRx + pLRy * pLRy);
    double cD = std::sqrt(cLRx * cLRx + cLRy * cLRy);
    if (dot < 0 || std::abs(cross) > pD * cD * 0.95) {
      double cx = (leftX[i] + rightX[i]) * 0.5, cy = (leftY[i] + rightY[i]) * 0.5;
      leftX[i] = cx; leftY[i] = cy; rightX[i] = cx; rightY[i] = cy;
    }
  }

  // ── Triangle strip with uniform solid alpha ──────────────────
  // Convert double→float only here for GPU vertex output
  for (int i = 0; i < outN - 1; i++) {
    int ni = i + 1;
    outVerts.push_back({(float)leftX[i], (float)leftY[i], r, g, b, a});
    outVerts.push_back({(float)rightX[i], (float)rightY[i], r, g, b, a});
    outVerts.push_back({(float)leftX[ni], (float)leftY[ni], r, g, b, a});
    outVerts.push_back({(float)rightX[i], (float)rightY[i], r, g, b, a});
    outVerts.push_back({(float)leftX[ni], (float)leftY[ni], r, g, b, a});
    outVerts.push_back({(float)rightX[ni], (float)rightY[ni], r, g, b, a});
  }

  // ── End cap: semicircular fan (base from LEFT, like Dart) ──────
  {
    double lx = leftX[outN - 1], ly = leftY[outN - 1];
    double rx = rightX[outN - 1], ry = rightY[outN - 1];
    double cx = (lx + rx) * 0.5, cy = (ly + ry) * 0.5;
    double rad = std::sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry)) * 0.5;
    if (rad > 0.1) {
      const int segs = 10;
      double base = std::atan2(ly - cy, lx - cx);
      for (int s = 0; s < segs; s++) {
        double a0 = base - M_PI * s / segs;
        double a1 = base - M_PI * (s + 1) / segs;
        outVerts.push_back({(float)cx, (float)cy, r, g, b, a});
        outVerts.push_back({(float)(cx + rad * std::cos(a0)), (float)(cy + rad * std::sin(a0)), r, g, b, a});
        outVerts.push_back({(float)(cx + rad * std::cos(a1)), (float)(cy + rad * std::sin(a1)), r, g, b, a});
      }
    }
  }
  // ── Start cap: semicircular fan (base from RIGHT, like Dart) ──
  {
    double lx = leftX[0], ly = leftY[0];
    double rx = rightX[0], ry = rightY[0];
    double cx = (lx + rx) * 0.5, cy = (ly + ry) * 0.5;
    double rad = std::sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry)) * 0.5;
    if (rad > 0.1) {
      const int segs = 10;
      double base = std::atan2(ry - cy, rx - cx);
      for (int s = 0; s < segs; s++) {
        double a0 = base - M_PI * s / segs;
        double a1 = base - M_PI * (s + 1) / segs;
        outVerts.push_back({(float)cx, (float)cy, r, g, b, a});
        outVerts.push_back({(float)(cx + rad * std::cos(a0)), (float)(cy + rad * std::sin(a0)), r, g, b, a});
        outVerts.push_back({(float)(cx + rad * std::cos(a1)), (float)(cy + rad * std::sin(a1)), r, g, b, a});
      }
    }
  }

  // Edge feathering: SKIPPED for live strokes (matches Dart: if (!liveStroke))
}


} // namespace stroke
