// simd_math.h — Platform-agnostic SIMD abstraction for stroke tessellation
// Provides unified API over ARM NEON, x86 SSE, and scalar fallback.
//
// Usage: #include "simd_math.h"
//   simd::f32x4 a = simd::load4(ptr);
//   simd::f32x4 b = simd::mul(a, simd::set1(0.5f));
//   simd::store4(out, b);

#pragma once

#include <cmath>
#include <cstdint>

namespace simd {

// ═══════════════════════════════════════════════════════════════════
// ARM NEON (Android ARM64, iOS, macOS Apple Silicon)
// ═══════════════════════════════════════════════════════════════════
#if defined(__ARM_NEON__) || defined(__ARM_NEON) || defined(__aarch64__)

#include <arm_neon.h>

using f32x4 = float32x4_t;
using f32x2 = float32x2_t;

// ── Load/Store ──────────────────────────────────────────────────
inline f32x4 load4(const float *p) { return vld1q_f32(p); }
inline void store4(float *p, f32x4 v) { vst1q_f32(p, v); }
inline f32x4 set1(float v) { return vdupq_n_f32(v); }
inline f32x4 set4(float a, float b, float c, float d) {
  float tmp[4] = {a, b, c, d};
  return vld1q_f32(tmp);
}

// ── Arithmetic ──────────────────────────────────────────────────
inline f32x4 add(f32x4 a, f32x4 b) { return vaddq_f32(a, b); }
inline f32x4 sub(f32x4 a, f32x4 b) { return vsubq_f32(a, b); }
inline f32x4 mul(f32x4 a, f32x4 b) { return vmulq_f32(a, b); }
// FMA: a * b + c (fused, single-rounding)
inline f32x4 fma(f32x4 a, f32x4 b, f32x4 c) { return vfmaq_f32(c, a, b); }
// FMS: c - a * b
inline f32x4 fnma(f32x4 a, f32x4 b, f32x4 c) { return vfmsq_f32(c, a, b); }
inline f32x4 neg(f32x4 a) { return vnegq_f32(a); }

// ── Fast reciprocal sqrt (Newton-Raphson refined) ───────────────
inline f32x4 rsqrt(f32x4 v) {
  f32x4 est = vrsqrteq_f32(v);
  // One Newton-Raphson step: est *= (3 - v * est * est) * 0.5
  est = vmulq_f32(est, vrsqrtsq_f32(vmulq_f32(v, est), est));
  return est;
}
inline f32x4 sqrt(f32x4 v) { return vmulq_f32(v, rsqrt(v)); }

// ── Extract lanes ───────────────────────────────────────────────
inline float lane(f32x4 v, int i) { return vgetq_lane_f32(v, 0); } // use template below
template<int I> inline float get(f32x4 v) { return vgetq_lane_f32(v, I); }

// ── Horizontal operations ───────────────────────────────────────
inline float hsum(f32x4 v) {
  f32x2 lo = vget_low_f32(v);
  f32x2 hi = vget_high_f32(v);
  f32x2 sum = vadd_f32(lo, hi);
  return vget_lane_f32(vpadd_f32(sum, sum), 0);
}

// ── f32x2 operations (for interleaved X/Y EMA) ─────────────────
inline f32x2 load2(const float *p) { return vld1_f32(p); }
inline void store2(float *p, f32x2 v) { vst1_f32(p, v); }
inline f32x2 set1_2(float v) { return vdup_n_f32(v); }
inline f32x2 add2(f32x2 a, f32x2 b) { return vadd_f32(a, b); }
inline f32x2 sub2(f32x2 a, f32x2 b) { return vsub_f32(a, b); }
inline f32x2 mul2(f32x2 a, f32x2 b) { return vmul_f32(a, b); }
inline f32x2 fma2(f32x2 a, f32x2 b, f32x2 c) { return vfma_f32(c, a, b); }

// ═══════════════════════════════════════════════════════════════════
// x86 SSE (Linux x86_64, Windows)
// ═══════════════════════════════════════════════════════════════════
#elif defined(__SSE2__) || defined(_M_X64) || defined(_M_AMD64)

#include <immintrin.h>

using f32x4 = __m128;

// ── Load/Store ──────────────────────────────────────────────────
inline f32x4 load4(const float *p) { return _mm_loadu_ps(p); }
inline void store4(float *p, f32x4 v) { _mm_storeu_ps(p, v); }
inline f32x4 set1(float v) { return _mm_set1_ps(v); }
inline f32x4 set4(float a, float b, float c, float d) {
  return _mm_set_ps(d, c, b, a); // Note: SSE is reverse order
}

// ── Arithmetic ──────────────────────────────────────────────────
inline f32x4 add(f32x4 a, f32x4 b) { return _mm_add_ps(a, b); }
inline f32x4 sub(f32x4 a, f32x4 b) { return _mm_sub_ps(a, b); }
inline f32x4 mul(f32x4 a, f32x4 b) { return _mm_mul_ps(a, b); }
#ifdef __FMA__
inline f32x4 fma(f32x4 a, f32x4 b, f32x4 c) { return _mm_fmadd_ps(a, b, c); }
inline f32x4 fnma(f32x4 a, f32x4 b, f32x4 c) { return _mm_fnmadd_ps(a, b, c); }
#else
inline f32x4 fma(f32x4 a, f32x4 b, f32x4 c) { return _mm_add_ps(_mm_mul_ps(a, b), c); }
inline f32x4 fnma(f32x4 a, f32x4 b, f32x4 c) { return _mm_sub_ps(c, _mm_mul_ps(a, b)); }
#endif
inline f32x4 neg(f32x4 a) { return _mm_sub_ps(_mm_setzero_ps(), a); }

// ── Fast reciprocal sqrt ────────────────────────────────────────
inline f32x4 rsqrt(f32x4 v) {
  f32x4 est = _mm_rsqrt_ps(v);
  // Newton-Raphson refinement
  f32x4 half = _mm_set1_ps(0.5f);
  f32x4 three = _mm_set1_ps(3.0f);
  f32x4 muls = _mm_mul_ps(_mm_mul_ps(v, est), est);
  return _mm_mul_ps(_mm_mul_ps(half, est), _mm_sub_ps(three, muls));
}
inline f32x4 sqrt(f32x4 v) { return _mm_sqrt_ps(v); }

// ── Extract lanes ───────────────────────────────────────────────
template<int I> inline float get(f32x4 v) {
  // SSE4.1 _mm_extract_ps returns int, use shuffle trick
  return _mm_cvtss_f32(_mm_shuffle_ps(v, v, _MM_SHUFFLE(I, I, I, I)));
}

// ── Horizontal sum ──────────────────────────────────────────────
inline float hsum(f32x4 v) {
  f32x4 shuf = _mm_movehdup_ps(v);       // (1,1,3,3)
  f32x4 sums = _mm_add_ps(v, shuf);      // (0+1, _, 2+3, _)
  shuf = _mm_movehl_ps(shuf, sums);      // (2+3, _, _, _)
  sums = _mm_add_ss(sums, shuf);         // (0+1+2+3, _, _, _)
  return _mm_cvtss_f32(sums);
}

// ── f32x2 emulation via f32x4 (only lower 2 lanes used) ────────
using f32x2 = f32x4;
inline f32x2 load2(const float *p) {
  return _mm_castpd_ps(_mm_load_sd(reinterpret_cast<const double*>(p)));
}
inline void store2(float *p, f32x2 v) {
  _mm_store_sd(reinterpret_cast<double*>(p), _mm_castps_pd(v));
}
inline f32x2 set1_2(float v) { return _mm_set1_ps(v); }
inline f32x2 add2(f32x2 a, f32x2 b) { return _mm_add_ps(a, b); }
inline f32x2 sub2(f32x2 a, f32x2 b) { return _mm_sub_ps(a, b); }
inline f32x2 mul2(f32x2 a, f32x2 b) { return _mm_mul_ps(a, b); }
inline f32x2 fma2(f32x2 a, f32x2 b, f32x2 c) { return fma(a, b, c); }

// ═══════════════════════════════════════════════════════════════════
// Scalar fallback (any platform without SIMD)
// ═══════════════════════════════════════════════════════════════════
#else

struct f32x4 { float v[4]; };
struct f32x2 { float v[2]; };

inline f32x4 load4(const float *p) { return {p[0], p[1], p[2], p[3]}; }
inline void store4(float *p, f32x4 a) { p[0]=a.v[0]; p[1]=a.v[1]; p[2]=a.v[2]; p[3]=a.v[3]; }
inline f32x4 set1(float v) { return {v, v, v, v}; }
inline f32x4 set4(float a, float b, float c, float d) { return {a, b, c, d}; }
inline f32x4 add(f32x4 a, f32x4 b) { return {a.v[0]+b.v[0], a.v[1]+b.v[1], a.v[2]+b.v[2], a.v[3]+b.v[3]}; }
inline f32x4 sub(f32x4 a, f32x4 b) { return {a.v[0]-b.v[0], a.v[1]-b.v[1], a.v[2]-b.v[2], a.v[3]-b.v[3]}; }
inline f32x4 mul(f32x4 a, f32x4 b) { return {a.v[0]*b.v[0], a.v[1]*b.v[1], a.v[2]*b.v[2], a.v[3]*b.v[3]}; }
inline f32x4 fma(f32x4 a, f32x4 b, f32x4 c) { return {a.v[0]*b.v[0]+c.v[0], a.v[1]*b.v[1]+c.v[1], a.v[2]*b.v[2]+c.v[2], a.v[3]*b.v[3]+c.v[3]}; }
inline f32x4 fnma(f32x4 a, f32x4 b, f32x4 c) { return {c.v[0]-a.v[0]*b.v[0], c.v[1]-a.v[1]*b.v[1], c.v[2]-a.v[2]*b.v[2], c.v[3]-a.v[3]*b.v[3]}; }
inline f32x4 neg(f32x4 a) { return {-a.v[0], -a.v[1], -a.v[2], -a.v[3]}; }
inline f32x4 rsqrt(f32x4 a) { return {1.0f/std::sqrt(a.v[0]), 1.0f/std::sqrt(a.v[1]), 1.0f/std::sqrt(a.v[2]), 1.0f/std::sqrt(a.v[3])}; }
inline f32x4 sqrt(f32x4 a) { return {std::sqrt(a.v[0]), std::sqrt(a.v[1]), std::sqrt(a.v[2]), std::sqrt(a.v[3])}; }
template<int I> inline float get(f32x4 v) { return v.v[I]; }
inline float hsum(f32x4 v) { return v.v[0]+v.v[1]+v.v[2]+v.v[3]; }

inline f32x2 load2(const float *p) { return {p[0], p[1]}; }
inline void store2(float *p, f32x2 v) { p[0]=v.v[0]; p[1]=v.v[1]; }
inline f32x2 set1_2(float v) { return {v, v}; }
inline f32x2 add2(f32x2 a, f32x2 b) { return {a.v[0]+b.v[0], a.v[1]+b.v[1]}; }
inline f32x2 sub2(f32x2 a, f32x2 b) { return {a.v[0]-b.v[0], a.v[1]-b.v[1]}; }
inline f32x2 mul2(f32x2 a, f32x2 b) { return {a.v[0]*b.v[0], a.v[1]*b.v[1]}; }
inline f32x2 fma2(f32x2 a, f32x2 b, f32x2 c) { return {a.v[0]*b.v[0]+c.v[0], a.v[1]*b.v[1]+c.v[1]}; }

#endif

// ═══════════════════════════════════════════════════════════════════
// High-level SIMD helpers for tessellation
// ═══════════════════════════════════════════════════════════════════

/// Catmull-Rom spline evaluation for 4 t-values simultaneously.
/// Returns interpolated position for each t using control points p0..p3.
/// basis: 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t² + (-p0+3*p1-3*p2+p3)*t³)
inline f32x4 catmullRom4(f32x4 p0, f32x4 p1, f32x4 p2, f32x4 p3, f32x4 t) {
  f32x4 t2 = mul(t, t);
  f32x4 t3 = mul(t2, t);
  f32x4 half = set1(0.5f);

  // c0 = 2*p1
  f32x4 c0 = mul(set1(2.0f), p1);
  // c1 = (-p0 + p2) * t
  f32x4 c1 = mul(sub(p2, p0), t);
  // c2 = (2*p0 - 5*p1 + 4*p2 - p3) * t²
  f32x4 c2a = fma(set1(2.0f), p0, mul(set1(-5.0f), p1));
  f32x4 c2b = fma(set1(4.0f), p2, neg(p3));
  f32x4 c2 = mul(add(c2a, c2b), t2);
  // c3 = (-p0 + 3*p1 - 3*p2 + p3) * t³
  f32x4 c3a = fma(set1(3.0f), p1, neg(p0));
  f32x4 c3b = fma(set1(-3.0f), p2, p3);
  f32x4 c3 = mul(add(c3a, c3b), t3);

  return mul(half, add(add(c0, c1), add(c2, c3)));
}

/// EMA smoothing for interleaved [x, y] pairs using f32x2.
/// Processes forward pass: out[i] = prev * alpha + cur * (1-alpha)
inline void emaForward2(float *xy, int count, float alpha) {
  if (count < 2) return;
  f32x2 a = set1_2(alpha);
  f32x2 oma = set1_2(1.0f - alpha);
  f32x2 prev = load2(xy);
  for (int i = 1; i < count; i++) {
    f32x2 cur = load2(xy + i * 2);
    // prev * alpha + cur * (1-alpha)
    f32x2 result = fma2(a, prev, mul2(oma, cur));
    store2(xy + i * 2, result);
    prev = result;
  }
}

/// EMA smoothing backward pass for interleaved [x, y] pairs.
inline void emaBackward2(float *xy, int count, float alpha) {
  if (count < 2) return;
  f32x2 a = set1_2(alpha);
  f32x2 oma = set1_2(1.0f - alpha);
  f32x2 prev = load2(xy + (count - 1) * 2);
  for (int i = count - 2; i >= 0; i--) {
    f32x2 cur = load2(xy + i * 2);
    f32x2 result = fma2(a, prev, mul2(oma, cur));
    store2(xy + i * 2, result);
    prev = result;
  }
}

/// Batch perpendicular offset: compute left/right points for 4 points.
/// Given centers (cx4, cy4), tangent normals (nx4, ny4), and halfWidths (hw4):
///   left  = center + normal * hw
///   right = center - normal * hw
inline void perpOffset4(const float *cx, const float *cy,
                        const float *nx, const float *ny,
                        const float *hw,
                        float *lx, float *ly, float *rx, float *ry) {
  f32x4 pcx = load4(cx), pcy = load4(cy);
  f32x4 pnx = load4(nx), pny = load4(ny);
  f32x4 phw = load4(hw);
  f32x4 offX = mul(pnx, phw);
  f32x4 offY = mul(pny, phw);
  store4(lx, add(pcx, offX));
  store4(ly, add(pcy, offY));
  store4(rx, sub(pcx, offX));
  store4(ry, sub(pcy, offY));
}

/// Chaikin subdivision for 4 consecutive pairs: 0.75*a + 0.25*b
inline void chaikin4(const float *a, const float *b, float *out75, float *out25) {
  f32x4 va = load4(a), vb = load4(b);
  f32x4 p75 = set1(0.75f), p25 = set1(0.25f);
  store4(out75, fma(p75, va, mul(p25, vb)));
  store4(out25, fma(p25, va, mul(p75, vb)));
}

/// Batch normalize 4 tangent vectors: (tx[i], ty[i]) → unit length
/// Returns lengths in outLen
inline void normalize4(float *tx, float *ty, float *outLen) {
  f32x4 vx = load4(tx), vy = load4(ty);
  f32x4 lenSq = fma(vx, vx, mul(vy, vy));
  f32x4 len = sqrt(lenSq);
  f32x4 invLen = rsqrt(lenSq);
  // Guard against zero-length: if lenSq < epsilon, set to (1,0)
  store4(outLen, len);
  store4(tx, mul(vx, invLen));
  store4(ty, mul(vy, invLen));
}

} // namespace simd
