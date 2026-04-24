// vk_jni_bridge.cpp — JNI bridge between Kotlin VulkanStrokeOverlayPlugin and
// C++ VkStrokeRenderer Exposes native functions for init, render, transform,
// clear, resize, destroy.

#include "vk_stroke_renderer.h"
#include <android/native_window_jni.h>
#include <jni.h>

static VkStrokeRenderer *g_renderer = nullptr;

extern "C" {

// ═══════════════════════════════════════════════════════════════════
// nativeInit — Initialize Vulkan renderer from a Surface
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeInit(
    JNIEnv *env, jobject /* this */, jobject surface, jint width, jint height) {
  if (g_renderer) {
    g_renderer->destroy();
    delete g_renderer;
  }

  ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
  if (!window) {
    LOGE("ANativeWindow_fromSurface returned null");
    return JNI_FALSE;
  }

  // Set buffer geometry to match requested size
  ANativeWindow_setBuffersGeometry(window, width, height,
                                   AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);

  g_renderer = new VkStrokeRenderer();
  if (!g_renderer->init(window, width, height)) {
    LOGE("VkStrokeRenderer::init failed");
    delete g_renderer;
    g_renderer = nullptr;
    ANativeWindow_release(window);
    return JNI_FALSE;
  }

  return JNI_TRUE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeUpdateAndRender — Tessellate + render stroke
// points: [x0, y0, x1, y1, ...], color: ARGB int, width: logical px
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeUpdateAndRender(
    JNIEnv *env, jobject /* this */, jfloatArray pointsArray, jint colorArgb,
    jfloat strokeWidth, jint totalPoints, jint brushType,
    jfloat pencilBaseOpacity, jfloat pencilMaxOpacity,
    jfloat pencilMinPressure, jfloat pencilMaxPressure,
    jfloat fountainThinning, jfloat fountainNibAngleDeg,
    jfloat fountainNibStrength, jfloat fountainPressureRate,
    jint fountainTaperEntry) {
  if (!g_renderer || !g_renderer->isInitialized())
    return;

  jsize len = env->GetArrayLength(pointsArray);
  if (len < 10)
    return; // Need at least 2 points (10 floats: x,y,p,tx,ty × 2)

  jfloat *pts = env->GetFloatArrayElements(pointsArray, nullptr);
  if (!pts)
    return;

  int pointCount = len / 5; // Stride 5: x, y, pressure, tiltX, tiltY

  // Extract ARGB color
  float a = ((colorArgb >> 24) & 0xFF) / 255.0f;
  float r = ((colorArgb >> 16) & 0xFF) / 255.0f;
  float g = ((colorArgb >> 8) & 0xFF) / 255.0f;
  float b = (colorArgb & 0xFF) / 255.0f;

  g_renderer->updateAndRender(pts, pointCount, r, g, b, a, strokeWidth,
                              totalPoints, brushType,
                              pencilBaseOpacity, pencilMaxOpacity,
                              pencilMinPressure, pencilMaxPressure,
                                                            fountainThinning, fountainNibAngleDeg,
                              fountainNibStrength, fountainPressureRate,
                              fountainTaperEntry);

  env->ReleaseFloatArrayElements(pointsArray, pts, JNI_ABORT);
}

// ═══════════════════════════════════════════════════════════════════
// nativeSetTransform — Set 4x4 canvas transform matrix
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeSetTransform(
    JNIEnv *env, jobject /* this */, jfloatArray matrixArray) {
  if (!g_renderer || !g_renderer->isInitialized())
    return;

  jfloat *m = env->GetFloatArrayElements(matrixArray, nullptr);
  if (!m)
    return;

  g_renderer->setTransform(m);

  env->ReleaseFloatArrayElements(matrixArray, m, JNI_ABORT);
}

// ═══════════════════════════════════════════════════════════════════
// nativeClear — Clear the render target (transparent)
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeClear(
    JNIEnv * /* env */, jobject /* this */) {
  if (g_renderer && g_renderer->isInitialized()) {
    g_renderer->clearFrame();
  }
}

// ═══════════════════════════════════════════════════════════════════
// nativeResize — Resize the render target
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeResize(
    JNIEnv * /* env */, jobject /* this */, jint width, jint height) {
  if (!g_renderer || !g_renderer->isInitialized())
    return JNI_FALSE;
  return g_renderer->resize(width, height) ? JNI_TRUE : JNI_FALSE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeDestroy — Cleanup all Vulkan resources
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeDestroy(
    JNIEnv * /* env */, jobject /* this */) {
  if (g_renderer) {
    g_renderer->destroy();
    delete g_renderer;
    g_renderer = nullptr;
  }
}

// ═══════════════════════════════════════════════════════════════════
// nativeIsInitialized — Check if the renderer is ready
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jboolean JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeIsInitialized(
    JNIEnv * /* env */, jobject /* this */) {
  return (g_renderer && g_renderer->isInitialized()) ? JNI_TRUE : JNI_FALSE;
}

// ═══════════════════════════════════════════════════════════════════
// nativeGetStats — Get performance statistics snapshot
// Returns float[11]: [p50us, p90us, p99us, vertexCount, drawCalls,
//                     swapchainImages, totalFrames, active,
//                     apiMajor, apiMinor, apiPatch]
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jfloatArray JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeGetStats(
    JNIEnv *env, jobject /* this */) {
  jfloatArray result = env->NewFloatArray(11);
  if (!result)
    return nullptr;

  float data[11] = {0};
  if (g_renderer && g_renderer->isInitialized()) {
    VkStrokeStats s = g_renderer->getStats();
    data[0] = s.frameTimeP50Us;
    data[1] = s.frameTimeP90Us;
    data[2] = s.frameTimeP99Us;
    data[3] = (float)s.vertexCount;
    data[4] = (float)s.drawCalls;
    data[5] = (float)s.swapchainImages;
    data[6] = (float)s.totalFrames;
    data[7] = s.active ? 1.0f : 0.0f;
    data[8] = (float)s.apiVersionMajor;
    data[9] = (float)s.apiVersionMinor;
    data[10] = (float)s.apiVersionPatch;
  }

  env->SetFloatArrayRegion(result, 0, 11, data);
  return result;
}

// ═══════════════════════════════════════════════════════════════════
// nativeGetDeviceName — Get GPU device name
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT jstring JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeGetDeviceName(
    JNIEnv *env, jobject /* this */) {
  if (g_renderer && g_renderer->isInitialized()) {
    VkStrokeStats s = g_renderer->getStats();
    return env->NewStringUTF(s.deviceName);
  }
  return env->NewStringUTF("N/A");
}

// ═══════════════════════════════════════════════════════════════════
// nativeSetZoomLevel — 🚀 Adaptive LOD
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeSetZoomLevel(
    JNIEnv * /* env */, jobject /* this */, jfloat zoom) {
  if (g_renderer && g_renderer->isInitialized()) {
    g_renderer->setZoomLevel(zoom);
  }
}

// ═══════════════════════════════════════════════════════════════════
// nativeTrimMemory — 🚀 Memory pressure management
// ═══════════════════════════════════════════════════════════════════

JNIEXPORT void JNICALL
Java_com_flueraengine_fluera_1engine_VulkanStrokeOverlayPlugin_nativeTrimMemory(
    JNIEnv * /* env */, jobject /* this */, jint level) {
  if (g_renderer) {
    g_renderer->trimMemory(level);
  }
}

} // extern "C"

// ═══════════════════════════════════════════════════════════════════
// 🚀 FFI EXPORT — Direct Dart→C++ hot path (replaces MethodChannel)
//
// Shared buffer layout defined in fluera_stroke_ffi.h.
// Called from Dart via dart:ffi on the UI isolate thread.
// ═══════════════════════════════════════════════════════════════════

// Buffer layout — mirrors fluera_stroke_ffi.h
#define FLUERA_FFI_CMD           0
#define FLUERA_FFI_POINT_COUNT   1
#define FLUERA_FFI_COLOR_R       2
#define FLUERA_FFI_COLOR_G       3
#define FLUERA_FFI_COLOR_B       4
#define FLUERA_FFI_COLOR_A       5
#define FLUERA_FFI_STROKE_WIDTH  6
#define FLUERA_FFI_TOTAL_POINTS  7
#define FLUERA_FFI_BRUSH_TYPE    8
#define FLUERA_FFI_PENCIL_BASE   9
#define FLUERA_FFI_PENCIL_MAX    10
#define FLUERA_FFI_PENCIL_MIN_P  11
#define FLUERA_FFI_PENCIL_MAX_P  12
#define FLUERA_FFI_FOUNTAIN_THIN 13
#define FLUERA_FFI_FOUNTAIN_ANGLE 14
#define FLUERA_FFI_FOUNTAIN_STR  15
#define FLUERA_FFI_FOUNTAIN_RATE 16
#define FLUERA_FFI_FOUNTAIN_TAPER 17
#define FLUERA_FFI_TRANSFORM     20
#define FLUERA_FFI_POINTS        36
#define FLUERA_CMD_UPDATE_AND_RENDER  1.0f
#define FLUERA_CMD_SET_TRANSFORM     2.0f
#define FLUERA_CMD_CLEAR             3.0f

// Persistent point accumulator for ring buffer mode
#include "../../../../shared/ring_buffer.h"
static std::vector<float> g_ringAccumPoints;
static int g_ringAccumCount = 0;
static int g_ringLastSequence = -1;

extern "C" {

__attribute__((visibility("default")))
void fluera_stroke_execute(float* buf) {
  if (!buf || !g_renderer || !g_renderer->isInitialized()) return;

  const float cmd = buf[FLUERA_FFI_CMD];

  if (cmd == FLUERA_CMD_CLEAR) {
    g_renderer->clearFrame();
    // Also reset ring buffer accumulator (safety net — resetRing sequence
    // should handle this, but belt-and-suspenders for edge cases)
    g_ringAccumPoints.clear();
    g_ringAccumCount = 0;
    return;
  }

  if (cmd == FLUERA_CMD_SET_TRANSFORM) {
    g_renderer->setTransform(&buf[FLUERA_FFI_TRANSFORM]);
    return;
  }

  if (cmd == FLUERA_CMD_UPDATE_AND_RENDER) {
    const int pointCount = (int)buf[FLUERA_FFI_POINT_COUNT];
    if (pointCount < 2) return;

    const float r = buf[FLUERA_FFI_COLOR_R];
    const float g = buf[FLUERA_FFI_COLOR_G];
    const float b = buf[FLUERA_FFI_COLOR_B];
    const float a = buf[FLUERA_FFI_COLOR_A];

    g_renderer->updateAndRender(
        &buf[FLUERA_FFI_POINTS], pointCount,
        r, g, b, a,
        buf[FLUERA_FFI_STROKE_WIDTH],
        (int)buf[FLUERA_FFI_TOTAL_POINTS],
        (int)buf[FLUERA_FFI_BRUSH_TYPE],
        buf[FLUERA_FFI_PENCIL_BASE],
        buf[FLUERA_FFI_PENCIL_MAX],
        buf[FLUERA_FFI_PENCIL_MIN_P],
        buf[FLUERA_FFI_PENCIL_MAX_P],
        buf[FLUERA_FFI_FOUNTAIN_THIN],
        buf[FLUERA_FFI_FOUNTAIN_ANGLE],
        buf[FLUERA_FFI_FOUNTAIN_STR],
        buf[FLUERA_FFI_FOUNTAIN_RATE],
        (int)buf[FLUERA_FFI_FOUNTAIN_TAPER]);
  }
}

} // extern "C"

// ═══════════════════════════════════════════════════════════════════
// 🚀 Ring buffer incremental FFI consumer
// ═══════════════════════════════════════════════════════════════════

extern "C" {

__attribute__((visibility("default")))
void fluera_stroke_ring_execute(int32_t* buf) {
  if (!buf || !g_renderer || !g_renderer->isInitialized()) return;

  const int cmd = buf[RING_CMD];

  if (cmd == RING_CMD_CLEAR) {
    g_renderer->clearFrame();
    g_ringAccumPoints.clear();
    g_ringAccumCount = 0;
    ring_reset(buf);
    return;
  }

  if (cmd == RING_CMD_TRANSFORM) {
    const float* mat = ring_get_transform(buf);
    g_renderer->setTransform(mat);
    return;
  }

  if (cmd == RING_CMD_RENDER) {
    // Check for new stroke (sequence changed → reset accumulator)
    int seq = buf[RING_SEQUENCE];
    if (seq != g_ringLastSequence) {
      g_ringAccumPoints.clear();
      g_ringAccumCount = 0;
      g_ringLastSequence = seq;
    }

    // Read new points from ring
    float tempBuf[5 * 200]; // Read up to 200 points at a time
    int newCount = ring_read_new_points(buf, tempBuf, 200);

    // Append new points to accumulator
    if (newCount > 0) {
      g_ringAccumPoints.insert(g_ringAccumPoints.end(),
                                tempBuf, tempBuf + newCount * 5);
      g_ringAccumCount += newCount;
    }

    if (g_ringAccumCount < 2) return;

    // Extract params from ring header
    const float cr = ring_get_float_param(buf, RING_PARAM_COLOR_R);
    const float cg = ring_get_float_param(buf, RING_PARAM_COLOR_G);
    const float cb = ring_get_float_param(buf, RING_PARAM_COLOR_B);
    const float ca = ring_get_float_param(buf, RING_PARAM_COLOR_A);

    g_renderer->updateAndRender(
        g_ringAccumPoints.data(), g_ringAccumCount,
        cr, cg, cb, ca,
        ring_get_float_param(buf, RING_PARAM_STROKE_W),
        (int)ring_get_float_param(buf, RING_PARAM_TOTAL_PTS),
        (int)ring_get_float_param(buf, RING_PARAM_BRUSH_TYPE),
        ring_get_float_param(buf, RING_PARAM_PENCIL_BASE),
        ring_get_float_param(buf, RING_PARAM_PENCIL_MAX),
        ring_get_float_param(buf, RING_PARAM_PENCIL_MINP),
        ring_get_float_param(buf, RING_PARAM_PENCIL_MAXP),
        ring_get_float_param(buf, RING_PARAM_FOUNT_THIN),
        ring_get_float_param(buf, RING_PARAM_FOUNT_ANGLE),
        ring_get_float_param(buf, RING_PARAM_FOUNT_STR),
        ring_get_float_param(buf, RING_PARAM_FOUNT_RATE),
        (int)ring_get_float_param(buf, RING_PARAM_FOUNT_TAPER));

    buf[RING_CMD] = RING_CMD_IDLE;
  }
}

} // extern "C"

