package com.fluera.canvas

import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * 🎨 VulkanStrokeOverlayPlugin — Flutter TextureRegistry bridge for C++ Vulkan stroke renderer.
 *
 * Uses SurfaceProducer (Impeller-compatible) for zero-copy GPU texture sharing.
 * Falls back to SurfaceTexture on older Flutter versions.
 *
 * 🛡️ Crash protection: all JNI calls are guarded by [nativeInitialized].
 * surfaceProducer.release() is wrapped in try-catch because when VkStrokeRenderer::init
 * fails on devices without Vulkan (e.g. emulators), the C++ layer already releases the
 * ANativeWindow internally. A subsequent Kotlin-side release causes a null-ptr SIGSEGV
 * in android::RefBase::incStrong via ImageReader.close / Surface.release.
 */
class VulkanStrokeOverlayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null
    private var reusableFloatBuffer: FloatArray? = null  // Reused to avoid GC pressure

    // SurfaceProducer path (Impeller-compatible)
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var surface: Surface? = null
    private var currentTextureId: Long = -1

    /**
     * 🛡️ True only after nativeInit() returns true. Guards every JNI call.
     * Set back to false before any nativeDestroy() / destroyTexture().
     */
    private var nativeInitialized = false

    companion object {
        private var nativeLibLoaded = false

        fun isVulkanAvailable(): Boolean {
            return Build.VERSION.SDK_INT >= 24
        }

        private fun ensureNativeLib() {
            if (!nativeLibLoaded) {
                try {
                    System.loadLibrary("fluera_vk_stroke")
                    nativeLibLoaded = true
                } catch (e: UnsatisfiedLinkError) {
                    android.util.Log.e("FlueraVk", "Failed to load fluera_vk_stroke: ${e.message}")
                }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "fluera_canvas/native_stroke")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        destroyTexture()
        textureRegistry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isVulkanAvailable() && ensureAndCheckNative())
            }

            "init" -> {
                val width = (call.argument<Number>("width") ?: 1080).toInt()
                val height = (call.argument<Number>("height") ?: 1920).toInt()

                if (!isVulkanAvailable()) {
                    result.error("VULKAN_UNSUPPORTED", "Vulkan requires API 24+", null)
                    return
                }
                ensureNativeLib()
                if (!nativeLibLoaded) {
                    result.error("NATIVE_LIB_MISSING", "fluera_vk_stroke not loaded", null)
                    return
                }

                // Clean up any previous state before creating a new surface
                destroyTexture()

                try {
                    val producer = textureRegistry?.createSurfaceProducer()
                    if (producer == null) {
                        result.error("TEXTURE_FAILED", "createSurfaceProducer returned null", null)
                        return
                    }

                    surfaceProducer = producer
                    producer.setSize(width, height)
                    currentTextureId = producer.id()

                    val producerSurface = producer.surface
                    surface = producerSurface

                    val success = nativeInit(producerSurface, width, height)
                    if (success) {
                        nativeInitialized = true
                        android.util.Log.i("FlueraVk", "Vulkan renderer initialized, textureId=$currentTextureId")
                        result.success(currentTextureId)
                    } else {
                        // nativeInit already released the Surface internally on failure —
                        // destroyTexture() must not call nativeDestroy() again.
                        // surfaceProducer.release() is try-catched for this reason.
                        destroyTexture()
                        result.error("VK_INIT_FAILED", "Vulkan init failed", null)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("FlueraVk", "Init error: ${e.message}")
                    destroyTexture()
                    result.error("INIT_EXCEPTION", e.message, null)
                }
            }

            "updateAndRender" -> {
                if (!nativeInitialized) { result.success(null); return }

                val points = call.argument<List<Number>>("points")
                val color = (call.argument<Number>("color") ?: 0xFF000000L).toInt()
                val width = (call.argument<Number>("width") ?: 2.0).toDouble()
                val totalPoints = (call.argument<Number>("totalPoints") ?: 0).toInt()
                val brushType = (call.argument<Number>("brushType") ?: 0).toInt()
                val pencilBaseOpacity = (call.argument<Number>("pencilBaseOpacity") ?: 0.4).toFloat()
                val pencilMaxOpacity = (call.argument<Number>("pencilMaxOpacity") ?: 0.8).toFloat()
                val pencilMinPressure = (call.argument<Number>("pencilMinPressure") ?: 0.5).toFloat()
                val pencilMaxPressure = (call.argument<Number>("pencilMaxPressure") ?: 1.2).toFloat()
                val fountainThinning = (call.argument<Number>("fountainThinning") ?: 0.5).toFloat()
                val fountainNibAngleDeg = (call.argument<Number>("fountainNibAngleDeg") ?: 30.0).toFloat()
                val fountainNibStrength = (call.argument<Number>("fountainNibStrength") ?: 0.35).toFloat()
                val fountainPressureRate = (call.argument<Number>("fountainPressureRate") ?: 0.275).toFloat()
                val fountainTaperEntry = (call.argument<Number>("fountainTaperEntry") ?: 6).toInt()

                if (points != null && points.size >= 10) {
                    val needed = points.size
                    if (reusableFloatBuffer == null || reusableFloatBuffer!!.size != needed) {
                        reusableFloatBuffer = FloatArray(needed)
                    }
                    val buf = reusableFloatBuffer!!
                    for (i in 0 until needed) {
                        buf[i] = points[i].toFloat()
                    }
                    nativeUpdateAndRender(buf, color, width.toFloat(), totalPoints, brushType,
                        pencilBaseOpacity, pencilMaxOpacity, pencilMinPressure, pencilMaxPressure,
                        fountainThinning, fountainNibAngleDeg, fountainNibStrength, fountainPressureRate, fountainTaperEntry)
                }
                result.success(null)
            }

            "setTransform" -> {
                if (!nativeInitialized) { result.success(null); return }

                val matrix = call.argument<List<Number>>("matrix")
                if (matrix != null && matrix.size == 16) {
                    val floatArray = FloatArray(16) { matrix[it].toFloat() }
                    nativeSetTransform(floatArray)
                }
                val zoom = call.argument<Number>("zoomLevel")?.toFloat()
                if (zoom != null) {
                    nativeSetZoomLevel(zoom)
                }
                result.success(null)
            }

            "trimMemory" -> {
                if (!nativeInitialized) { result.success(null); return }
                val level = call.argument<Number>("level")?.toInt() ?: 1
                nativeTrimMemory(level)
                result.success(null)
            }

            "clear" -> {
                if (!nativeInitialized) { result.success(null); return }
                nativeClear()
                result.success(null)
            }

            "resize" -> {
                val w = (call.argument<Number>("width") ?: 1080).toInt()
                val h = (call.argument<Number>("height") ?: 1920).toInt()
                surfaceProducer?.setSize(w, h)
                if (nativeInitialized) {
                    val success = nativeResize(w, h)
                    result.success(success)
                } else {
                    result.success(false)
                }
            }

            "destroy" -> {
                destroyTexture()
                result.success(null)
            }

            "getStats" -> {
                if (!nativeInitialized) { result.success(null); return }
                try {
                    val stats = nativeGetStats()
                    val deviceName = nativeGetDeviceName()
                    if (stats != null && stats.size >= 11) {
                        result.success(mapOf(
                            "p50us" to stats[0].toDouble(),
                            "p90us" to stats[1].toDouble(),
                            "p99us" to stats[2].toDouble(),
                            "vertexCount" to stats[3].toInt(),
                            "drawCalls" to stats[4].toInt(),
                            "swapchainImages" to stats[5].toInt(),
                            "totalFrames" to stats[6].toInt(),
                            "active" to (stats[7] > 0.5f),
                            "apiMajor" to stats[8].toInt(),
                            "apiMinor" to stats[9].toInt(),
                            "apiPatch" to stats[10].toInt(),
                            "deviceName" to (deviceName ?: "N/A")
                        ))
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun ensureAndCheckNative(): Boolean {
        ensureNativeLib()
        return nativeLibLoaded
    }

    /**
     * 🛡️ Safe teardown:
     * 1. Calls nativeDestroy() only if the renderer was successfully initialized.
     * 2. Wraps surfaceProducer.release() in try-catch — on Vulkan init failure the
     *    C++ layer already released the ANativeWindow, so a second release would
     *    SIGSEGV inside android::RefBase::incStrong / ImageReader.close.
     */
    private fun destroyTexture() {
        if (nativeInitialized) {
            try {
                nativeDestroy()
            } catch (e: Exception) {
                android.util.Log.w("FlueraVk", "nativeDestroy() exception: ${e.message}")
            }
            nativeInitialized = false
        }
        surface = null
        try {
            surfaceProducer?.release()
        } catch (e: Exception) {
            android.util.Log.w("FlueraVk", "surfaceProducer.release() failed (Surface already released by native layer): ${e.message}")
        }
        surfaceProducer = null
        currentTextureId = -1
        reusableFloatBuffer = null
    }

    // ─── JNI native methods ──────────────────────────────────────
    private external fun nativeInit(surface: Surface, width: Int, height: Int): Boolean
    private external fun nativeUpdateAndRender(points: FloatArray, color: Int, strokeWidth: Float, totalPoints: Int, brushType: Int, pencilBaseOpacity: Float, pencilMaxOpacity: Float, pencilMinPressure: Float, pencilMaxPressure: Float, fountainThinning: Float, fountainNibAngleDeg: Float, fountainNibStrength: Float, fountainPressureRate: Float, fountainTaperEntry: Int)
    private external fun nativeSetTransform(matrix: FloatArray)
    private external fun nativeClear()
    private external fun nativeResize(width: Int, height: Int): Boolean
    private external fun nativeDestroy()
    private external fun nativeIsInitialized(): Boolean
    private external fun nativeGetStats(): FloatArray?
    private external fun nativeGetDeviceName(): String?
    private external fun nativeSetZoomLevel(zoom: Float)
    private external fun nativeTrimMemory(level: Int)
}
