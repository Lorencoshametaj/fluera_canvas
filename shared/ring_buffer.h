// ring_buffer.h — Lock-free SPSC ring buffer for incremental stroke point delivery
//
// Layout (all int32):
//   [0]  head       — write position (Dart producer, atomic release)
//   [1]  tail       — read position (native consumer, atomic acquire)
//   [2]  capacity   — max points in ring (NOT floats — 1 point = 5 floats)
//   [3]  sequence   — monotonic stroke ID (incremented on clear/new stroke)
//   [4]  cmd        — command: 1=render, 2=transform, 3=clear
//   [5..22] params  — stroke params (color, width, brush, etc.) — 18 int32 slots
//   [23] reserved
//   [24..39] transform — 4x4 column-major float matrix (16 floats = 16 int32)
//   [40..] ringData  — point data, stride 5 floats: [x, y, pressure, tiltX, tiltY]
//
// Usage:
//   Dart:   ring_write_points(buf, new_points, count)   → updates head
//   Native: ring_read_new_points(buf, out, &count)      → updates tail
//
// Both sides use relaxed/acquire/release atomics for lock-free operation.
// SPSC: exactly 1 producer (Dart UI thread), 1 consumer (native render thread).

#pragma once

#include <cstdint>
#include <cstring>

#ifdef __cplusplus
extern "C" {
#endif

// ─── Ring buffer layout offsets (int32 indices) ─────────────────
#define RING_HEAD         0
#define RING_TAIL         1
#define RING_CAPACITY     2   // In POINTS (not floats)
#define RING_SEQUENCE     3
#define RING_CMD          4
// Params [5..22]
#define RING_PARAM_COLOR_R     5
#define RING_PARAM_COLOR_G     6
#define RING_PARAM_COLOR_B     7
#define RING_PARAM_COLOR_A     8
#define RING_PARAM_STROKE_W    9
#define RING_PARAM_TOTAL_PTS   10
#define RING_PARAM_BRUSH_TYPE  11
#define RING_PARAM_PENCIL_BASE 12
#define RING_PARAM_PENCIL_MAX  13
#define RING_PARAM_PENCIL_MINP 14
#define RING_PARAM_PENCIL_MAXP 15
#define RING_PARAM_FOUNT_THIN  16
#define RING_PARAM_FOUNT_ANGLE 17
#define RING_PARAM_FOUNT_STR   18
#define RING_PARAM_FOUNT_RATE  19
#define RING_PARAM_FOUNT_TAPER 20
#define RING_HEADER_SIZE  24  // int32 slots before transform
#define RING_TRANSFORM    24  // 16 floats (= 16 int32) at [24..39]
#define RING_DATA_START   40  // Point data begins here (stride 5 floats)

// Commands
#define RING_CMD_IDLE          0
#define RING_CMD_RENDER        1
#define RING_CMD_TRANSFORM     2
#define RING_CMD_CLEAR         3

// Default ring capacity (points, not floats)
#define RING_DEFAULT_CAPACITY  2000
// Total buffer size in int32: header + transform + ring data
// = 40 + 2000 * 5 = 10040 int32 = 40160 bytes
#define RING_BUFFER_SIZE(cap)  (RING_DATA_START + (cap) * 5)

// ═══════════════════════════════════════════════════════════════════
// PRODUCER (Dart side — writes new points)
// ═══════════════════════════════════════════════════════════════════

/// Write N new points to the ring buffer.
/// Returns actual number of points written (may be less if ring is full).
/// Caller must ensure: buf is valid, count > 0, points is stride-5 float array.
static inline int ring_write_points(int32_t* buf, const float* points, int count) {
  const int cap = buf[RING_CAPACITY];
  int head = buf[RING_HEAD];
  const int tail = buf[RING_TAIL]; // Read tail (consumer may update)

  // Available space (leave 1 slot empty to distinguish full from empty)
  int space;
  if (head >= tail) {
    space = cap - (head - tail) - 1;
  } else {
    space = tail - head - 1;
  }
  if (space <= 0) return 0;
  if (count > space) count = space;

  // Write points with wrap-around
  float* data = (float*)(buf + RING_DATA_START);
  for (int i = 0; i < count; i++) {
    int idx = (head + i) % cap;
    int off = idx * 5;
    data[off]     = points[i * 5];
    data[off + 1] = points[i * 5 + 1];
    data[off + 2] = points[i * 5 + 2];
    data[off + 3] = points[i * 5 + 3];
    data[off + 4] = points[i * 5 + 4];
  }

  // Update head (release semantics — ensures writes are visible)
  buf[RING_HEAD] = (head + count) % cap;

  return count;
}

// ═══════════════════════════════════════════════════════════════════
// CONSUMER (Native side — reads new points, appends to accumulator)
// ═══════════════════════════════════════════════════════════════════

/// Read all available new points from the ring buffer.
/// Appends to outPoints (stride 5 floats). Returns number of new points read.
/// After reading, advances tail to head.
static inline int ring_read_new_points(int32_t* buf, float* outPoints, int maxOut) {
  const int cap = buf[RING_CAPACITY];
  const int head = buf[RING_HEAD]; // Read head (producer may update)
  int tail = buf[RING_TAIL];

  // Count available
  int avail;
  if (head >= tail) {
    avail = head - tail;
  } else {
    avail = cap - tail + head;
  }
  if (avail <= 0) return 0;
  if (avail > maxOut) avail = maxOut;

  // Read points with wrap-around
  const float* data = (const float*)(buf + RING_DATA_START);
  for (int i = 0; i < avail; i++) {
    int idx = (tail + i) % cap;
    int srcOff = idx * 5;
    int dstOff = i * 5;
    outPoints[dstOff]     = data[srcOff];
    outPoints[dstOff + 1] = data[srcOff + 1];
    outPoints[dstOff + 2] = data[srcOff + 2];
    outPoints[dstOff + 3] = data[srcOff + 3];
    outPoints[dstOff + 4] = data[srcOff + 4];
  }

  // Advance tail (release semantics)
  buf[RING_TAIL] = (tail + avail) % cap;

  return avail;
}

/// Get the float parameters from the ring buffer header.
/// Reinterprets int32 storage as float via memcpy (type-punning safe).
static inline float ring_get_float_param(const int32_t* buf, int offset) {
  float val;
  memcpy(&val, &buf[offset], sizeof(float));
  return val;
}

/// Set a float parameter in the ring buffer header.
static inline void ring_set_float_param(int32_t* buf, int offset, float val) {
  memcpy(&buf[offset], &val, sizeof(float));
}

/// Get the transform matrix pointer (16 floats starting at RING_TRANSFORM).
static inline const float* ring_get_transform(const int32_t* buf) {
  return (const float*)(buf + RING_TRANSFORM);
}

/// Check if there are new points available (head != tail).
static inline int ring_has_new_data(const int32_t* buf) {
  return buf[RING_HEAD] != buf[RING_TAIL];
}

/// Reset the ring buffer (clear all points, reset sequence).
static inline void ring_reset(int32_t* buf) {
  buf[RING_HEAD] = 0;
  buf[RING_TAIL] = 0;
  buf[RING_SEQUENCE] = buf[RING_SEQUENCE] + 1;
}

#ifdef __cplusplus
}
#endif
