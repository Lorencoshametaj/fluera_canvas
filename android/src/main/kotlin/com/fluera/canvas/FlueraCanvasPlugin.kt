package com.fluera.canvas

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Entry point for the fluera_canvas Android plugin. Registers the native
 * Vulkan stroke overlay channel; nothing else.
 */
class FlueraCanvasPlugin : FlutterPlugin {
    private var vulkanStroke: VulkanStrokeOverlayPlugin? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vulkanStroke = VulkanStrokeOverlayPlugin().also { it.onAttachedToEngine(binding) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vulkanStroke?.onDetachedFromEngine(binding)
        vulkanStroke = null
    }
}
