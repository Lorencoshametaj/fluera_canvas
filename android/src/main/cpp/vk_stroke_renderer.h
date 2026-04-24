// vk_stroke_renderer.h — Pure C++ Vulkan stroke renderer
// Renders live strokes as triangle strips with round caps into an
// ANativeWindow. Uses VK_KHR_android_surface + swapchain for zero-copy Flutter
// TextureRegistry.

#pragma once

#include <android/log.h>
#include <android/native_window.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>
#include "../../../../shared/vertex_buffer_pool.h"
#include "../../../../shared/tessellation_thread.h"

#define VK_TAG "FlueraVk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, VK_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, VK_TAG, __VA_ARGS__)

#define VK_CHECK(x)                                                            \
  do {                                                                         \
    VkResult _r = (x);                                                         \
    if (_r != VK_SUCCESS) {                                                    \
      LOGE("%s failed: %d at %s:%d", #x, _r, __FILE__, __LINE__);              \
      return false;                                                            \
    }                                                                          \
  } while (0)

/// Vertex: 2D position + RGBA color (24 bytes)
struct StrokeVertex {
  float x, y;
  float r, g, b, a;
};

/// Performance statistics snapshot from the Vulkan renderer.
struct VkStrokeStats {
  float frameTimeP50Us;     // GPU frame time P50 (microseconds)
  float frameTimeP90Us;     // GPU frame time P90 (microseconds)
  float frameTimeP99Us;     // GPU frame time P99 (microseconds)
  uint32_t vertexCount;     // Vertices in last frame
  uint32_t drawCalls;       // Draw calls in last frame
  uint32_t swapchainImages; // Number of swapchain images
  uint32_t totalFrames;     // Total frames rendered
  char deviceName[256];     // GPU device name
  uint32_t apiVersionMajor; // Vulkan API version major
  uint32_t apiVersionMinor; // Vulkan API version minor
  uint32_t apiVersionPatch; // Vulkan API version patch
  bool active;              // Whether renderer is actively drawing
};

/// Manages the entire Vulkan pipeline for rendering strokes.
class VkStrokeRenderer {
public:
  VkStrokeRenderer() = default;
  ~VkStrokeRenderer();

  /// Initialize Vulkan from an ANativeWindow (from
  /// SurfaceTexture/SurfaceProducer).
  bool init(ANativeWindow *window, int width, int height);

  /// Tessellate touch points with pressure + render.
  /// points: [x0, y0, p0, x1, y1, p1, ...] (stride 3), count: number of points.
  /// color: RGBA [0..1], strokeWidth: logical pixels, totalPoints: total in
  /// stroke.
  /// brushType: 0 = ballpoint, 1 = marker, 2 = pencil, 3 = technical, 4 = fountain
  void updateAndRender(const float *points, int pointCount, float r, float g,
                       float b, float a, float strokeWidth, int totalPoints,
                       int brushType = 0,
                       float pencilBaseOpacity = 0.4f, float pencilMaxOpacity = 0.8f,
                       float pencilMinPressure = 0.5f, float pencilMaxPressure = 1.2f,
                       float fountainThinning = 0.5f, float fountainNibAngleDeg = 30.0f,
                       float fountainNibStrength = 0.35f, float fountainPressureRate = 0.275f,
                        int fountainTaperEntry = 6);

  /// Set canvas transform (4x4 column-major matrix).
  void setTransform(const float *matrix4x4);

  /// Clear the render target (transparent).
  void clearFrame();

  /// Resize the render target.
  bool resize(int width, int height);

  /// Cleanup all Vulkan resources.
  void destroy();

  /// 🚀 Release unused memory under pressure.
  /// Trims vertex pool, shrinks allPoints, clears async buffers.
  /// level: 0=normal, 1=warning (trim free buffers), 2=critical (aggressive)
  void trimMemory(int level = 1);
  void setZoomLevel(float zoom);  // 🚀 Adaptive LOD

  bool isInitialized() const { return initialized_; }

  /// Get current performance statistics snapshot.
  VkStrokeStats getStats() const;

private:
  // ─── Vulkan core objects ───────────────────────────────────────
  VkInstance instance_ = VK_NULL_HANDLE;
  VkPhysicalDevice physDevice_ = VK_NULL_HANDLE;
  VkDevice device_ = VK_NULL_HANDLE;
  VkQueue queue_ = VK_NULL_HANDLE;
  uint32_t queueFamily_ = 0;

  // ─── Surface + Swapchain ──────────────────────────────────────
  VkSurfaceKHR surface_ = VK_NULL_HANDLE;
  VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
  std::vector<VkImage> swapImages_;
  std::vector<VkImageView> swapViews_;
  std::vector<VkFramebuffer> framebuffers_;
  VkFormat swapFormat_ = VK_FORMAT_R8G8B8A8_UNORM;
  VkExtent2D swapExtent_ = {0, 0};

  // ─── MSAA ─────────────────────────────────────────────────────
  VkSampleCountFlagBits msaaSamples_ = VK_SAMPLE_COUNT_4_BIT;
  VkImage msaaImage_ = VK_NULL_HANDLE;
  VkImageView msaaView_ = VK_NULL_HANDLE;
  VkDeviceMemory msaaMemory_ = VK_NULL_HANDLE;

  // ─── Pipeline ─────────────────────────────────────────────────
  VkRenderPass renderPass_ = VK_NULL_HANDLE;
  VkPipelineLayout pipelineLayout_ = VK_NULL_HANDLE;
  VkPipeline pipeline_ = VK_NULL_HANDLE;

  // ─── Command ──────────────────────────────────────────────────
  VkCommandPool cmdPool_ = VK_NULL_HANDLE;

  // ─── Triple-buffered sync (3 frames in flight) ────────────────
  static constexpr int MAX_FRAMES_IN_FLIGHT = 3;
  VkCommandBuffer cmdBuffers_[3] = {};
  VkSemaphore imageAvailSems_[3] = {};
  VkSemaphore renderDoneSems_[3] = {};
  VkFence frameFences_[3] = {};
  uint32_t currentFrame_ = 0;

  // ─── Vertex buffer ────────────────────────────────────────────
  VkBuffer vertexBuffer_ = VK_NULL_HANDLE;
  VkDeviceMemory vertexMemory_ = VK_NULL_HANDLE;
  static constexpr size_t MAX_VERTICES = 524288; // 512K vertices (~12MB)
  uint32_t vertexCount_ = 0;
  // 🚀 Vertex buffer pool: pre-reserved CPU vectors, eliminates heap alloc
  VertexBufferPool<StrokeVertex> vertexPool_{4, 32768};
  int currentPoolSlot_ = -1; // Currently acquired pool slot
  std::vector<float> allPoints_;              // Raw accumulated points (stride 5)
  void *mappedVertexMemory_ = nullptr;         // 🚀 Persistent mapped pointer
  int totalAccumulatedPoints_ = 0; // 🎨 Global point count for tapering

  // ─── 🚀 Multi-Threaded Tessellation ────────────────────────
  TessellationThread<StrokeVertex> tessThread_;
  bool tessThreadStarted_ = false;
  // Cached copy of points for async tessellation (worker needs stable data)
  std::vector<float> asyncPointsCopy_;

  // ─── 🚀 GPU Compute Tessellation ──────────────────────────────
  VkPipeline computePipeline_ = VK_NULL_HANDLE;
  VkPipelineLayout computePipelineLayout_ = VK_NULL_HANDLE;
  VkDescriptorSetLayout computeDescSetLayout_ = VK_NULL_HANDLE;
  VkDescriptorPool computeDescPool_ = VK_NULL_HANDLE;
  VkDescriptorSet computeDescSet_ = VK_NULL_HANDLE;
  // Points SSBO: raw input points uploaded from Dart/FFI
  VkBuffer pointsSSBO_ = VK_NULL_HANDLE;
  VkDeviceMemory pointsSSBOMemory_ = VK_NULL_HANDLE;
  void *mappedPointsSSBO_ = nullptr;
  static constexpr size_t MAX_POINTS_SSBO = 5000 * 5 * sizeof(float);
  // Params UBO: brush parameters for compute shader
  VkBuffer computeParamsUBO_ = VK_NULL_HANDLE;
  VkDeviceMemory computeParamsMemory_ = VK_NULL_HANDLE;
  void *mappedComputeParams_ = nullptr;
  // Vertex output SSBO: compute writes tessellated vertices here
  VkBuffer computeVertexSSBO_ = VK_NULL_HANDLE;
  VkDeviceMemory computeVertexSSBOMemory_ = VK_NULL_HANDLE;
  // Cap output SSBO + counter
  VkBuffer computeCapSSBO_ = VK_NULL_HANDLE;
  VkDeviceMemory computeCapSSBOMemory_ = VK_NULL_HANDLE;
  VkBuffer computeCapCounterSSBO_ = VK_NULL_HANDLE;
  VkDeviceMemory computeCapCounterMemory_ = VK_NULL_HANDLE;
  void *mappedCapCounter_ = nullptr;
  bool computeAvailable_ = false;
  int prevComputePointCount_ = 0;  // 🚀 Incremental compute tracking
  int dynamicSubsPerSeg_ = 8;  // 🚀 Adaptive LOD: 4-16
  static constexpr int SUBS_PER_SEG = 8; // Subdivisions per input segment

  // ─── 🚀 Indirect Draw (GPU-driven vertex count) ───────────────
  VkBuffer indirectDrawBuffer_ = VK_NULL_HANDLE;
  VkDeviceMemory indirectDrawMemory_ = VK_NULL_HANDLE;
  void *mappedIndirectDraw_ = nullptr;
  bool indirectDrawAvailable_ = false;

  // ─── State ────────────────────────────────────────────────────
  float transform_[16];
  int width_ = 0, height_ = 0;
  bool initialized_ = false;
  ANativeWindow *window_ = nullptr;

  // ─── Performance tracking ─────────────────────────────────────
  static constexpr int STATS_MAX_SAMPLES = 120;
  std::vector<float> frameTimesUs_;          // Rolling frame time buffer (µs)
  uint32_t statsDrawCalls_ = 0;              // Draw calls last frame
  uint32_t statsTotalFrames_ = 0;            // Total frames rendered
  bool statsActive_ = false;                 // Currently rendering strokes?
  VkPhysicalDeviceProperties deviceProps_{}; // Cached device properties
  std::chrono::steady_clock::time_point lastFrameTime_; // For delta measurement
  bool hasLastFrameTime_ = false;

  // ─── Init helpers ─────────────────────────────────────────────
  bool createInstance();
  bool pickPhysicalDevice();
  bool createDevice();
  bool createSurface(ANativeWindow *window);
  bool createSwapchain();
  bool createRenderPass();
  bool createPipeline();
  bool createCommandPool();
  bool createVertexBuffer();
  bool createSyncObjects();
  bool createFramebuffers();

  void destroySwapchain();
  bool createMsaaResources();
  void destroyMsaaResources();

  // ─── 🚀 Compute pipeline ───────────────────────────────────────
  bool createComputePipeline();
  void dispatchCompute(const float *points, int pointCount, int brushType,
                       float r, float g, float b, float a, float strokeWidth,
                       float minPressure, float maxPressure,
                       float pencilBaseOpacity, float pencilMaxOpacity);
  bool createComputeBuffers();
  void destroyComputeResources();

  // ─── Tessellation ─────────────────────────────────────────────
  /// Tessellate 2D polyline with pressure-aware width + tapering.
  void tessellateStroke(const float *points, int pointCount, float r, float g,
                        float b, float a, float strokeWidth,
                        int pointStartIndex, int totalPoints,
                        std::vector<StrokeVertex> &outVerts,
                        float minPressure = 0.7f, float maxPressure = 1.1f);

  /// Thick marker tessellation: wider quads, no circles, pressure → width.
  void tessellateMarker(const float *points, int pointCount, float r, float g,
                        float b, float a, float strokeWidth,
                        std::vector<StrokeVertex> &outVerts);

  /// Technical pen tessellation: constant width, no taper, squared ends.
  void tessellateTechnicalPen(const float *points, int pointCount, float r,
                              float g, float b, float a, float strokeWidth,
                              std::vector<StrokeVertex> &outVerts);

  /// Soft pencil tessellation: pressure → opacity + width, round caps, grain.
  void tessellatePencil(const float *points, int pointCount, float r, float g,
                        float b, float a, float strokeWidth,
                        int pointStartIndex, int totalPoints,
                        std::vector<StrokeVertex> &outVerts,
                        float pencilBaseOpacity = 0.4f, float pencilMaxOpacity = 0.8f,
                        float pencilMinPressure = 0.5f, float pencilMaxPressure = 1.2f);

  /// Fountain pen (stilografica) tessellation: pressure accumulator, nib angle,
  /// thinning, tapering, 6-pass EMA smoothing, Chaikin subdivision, edge
  /// feathering, and semicircular caps. Full calligraphic pipeline.
  void tessellateFountainPen(const float *points, int pointCount,
                             float r, float g, float b, float a,
                             float strokeWidth, int totalPoints,
                             std::vector<StrokeVertex> &outVerts,
                             float thinning, float nibAngleRad,
                             float nibStrength, float pressureRate,
                             int taperEntry);

  /// Generate filled circle at a point (round join/cap).
  void generateCircle(float cx, float cy, float radius, float r, float g,
                      float b, float a, std::vector<StrokeVertex> &outVerts);

  uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags props);
};
