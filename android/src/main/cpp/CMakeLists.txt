cmake_minimum_required(VERSION 3.18)
project(fluera_canvas_native C CXX)

# ═══════════════════════════════════════════════════════════════════
# Vulkan Stroke Overlay — GPU-accelerated live stroke renderer
# Ships with fluera_canvas so pub.dev consumers can pull in only the
# stroke native code without the full fluera_engine app-layer native
# footprint (rnnoise, sqlite, sentry, pdfrx, sherpa-onnx, ...).
# ═══════════════════════════════════════════════════════════════════

add_library(fluera_vk_stroke SHARED
    vk_stroke_renderer.cpp
    vk_jni_bridge.cpp
)

target_include_directories(fluera_vk_stroke PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(fluera_vk_stroke PRIVATE
    VK_USE_PLATFORM_ANDROID_KHR
)

set_target_properties(fluera_vk_stroke PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

target_compile_options(fluera_vk_stroke PRIVATE
    -O2
    -fvisibility=hidden
)

# Link Vulkan, Android, and log libraries.
# Vulkan is an NDK system library available at link time for API 24+.
# The Kotlin plugin gracefully prevents loading on API < 24.
find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(fluera_vk_stroke
    vulkan
    ${android-lib}
    ${log-lib}
)
