// vk_stroke_renderer.cpp — Pure C++ Vulkan stroke renderer implementation



// Triangle strip tessellation + round caps, rendered via Vulkan swapchain



// into Flutter's ANativeWindow (TextureRegistry SurfaceTexture).







#include "vk_stroke_renderer.h"



#include "vk_shaders.h"
#include "vk_compute_shader.h"



#include <algorithm>



#include <array>



#include <cstring>







// ═══════════════════════════════════════════════════════════════════



// DESTRUCTOR



// ═══════════════════════════════════════════════════════════════════







VkStrokeRenderer::~VkStrokeRenderer() { destroy(); }







// ═══════════════════════════════════════════════════════════════════



// INIT

// Forward declaration — full definition at line ~4909
struct ComputeParams {
  float colorR, colorG, colorB, colorA;
  float strokeWidth;
  int32_t pointCount;
  int32_t brushType;
  float minPressure, maxPressure;
  float pencilBaseOpacity, pencilMaxOpacity;
  int32_t subsPerSeg;
  int32_t totalSubdivs;
  float fountainThinning, fountainNibAngleRad, fountainNibStrength;
  int32_t startSeg;
  int32_t vertexOffset;
};


// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::init(ANativeWindow *window, int width, int height) {



  if (initialized_)



    destroy();



  window_ = window;



  width_ = width;



  height_ = height;







  // Identity transform



  memset(transform_, 0, sizeof(transform_));



  transform_[0] = transform_[5] = transform_[10] = transform_[15] = 1.0f;







  if (!createInstance())



    return false;



  if (!pickPhysicalDevice())



    return false;



  if (!createDevice())



    return false;



  if (!createSurface(window))



    return false;



  if (!createSwapchain())



    return false;



  if (!createMsaaResources())



    return false;



  if (!createRenderPass())



    return false;



  if (!createPipeline())



    return false;



  if (!createFramebuffers())



    return false;



  if (!createCommandPool())



    return false;



  if (!createVertexBuffer())



    return false;



  if (!createSyncObjects())



    return false;





  // Pre-allocate vertex accumulation buffer to avoid realloc spikes
  // 🚀 Pool pre-reserves vectors, no manual reserve needed

  // 🚀 Try GPU compute tessellation (non-fatal — falls back to CPU if fails)
  createComputePipeline();

  initialized_ = true;



  LOGI("VkStrokeRenderer initialized: %dx%d", width, height);



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// VULKAN INSTANCE



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createInstance() {



  VkApplicationInfo appInfo{};



  appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;



  appInfo.pApplicationName = "FlueraStroke";



  appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);



  appInfo.pEngineName = "FluEra";



  appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);



  appInfo.apiVersion = VK_API_VERSION_1_1;







  const char *extensions[] = {



      VK_KHR_SURFACE_EXTENSION_NAME,



      VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,



  };







  VkInstanceCreateInfo ci{};



  ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;



  ci.pApplicationInfo = &appInfo;



  ci.enabledExtensionCount = 2;



  ci.ppEnabledExtensionNames = extensions;







  VK_CHECK(vkCreateInstance(&ci, nullptr, &instance_));



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// PHYSICAL DEVICE



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::pickPhysicalDevice() {



  uint32_t count = 0;



  vkEnumeratePhysicalDevices(instance_, &count, nullptr);



  if (count == 0) {



    LOGE("No Vulkan physical devices found");



    return false;



  }



  std::vector<VkPhysicalDevice> devices(count);



  vkEnumeratePhysicalDevices(instance_, &count, devices.data());



  physDevice_ = devices[0]; // Pick first device (usually the GPU)







  vkGetPhysicalDeviceProperties(physDevice_, &deviceProps_);



  LOGI("Vulkan device: %s (API %d.%d.%d)", deviceProps_.deviceName,



       VK_VERSION_MAJOR(deviceProps_.apiVersion),



       VK_VERSION_MINOR(deviceProps_.apiVersion),



       VK_VERSION_PATCH(deviceProps_.apiVersion));



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// LOGICAL DEVICE + QUEUE



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createDevice() {



  uint32_t qfCount = 0;



  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &qfCount, nullptr);



  std::vector<VkQueueFamilyProperties> qfProps(qfCount);



  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &qfCount,



                                           qfProps.data());







  queueFamily_ = UINT32_MAX;



  for (uint32_t i = 0; i < qfCount; i++) {



    if (qfProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {



      queueFamily_ = i;



      break;



    }



  }



  if (queueFamily_ == UINT32_MAX) {



    LOGE("No graphics queue family");



    return false;



  }







  float priority = 1.0f;



  VkDeviceQueueCreateInfo qci{};



  qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;



  qci.queueFamilyIndex = queueFamily_;



  qci.queueCount = 1;



  qci.pQueuePriorities = &priority;







  const char *devExts[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};







  VkDeviceCreateInfo dci{};



  dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;



  dci.queueCreateInfoCount = 1;



  dci.pQueueCreateInfos = &qci;



  dci.enabledExtensionCount = 1;



  dci.ppEnabledExtensionNames = devExts;







  VK_CHECK(vkCreateDevice(physDevice_, &dci, nullptr, &device_));



  vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// SURFACE (from ANativeWindow)



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createSurface(ANativeWindow *window) {



  VkAndroidSurfaceCreateInfoKHR sci{};



  sci.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;



  sci.window = window;



  VK_CHECK(vkCreateAndroidSurfaceKHR(instance_, &sci, nullptr, &surface_));



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// SWAPCHAIN



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createSwapchain() {



  VkSurfaceCapabilitiesKHR caps;



  vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDevice_, surface_, &caps);







  // Pick format



  uint32_t fmtCount = 0;



  vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice_, surface_, &fmtCount,



                                       nullptr);



  std::vector<VkSurfaceFormatKHR> fmts(fmtCount);



  vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice_, surface_, &fmtCount,



                                       fmts.data());







  swapFormat_ = fmts[0].format;



  VkColorSpaceKHR colorSpace = fmts[0].colorSpace;



  for (auto &f : fmts) {



    if (f.format == VK_FORMAT_R8G8B8A8_UNORM) {



      swapFormat_ = f.format;



      colorSpace = f.colorSpace;



      break;



    }



  }







  swapExtent_ = caps.currentExtent;



  if (swapExtent_.width == UINT32_MAX) {



    swapExtent_.width = static_cast<uint32_t>(width_);



    swapExtent_.height = static_cast<uint32_t>(height_);



  }







  uint32_t imageCount = caps.minImageCount + 1;



  if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount)



    imageCount = caps.maxImageCount;







  VkSwapchainCreateInfoKHR sci{};



  sci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;



  sci.surface = surface_;



  sci.minImageCount = imageCount;



  sci.imageFormat = swapFormat_;



  sci.imageColorSpace = colorSpace;



  sci.imageExtent = swapExtent_;



  sci.imageArrayLayers = 1;



  sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;



  sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;



  sci.preTransform = caps.currentTransform;



  sci.compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;



  // Prefer MAILBOX (lowest latency), fallback to FIFO



  sci.presentMode = VK_PRESENT_MODE_MAILBOX_KHR;



  sci.clipped = VK_TRUE;







  VK_CHECK(vkCreateSwapchainKHR(device_, &sci, nullptr, &swapchain_));







  uint32_t imgCount = 0;



  vkGetSwapchainImagesKHR(device_, swapchain_, &imgCount, nullptr);



  swapImages_.resize(imgCount);



  vkGetSwapchainImagesKHR(device_, swapchain_, &imgCount, swapImages_.data());







  // Create image views



  swapViews_.resize(imgCount);



  for (uint32_t i = 0; i < imgCount; i++) {



    VkImageViewCreateInfo vci{};



    vci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;



    vci.image = swapImages_[i];



    vci.viewType = VK_IMAGE_VIEW_TYPE_2D;



    vci.format = swapFormat_;



    vci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;



    vci.subresourceRange.levelCount = 1;



    vci.subresourceRange.layerCount = 1;



    VK_CHECK(vkCreateImageView(device_, &vci, nullptr, &swapViews_[i]));



  }







  return true;



}







// ═══════════════════════════════════════════════════════════════════



// RENDER PASS



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createRenderPass() {



  // Attachment 0: MSAA color (drawn to, not stored)



  VkAttachmentDescription msaaAtt{};



  msaaAtt.format = swapFormat_;



  msaaAtt.samples = msaaSamples_;



  msaaAtt.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;



  msaaAtt.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE; // Resolved, not stored



  msaaAtt.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;



  msaaAtt.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;



  msaaAtt.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;



  msaaAtt.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;







  // Attachment 1: Resolve target (swapchain image)



  VkAttachmentDescription resolveAtt{};



  resolveAtt.format = swapFormat_;



  resolveAtt.samples = VK_SAMPLE_COUNT_1_BIT;



  resolveAtt.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;



  resolveAtt.storeOp = VK_ATTACHMENT_STORE_OP_STORE;



  resolveAtt.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;



  resolveAtt.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;



  resolveAtt.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;



  resolveAtt.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;







  VkAttachmentDescription attachments[] = {msaaAtt, resolveAtt};







  VkAttachmentReference colorRef{};



  colorRef.attachment = 0; // MSAA color



  colorRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;







  VkAttachmentReference resolveRef{};



  resolveRef.attachment = 1; // Resolve target



  resolveRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;







  VkSubpassDescription sub{};



  sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;



  sub.colorAttachmentCount = 1;



  sub.pColorAttachments = &colorRef;



  sub.pResolveAttachments = &resolveRef;







  VkSubpassDependency dep{};



  dep.srcSubpass = VK_SUBPASS_EXTERNAL;



  dep.dstSubpass = 0;



  dep.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;



  dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;



  dep.srcAccessMask = 0;



  dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;







  VkRenderPassCreateInfo rpci{};



  rpci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;



  rpci.attachmentCount = 2;



  rpci.pAttachments = attachments;



  rpci.subpassCount = 1;



  rpci.pSubpasses = &sub;



  rpci.dependencyCount = 1;



  rpci.pDependencies = &dep;







  VK_CHECK(vkCreateRenderPass(device_, &rpci, nullptr, &renderPass_));



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// GRAPHICS PIPELINE



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createPipeline() {



  // Shader modules



  VkShaderModuleCreateInfo vsci{};



  vsci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;



  vsci.codeSize = vert_shader_spv_size;



  vsci.pCode = vert_shader_spv;







  VkShaderModule vertModule;



  VK_CHECK(vkCreateShaderModule(device_, &vsci, nullptr, &vertModule));







  VkShaderModuleCreateInfo fsci{};



  fsci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;



  fsci.codeSize = frag_shader_spv_size;



  fsci.pCode = frag_shader_spv;







  VkShaderModule fragModule;



  VK_CHECK(vkCreateShaderModule(device_, &fsci, nullptr, &fragModule));







  VkPipelineShaderStageCreateInfo stages[2]{};



  stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;



  stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;



  stages[0].module = vertModule;



  stages[0].pName = "main";



  stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;



  stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;



  stages[1].module = fragModule;



  stages[1].pName = "main";







  // Vertex input: float2 position + float4 color



  VkVertexInputBindingDescription binding{};



  binding.binding = 0;



  binding.stride = sizeof(StrokeVertex);



  binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;







  VkVertexInputAttributeDescription attrs[2]{};



  attrs[0].location = 0; // inPosition (vec2)



  attrs[0].binding = 0;



  attrs[0].format = VK_FORMAT_R32G32_SFLOAT;



  attrs[0].offset = offsetof(StrokeVertex, x);



  attrs[1].location = 1; // inColor (vec4)



  attrs[1].binding = 0;



  attrs[1].format = VK_FORMAT_R32G32B32A32_SFLOAT;



  attrs[1].offset = offsetof(StrokeVertex, r);







  VkPipelineVertexInputStateCreateInfo vertexInput{};



  vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;



  vertexInput.vertexBindingDescriptionCount = 1;



  vertexInput.pVertexBindingDescriptions = &binding;



  vertexInput.vertexAttributeDescriptionCount = 2;



  vertexInput.pVertexAttributeDescriptions = attrs;







  VkPipelineInputAssemblyStateCreateInfo assembly{};



  assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;



  assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;



  assembly.primitiveRestartEnable = VK_FALSE;







  // Viewport + scissor (dynamic)



  VkViewport viewport{};



  viewport.width = (float)swapExtent_.width;



  viewport.height = (float)swapExtent_.height;



  viewport.maxDepth = 1.0f;







  VkRect2D scissor{};



  scissor.extent = swapExtent_;







  VkPipelineViewportStateCreateInfo vpState{};



  vpState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;



  vpState.viewportCount = 1;



  vpState.pViewports = &viewport;



  vpState.scissorCount = 1;



  vpState.pScissors = &scissor;







  // Rasterizer



  VkPipelineRasterizationStateCreateInfo raster{};



  raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;



  raster.polygonMode = VK_POLYGON_MODE_FILL;



  raster.cullMode = VK_CULL_MODE_NONE;



  raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;



  raster.lineWidth = 1.0f;







  // No MSAA (keep it simple for v1)



  VkPipelineMultisampleStateCreateInfo msaa{};



  msaa.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;



  msaa.rasterizationSamples = msaaSamples_;







  // Blending: overwrite mode (prevents alpha accumulation at joints)



  VkPipelineColorBlendAttachmentState blendAtt{};



  blendAtt.blendEnable = VK_TRUE;



  blendAtt.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;



  blendAtt.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;



  blendAtt.colorBlendOp = VK_BLEND_OP_ADD;



  blendAtt.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;



  blendAtt.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;



  blendAtt.alphaBlendOp = VK_BLEND_OP_ADD;



  blendAtt.colorWriteMask = VK_COLOR_COMPONENT_R_BIT |



                            VK_COLOR_COMPONENT_G_BIT |



                            VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;







  VkPipelineColorBlendStateCreateInfo blend{};



  blend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;



  blend.attachmentCount = 1;



  blend.pAttachments = &blendAtt;







  // Push constants: mat4 transform (64 bytes)



  VkPushConstantRange pushRange{};



  pushRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;



  pushRange.offset = 0;



  pushRange.size = 64; // sizeof(mat4)







  VkPipelineLayoutCreateInfo layoutCI{};



  layoutCI.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;



  layoutCI.pushConstantRangeCount = 1;



  layoutCI.pPushConstantRanges = &pushRange;







  VK_CHECK(



      vkCreatePipelineLayout(device_, &layoutCI, nullptr, &pipelineLayout_));







  // Dynamic viewport/scissor for resize



  VkDynamicState dynStates[] = {



      VK_DYNAMIC_STATE_VIEWPORT,



      VK_DYNAMIC_STATE_SCISSOR,



  };



  VkPipelineDynamicStateCreateInfo dynState{};



  dynState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;



  dynState.dynamicStateCount = 2;



  dynState.pDynamicStates = dynStates;







  VkGraphicsPipelineCreateInfo pci{};



  pci.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;



  pci.stageCount = 2;



  pci.pStages = stages;



  pci.pVertexInputState = &vertexInput;



  pci.pInputAssemblyState = &assembly;



  pci.pViewportState = &vpState;



  pci.pRasterizationState = &raster;



  pci.pMultisampleState = &msaa;



  pci.pColorBlendState = &blend;



  pci.pDynamicState = &dynState;



  pci.layout = pipelineLayout_;



  pci.renderPass = renderPass_;



  pci.subpass = 0;







  VkResult r = vkCreateGraphicsPipelines(device_, VK_NULL_HANDLE, 1, &pci,



                                         nullptr, &pipeline_);



  vkDestroyShaderModule(device_, vertModule, nullptr);



  vkDestroyShaderModule(device_, fragModule, nullptr);







  if (r != VK_SUCCESS) {



    LOGE("vkCreateGraphicsPipelines failed: %d", r);



    return false;



  }



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// FRAMEBUFFERS



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createFramebuffers() {



  framebuffers_.resize(swapViews_.size());



  for (size_t i = 0; i < swapViews_.size(); i++) {



    // MSAA: attach both multisampled color and resolve target



    VkImageView attachments[] = {msaaView_, swapViews_[i]};



    VkFramebufferCreateInfo fci{};



    fci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;



    fci.renderPass = renderPass_;



    fci.attachmentCount = 2;



    fci.pAttachments = attachments;



    fci.width = swapExtent_.width;



    fci.height = swapExtent_.height;



    fci.layers = 1;



    VK_CHECK(vkCreateFramebuffer(device_, &fci, nullptr, &framebuffers_[i]));



  }



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// COMMAND POOL + BUFFER



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createCommandPool() {



  VkCommandPoolCreateInfo cpci{};



  cpci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;



  cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;



  cpci.queueFamilyIndex = queueFamily_;



  VK_CHECK(vkCreateCommandPool(device_, &cpci, nullptr, &cmdPool_));







  VkCommandBufferAllocateInfo cbai{};



  cbai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;



  cbai.commandPool = cmdPool_;



  cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;



  cbai.commandBufferCount = MAX_FRAMES_IN_FLIGHT;



  VK_CHECK(vkAllocateCommandBuffers(device_, &cbai, cmdBuffers_));



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// VERTEX BUFFER (host-visible, pre-allocated)



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createVertexBuffer() {



  VkDeviceSize size = MAX_VERTICES * sizeof(StrokeVertex);







  VkBufferCreateInfo bci{};



  bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;



  bci.size = size;



  bci.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;



  bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;



  VK_CHECK(vkCreateBuffer(device_, &bci, nullptr, &vertexBuffer_));







  VkMemoryRequirements memReq;



  vkGetBufferMemoryRequirements(device_, vertexBuffer_, &memReq);







  VkMemoryAllocateInfo mai{};



  mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;



  mai.allocationSize = memReq.size;



  mai.memoryTypeIndex = findMemoryType(



      memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |



                                 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);



  VK_CHECK(vkAllocateMemory(device_, &mai, nullptr, &vertexMemory_));



  VK_CHECK(vkBindBufferMemory(device_, vertexBuffer_, vertexMemory_, 0));







  // 🚀 Persistent mapping — stays mapped for the lifetime of the buffer



  VK_CHECK(



      vkMapMemory(device_, vertexMemory_, 0, size, 0, &mappedVertexMemory_));



  return true;



}







uint32_t VkStrokeRenderer::findMemoryType(uint32_t typeFilter,



                                          VkMemoryPropertyFlags props) {



  VkPhysicalDeviceMemoryProperties memProps;



  vkGetPhysicalDeviceMemoryProperties(physDevice_, &memProps);



  for (uint32_t i = 0; i < memProps.memoryTypeCount; i++) {



    if ((typeFilter & (1 << i)) &&



        (memProps.memoryTypes[i].propertyFlags & props) == props) {



      return i;



    }



  }



  LOGE("Failed to find suitable memory type");



  return 0;



}







// ═══════════════════════════════════════════════════════════════════



// SYNC OBJECTS



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::createSyncObjects() {



  VkSemaphoreCreateInfo sci{};



  sci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;



  VkFenceCreateInfo fci{};



  fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;



  fci.flags = VK_FENCE_CREATE_SIGNALED_BIT;







  for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {



    VK_CHECK(vkCreateSemaphore(device_, &sci, nullptr, &imageAvailSems_[i]));



    VK_CHECK(vkCreateSemaphore(device_, &sci, nullptr, &renderDoneSems_[i]));



    VK_CHECK(vkCreateFence(device_, &fci, nullptr, &frameFences_[i]));



  }



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// TESSELLATION — polyline → circle-at-point + segment quads



// Matches Dart/Skia StrokeCap.round + StrokeJoin.round exactly.



// ═══════════════════════════════════════════════════════════════════







void VkStrokeRenderer::tessellateStroke(const float *points, int pointCount,
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
  if (n >= 4) {
    const double alpha = 0.25;
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 1; i < n - 1; i++) {
        px[i] = px[i - 1] * alpha + px[i] * (1.0 - alpha);
        py[i] = py[i - 1] * alpha + py[i] * (1.0 - alpha);
      }
      for (int i = n - 2; i > 0; i--) {
        px[i] = px[i + 1] * alpha + px[i] * (1.0 - alpha);
        py[i] = py[i + 1] * alpha + py[i] * (1.0 - alpha);
      }
    }
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

void VkStrokeRenderer::generateCircle(float cx, float cy, float radius, float r,



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







void VkStrokeRenderer::tessellateMarker(const float *points, int pointCount,
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

  // ── Step 3: Compute perpendicular offsets on dense spline samples ──
  // With ~1.5px spacing, the perpendicular direction changes very gradually
  // between samples → smooth outer border, no saw-tooth.
  std::vector<Vec2> leftPts(denseCount), rightPts(denseCount);

  for (int i = 0; i < denseCount; i++) {
    float tx = 0, ty = 0;
    if (i > 0) { tx += dense[i].x - dense[i-1].x; ty += dense[i].y - dense[i-1].y; }
    if (i < denseCount - 1) { tx += dense[i+1].x - dense[i].x; ty += dense[i+1].y - dense[i].y; }
    float tLen = std::sqrt(tx * tx + ty * ty);
    if (tLen < 0.0001f) { tx = 1; ty = 0; tLen = 1; }
    tx /= tLen; ty /= tLen;
    float perpX = -ty, perpY = tx;
    leftPts[i] = {dense[i].x + perpX * halfW, dense[i].y + perpY * halfW};
    rightPts[i] = {dense[i].x - perpX * halfW, dense[i].y - perpY * halfW};
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

void VkStrokeRenderer::tessellatePencil(const float *points, int pointCount,
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
  constexpr float GRAIN_INTENSITY = 0.08f;
  constexpr float TILT_WIDTH_BOOST = 0.5f;
  constexpr float TILT_OPACITY_DROP = 0.15f;
  constexpr float VELOCITY_ALPHA_DROP = 0.10f;
  float baseHalfW = strokeWidth * 0.5f;

  auto grainHash = [](float x, float y) -> float {
    int ix = (int)(x * 7.3f); int iy = (int)(y * 11.7f);
    int h = (ix * 374761393 + iy * 668265263) ^ (ix * 1274126177);
    h = (h ^ (h >> 13)) * 1103515245;
    return (float)(h & 0x7FFFFFFF) / (float)0x7FFFFFFF;
  };

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







void VkStrokeRenderer::setTransform(const float *matrix4x4) {



  memcpy(transform_, matrix4x4, 16 * sizeof(float));



}







// ═══════════════════════════════════════════════════════════════════



// RENDER FRAME



// ═══════════════════════════════════════════════════════════════════







// ─── Technical Pen: constant width, Catmull-Rom spline, no taper ───
void VkStrokeRenderer::tessellateTechnicalPen(const float *points, int pointCount,
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

void VkStrokeRenderer::tessellateFountainPen(
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

  // ── Outline generation (left/right from tangent normals) ──────
  std::vector<double> leftX(n), leftY(n), rightX(n), rightY(n);
  for (int i = 0; i < n; i++) {
    double halfW = widths[i] * 0.5;
    double nx = -tanY[i], ny = tanX[i];
    leftX[i] = px[i] + nx * halfW;
    leftY[i] = py[i] + ny * halfW;
    rightX[i] = px[i] - nx * halfW;
    rightY[i] = py[i] - ny * halfW;
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

  // ── Chaikin corner-cutting subdivision (1 iteration) ──────────
  {
    int outLen = 2 * (n - 1) + 2;
    std::vector<double> cLX(outLen), cLY(outLen), cRX(outLen), cRY(outLen);
    int ci = 0;
    cLX[ci] = leftX[0]; cLY[ci] = leftY[0]; cRX[ci] = rightX[0]; cRY[ci] = rightY[0]; ci++;
    for (int i = 0; i < n - 1; i++) {
      cLX[ci] = leftX[i] * 0.75 + leftX[i + 1] * 0.25;
      cLY[ci] = leftY[i] * 0.75 + leftY[i + 1] * 0.25;
      cRX[ci] = rightX[i] * 0.75 + rightX[i + 1] * 0.25;
      cRY[ci] = rightY[i] * 0.75 + rightY[i + 1] * 0.25; ci++;
      cLX[ci] = leftX[i] * 0.25 + leftX[i + 1] * 0.75;
      cLY[ci] = leftY[i] * 0.25 + leftY[i + 1] * 0.75;
      cRX[ci] = rightX[i] * 0.25 + rightX[i + 1] * 0.75;
      cRY[ci] = rightY[i] * 0.25 + rightY[i + 1] * 0.75; ci++;
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

void VkStrokeRenderer::updateAndRender(const float *points, int pointCount,
                                       float r, float g, float b, float a,
                                       float strokeWidth, int totalPoints,
                                       int brushType,
                                       float pencilBaseOpacity, float pencilMaxOpacity,
                                       float pencilMinPressure, float pencilMaxPressure,
                                       float fountainThinning, float fountainNibAngleDeg,
                                       float fountainNibStrength, float fountainPressureRate,
                                       int fountainTaperEntry) {
  if (!initialized_ || pointCount < 2 || !mappedVertexMemory_)
    return;

  // 🚀 Acquire pre-reserved vertex vector from pool (zero alloc hot path)
  int poolSlot;
  auto& verts = vertexPool_.acquire(poolSlot);

  if (brushType == 0) {
    // ── FULL RETESSELLATION (ballpoint) ──────────────────────────
    // Both the ring buffer (g_ringAccumPoints) and the flat FFI/MethodChannel
    // already send ALL accumulated points for ballpoint.
    // Tessellate directly from incoming buffer — no internal accumulation
    // (allPoints_ caused double-accumulation with ring buffer → fan artifact).
    totalAccumulatedPoints_ = pointCount;

    if (pointCount >= 2) {
      tessellateStroke(points, pointCount,
                       r, g, b, a, strokeWidth,
                       0, totalPoints, verts,
                       pencilMinPressure, pencilMaxPressure);
    }

    if (verts.size() > MAX_VERTICES) {
      verts.resize(MAX_VERTICES);
    }

    vertexCount_ = static_cast<uint32_t>(verts.size());

    // Upload entire vertex buffer
    if (vertexCount_ > 0) {
      auto *dst = reinterpret_cast<StrokeVertex *>(mappedVertexMemory_);
      memcpy(dst, verts.data(),
             vertexCount_ * sizeof(StrokeVertex));
    }
  } else {
    // ── 🚀 ASYNC TESSELLATION (marker/pencil/technical/fountain) ───
    // These brushes need ALL points — offload to worker thread.
    // Render thread continues drawing previous frame's geometry.
    totalAccumulatedPoints_ = pointCount;

    // Start worker thread on first use
    if (!tessThreadStarted_) {
      tessThread_.start();
      tessThreadStarted_ = true;
    }

    // Copy point data for thread safety (worker needs stable data)
    asyncPointsCopy_.assign(points, points + pointCount * 5);
    const int pc = pointCount;
    const float cr = r, cg = g, cb = b, ca = a;
    const float sw = strokeWidth;
    const int bt = brushType;
    const float pbo = pencilBaseOpacity, pmo = pencilMaxOpacity;
    const float pmp = pencilMinPressure, pmxp = pencilMaxPressure;
    const float ft = fountainThinning, fna = fountainNibAngleDeg;
    const float fns = fountainNibStrength, fpr = fountainPressureRate;
    const int fte = fountainTaperEntry;

    // Submit tessellation task to worker thread
    tessThread_.submit([this, pc, cr, cg, cb, ca, sw, bt,
                        pbo, pmo, pmp, pmxp, ft, fna, fns, fpr, fte]
                       (std::vector<StrokeVertex>& out) {
      const float* pts = asyncPointsCopy_.data();
      if (bt == 1) {
        tessellateMarker(pts, pc, cr, cg, cb, ca, sw, out);
      } else if (bt == 3) {
        tessellateTechnicalPen(pts, pc, cr, cg, cb, ca, sw, out);
      } else if (bt == 4) {
        float nibRad = fna * (float)M_PI / 180.0f;
        tessellateFountainPen(pts, pc, cr, cg, cb, ca, sw,
                              pc, out, ft, nibRad, fns, fpr, fte);
      } else {
        // brushType == 2 (pencil)
        tessellatePencil(pts, pc, cr, cg, cb, ca, sw,
                         0, pc, out, pbo, pmo, pmp, pmxp);
      }
    });

    // Check if worker produced new results → swap + upload
    if (tessThread_.trySwap()) {
      const auto& front = tessThread_.frontVertices();
      uint32_t count = tessThread_.frontVertexCount();
      if (count > MAX_VERTICES) count = MAX_VERTICES;
      vertexCount_ = count;
      if (vertexCount_ > 0) {
        auto *dst = reinterpret_cast<StrokeVertex *>(mappedVertexMemory_);
        memcpy(dst, front.data(), vertexCount_ * sizeof(StrokeVertex));
      }
    }
    // else: render thread draws previous frame's geometry (no stall)

    vertexPool_.release(poolSlot);
  }

  // 🚀 Release vector back to pool (keeps capacity, resets size)
  if (brushType == 0) {
    vertexPool_.release(poolSlot);
  }

  statsActive_ = true;

  // Track whether this frame uses GPU compute or CPU tessellation
  // 🚀 Ballpoint (0) excluded: uses specialised EMA + cap tessellation on CPU
  // 🎨 Fountain pen (4) excluded: needs per-point nib angle + Chaikin + arc-length on CPU
  bool useCompute = computeAvailable_ && computePipeline_ && brushType != 0 && brushType != 4;




  statsDrawCalls_ = 1;



  statsTotalFrames_++;



  // ─── Record + submit (triple-buffered) ─────────────────────



  uint32_t f = currentFrame_;



  VkResult fenceResult = vkWaitForFences(device_, 1, &frameFences_[f], VK_TRUE, 5000000); // 5ms timeout
  if (fenceResult == VK_TIMEOUT) {
    LOGI("VkStrokeRenderer: fence timeout, skipping frame");
    return; // Skip frame to avoid GPU backlog stall
  }



  vkResetFences(device_, 1, &frameFences_[f]);

  // Start timing AFTER fence wait — measure actual work, not sync idle
  auto frameStart = std::chrono::steady_clock::now();





  uint32_t imageIndex;



  VkResult acqResult =



      vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, imageAvailSems_[f],



                            VK_NULL_HANDLE, &imageIndex);



  if (acqResult == VK_ERROR_OUT_OF_DATE_KHR) {



    resize(width_, height_);



    return;



  }







  vkResetCommandBuffer(cmdBuffers_[f], 0);







  VkCommandBufferBeginInfo beginInfo{};



  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;



  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;



  vkBeginCommandBuffer(cmdBuffers_[f], &beginInfo);

  // ─── 🚀 GPU Compute tessellation dispatch (before render pass) ───
  if (useCompute) {
    int totalSubdivs = (totalAccumulatedPoints_ - 1) * SUBS_PER_SEG;

    // Upload points to SSBO
    size_t pointBytes = totalAccumulatedPoints_ * 5 * sizeof(float);
    if (pointBytes > MAX_POINTS_SSBO) pointBytes = MAX_POINTS_SSBO;
    if (brushType == 0) {
      memcpy(mappedPointsSSBO_, allPoints_.data(), pointBytes);
    } else {
      memcpy(mappedPointsSSBO_, points, pointBytes);
    }

    // Upload params
    ComputeParams params{};
    params.colorR = r; params.colorG = g; params.colorB = b; params.colorA = a;
    params.strokeWidth = strokeWidth;
    params.pointCount = totalAccumulatedPoints_;
    params.brushType = brushType;
    params.minPressure = pencilMinPressure;
    params.maxPressure = pencilMaxPressure;
    params.pencilBaseOpacity = pencilBaseOpacity;
    params.pencilMaxOpacity = pencilMaxOpacity;
    params.subsPerSeg = SUBS_PER_SEG;
    params.totalSubdivs = totalSubdivs;
    memcpy(mappedComputeParams_, &params, sizeof(ComputeParams));

    // Reset cap counter
    *(int32_t*)mappedCapCounter_ = 0;

    // Bind compute pipeline and dispatch
    vkCmdBindPipeline(cmdBuffers_[f], VK_PIPELINE_BIND_POINT_COMPUTE, computePipeline_);
    vkCmdBindDescriptorSets(cmdBuffers_[f], VK_PIPELINE_BIND_POINT_COMPUTE,
                            computePipelineLayout_, 0, 1, &computeDescSet_, 0, nullptr);
    uint32_t groups = (totalSubdivs + 63) / 64;
    vkCmdDispatch(cmdBuffers_[f], groups, 1, 1);

    // Memory barrier: compute writes → vertex reads
    VkMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffers_[f],
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,
                         0, 1, &barrier, 0, nullptr, 0, nullptr);

    vertexCount_ = totalSubdivs * 6;
    // 🚀 #7: Include cap vertices in stats (2 caps × adaptive segments × 3 verts)
    if (brushType == 0 || brushType == 3) {
      int capSegs = std::clamp(dynamicSubsPerSeg_, 4, 16);
      vertexCount_ += 2 * capSegs * 3;
    }
  }

  VkClearValue clearVals[2]{};



  clearVals[0].color = {{0.0f, 0.0f, 0.0f, 0.0f}};



  clearVals[1].color = {{0.0f, 0.0f, 0.0f, 0.0f}};







  VkRenderPassBeginInfo rpbi{};



  rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;



  rpbi.renderPass = renderPass_;



  rpbi.framebuffer = framebuffers_[imageIndex];



  rpbi.renderArea.extent = swapExtent_;



  rpbi.clearValueCount = 2;



  rpbi.pClearValues = clearVals;







  vkCmdBeginRenderPass(cmdBuffers_[f], &rpbi, VK_SUBPASS_CONTENTS_INLINE);



  vkCmdBindPipeline(cmdBuffers_[f], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_);







  VkViewport vp{};



  vp.width = (float)swapExtent_.width;



  vp.height = (float)swapExtent_.height;



  vp.maxDepth = 1.0f;



  vkCmdSetViewport(cmdBuffers_[f], 0, 1, &vp);







  VkRect2D sc{};



  sc.extent = swapExtent_;



  vkCmdSetScissor(cmdBuffers_[f], 0, 1, &sc);







  vkCmdPushConstants(cmdBuffers_[f], pipelineLayout_,



                     VK_SHADER_STAGE_VERTEX_BIT, 0, 64, transform_);







  VkDeviceSize offset = 0;



  // 🚀 Bind compute output SSBO as vertex buffer when GPU compute is active
  if (useCompute) {
    vkCmdBindVertexBuffers(cmdBuffers_[f], 0, 1, &computeVertexSSBO_, &offset);
  } else {
    vkCmdBindVertexBuffers(cmdBuffers_[f], 0, 1, &vertexBuffer_, &offset);
  }



  // 🚀 Indirect draw: GPU-driven vertex count for compute path
  if (useCompute && indirectDrawAvailable_) {
    vkCmdDrawIndirect(cmdBuffers_[f], indirectDrawBuffer_, 0, 1, 0);
  } else {
    vkCmdDraw(cmdBuffers_[f], vertexCount_, 1, 0, 0);
  }







  vkCmdEndRenderPass(cmdBuffers_[f]);



  vkEndCommandBuffer(cmdBuffers_[f]);







  VkPipelineStageFlags waitStage =



      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;



  VkSubmitInfo si{};



  si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;



  si.waitSemaphoreCount = 1;



  si.pWaitSemaphores = &imageAvailSems_[f];



  si.pWaitDstStageMask = &waitStage;



  si.commandBufferCount = 1;



  si.pCommandBuffers = &cmdBuffers_[f];



  si.signalSemaphoreCount = 1;



  si.pSignalSemaphores = &renderDoneSems_[f];



  vkQueueSubmit(queue_, 1, &si, frameFences_[f]);







  VkPresentInfoKHR pi{};



  pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;



  pi.waitSemaphoreCount = 1;



  pi.pWaitSemaphores = &renderDoneSems_[f];



  pi.swapchainCount = 1;



  pi.pSwapchains = &swapchain_;



  pi.pImageIndices = &imageIndex;



  vkQueuePresentKHR(queue_, &pi);







  // ─── End stats timing ─────────────────────────────────────



  auto frameEnd = std::chrono::steady_clock::now();



  auto frameUs = std::chrono::duration_cast<std::chrono::microseconds>(



                     frameEnd - frameStart)



                     .count();



  frameTimesUs_.push_back(static_cast<float>(frameUs));



  if ((int)frameTimesUs_.size() > STATS_MAX_SAMPLES) {



    frameTimesUs_.erase(frameTimesUs_.begin());



  }







  currentFrame_ = (currentFrame_ + 1) % MAX_FRAMES_IN_FLIGHT;



}







void VkStrokeRenderer::clearFrame() {



  if (!initialized_)



    return;







  vertexPool_.releaseAll();



  allPoints_.clear();



  vertexCount_ = 0;



  totalAccumulatedPoints_ = 0;



  statsActive_ = false;



  hasLastFrameTime_ = false;







  uint32_t f = currentFrame_;



  // 🚀 P99 FIX: bounded fence wait (was UINT64_MAX — could stall raster thread)
  VkResult clearFenceResult = vkWaitForFences(device_, 1, &frameFences_[f], VK_TRUE, 5000000); // 5ms
  if (clearFenceResult == VK_TIMEOUT) {
    LOGI("VkStrokeRenderer: clearFrame fence timeout, skipping");
    return;
  }

  vkResetFences(device_, 1, &frameFences_[f]);







  uint32_t imageIndex;



  VkResult acqResult =



      vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, imageAvailSems_[f],



                            VK_NULL_HANDLE, &imageIndex);



  if (acqResult != VK_SUCCESS)



    return;







  vkResetCommandBuffer(cmdBuffers_[f], 0);







  VkCommandBufferBeginInfo beginInfo{};



  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;



  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;



  vkBeginCommandBuffer(cmdBuffers_[f], &beginInfo);







  VkClearValue clearVals[2]{};



  clearVals[0].color = {{0.0f, 0.0f, 0.0f, 0.0f}};



  clearVals[1].color = {{0.0f, 0.0f, 0.0f, 0.0f}};







  VkRenderPassBeginInfo rpbi{};



  rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;



  rpbi.renderPass = renderPass_;



  rpbi.framebuffer = framebuffers_[imageIndex];



  rpbi.renderArea.extent = swapExtent_;



  rpbi.clearValueCount = 2;



  rpbi.pClearValues = clearVals;







  vkCmdBeginRenderPass(cmdBuffers_[f], &rpbi, VK_SUBPASS_CONTENTS_INLINE);



  vkCmdEndRenderPass(cmdBuffers_[f]);



  vkEndCommandBuffer(cmdBuffers_[f]);







  VkPipelineStageFlags waitStage =



      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;



  VkSubmitInfo si{};



  si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;



  si.waitSemaphoreCount = 1;



  si.pWaitSemaphores = &imageAvailSems_[f];



  si.pWaitDstStageMask = &waitStage;



  si.commandBufferCount = 1;



  si.pCommandBuffers = &cmdBuffers_[f];



  si.signalSemaphoreCount = 1;



  si.pSignalSemaphores = &renderDoneSems_[f];



  vkQueueSubmit(queue_, 1, &si, frameFences_[f]);







  VkPresentInfoKHR pi{};



  pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;



  pi.waitSemaphoreCount = 1;



  pi.pWaitSemaphores = &renderDoneSems_[f];



  pi.swapchainCount = 1;



  pi.pSwapchains = &swapchain_;



  pi.pImageIndices = &imageIndex;



  vkQueuePresentKHR(queue_, &pi);







  currentFrame_ = (currentFrame_ + 1) % MAX_FRAMES_IN_FLIGHT;



}







// ═══════════════════════════════════════════════════════════════════



// RESIZE



// ═══════════════════════════════════════════════════════════════════







bool VkStrokeRenderer::resize(int width, int height) {



  if (!initialized_)



    return false;



  vkDeviceWaitIdle(device_);







  width_ = width;



  height_ = height;







  destroySwapchain();



  if (!createSwapchain())



    return false;



  if (!createFramebuffers())



    return false;







  LOGI("VkStrokeRenderer resized: %dx%d", width, height);



  return true;



}







// ═══════════════════════════════════════════════════════════════════



// CLEANUP



// ═══════════════════════════════════════════════════════════════════







void VkStrokeRenderer::destroySwapchain() {



  for (auto fb : framebuffers_)



    vkDestroyFramebuffer(device_, fb, nullptr);



  framebuffers_.clear();



  destroyMsaaResources();



  for (auto iv : swapViews_)



    vkDestroyImageView(device_, iv, nullptr);



  swapViews_.clear();



  if (swapchain_)



    vkDestroySwapchainKHR(device_, swapchain_, nullptr);



  swapchain_ = VK_NULL_HANDLE;



  swapImages_.clear();



}







bool VkStrokeRenderer::createMsaaResources() {



  VkImageCreateInfo ici{};



  ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;



  ici.imageType = VK_IMAGE_TYPE_2D;



  ici.format = swapFormat_;



  ici.extent = {swapExtent_.width, swapExtent_.height, 1};



  ici.mipLevels = 1;



  ici.arrayLayers = 1;



  ici.samples = msaaSamples_;



  ici.tiling = VK_IMAGE_TILING_OPTIMAL;



  ici.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |



              VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;



  ici.sharingMode = VK_SHARING_MODE_EXCLUSIVE;



  ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;







  VK_CHECK(vkCreateImage(device_, &ici, nullptr, &msaaImage_));







  VkMemoryRequirements memReq;



  vkGetImageMemoryRequirements(device_, msaaImage_, &memReq);







  VkMemoryAllocateInfo mai{};



  mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;



  mai.allocationSize = memReq.size;



  // Prefer LAZILY_ALLOCATED for transient MSAA (GPU-only, never stored)



  uint32_t memType = findMemoryType(memReq.memoryTypeBits,



                                    VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT |



                                        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);



  if (memType == 0) {



    // Fallback to regular device-local



    memType = findMemoryType(memReq.memoryTypeBits,



                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);



  }



  mai.memoryTypeIndex = memType;



  VK_CHECK(vkAllocateMemory(device_, &mai, nullptr, &msaaMemory_));



  VK_CHECK(vkBindImageMemory(device_, msaaImage_, msaaMemory_, 0));







  VkImageViewCreateInfo vci{};



  vci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;



  vci.image = msaaImage_;



  vci.viewType = VK_IMAGE_VIEW_TYPE_2D;



  vci.format = swapFormat_;



  vci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;



  vci.subresourceRange.levelCount = 1;



  vci.subresourceRange.layerCount = 1;



  VK_CHECK(vkCreateImageView(device_, &vci, nullptr, &msaaView_));







  LOGI("MSAA 4x resources created");



  return true;



}







void VkStrokeRenderer::destroyMsaaResources() {



  if (msaaView_)



    vkDestroyImageView(device_, msaaView_, nullptr);



  if (msaaImage_)



    vkDestroyImage(device_, msaaImage_, nullptr);



  if (msaaMemory_)



    vkFreeMemory(device_, msaaMemory_, nullptr);



  msaaView_ = VK_NULL_HANDLE;



  msaaImage_ = VK_NULL_HANDLE;



  msaaMemory_ = VK_NULL_HANDLE;



}







// ═══════════════════════════════════════════════════════════════════
// 🚀 MEMORY PRESSURE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════

void VkStrokeRenderer::trimMemory(int level) {
  if (level >= 1) {
    // Warning: trim free pool buffers to initial capacity
    vertexPool_.trim();
    LOGI("trimMemory(warning): vertex pool trimmed, %zu bytes reserved",
         vertexPool_.totalReservedBytes());
  }
  if (level >= 2) {
    // Critical: release ALL pool buffers + shrink vectors
    vertexPool_.releaseAll();
    vertexPool_.trim();

    // Shrink allPoints_ to zero (will re-grow on next stroke)
    allPoints_.clear();
    allPoints_.shrink_to_fit();

    // Shrink async points copy
    asyncPointsCopy_.clear();
    asyncPointsCopy_.shrink_to_fit();

    LOGI("trimMemory(critical): all buffers freed, %zu bytes remaining",
         vertexPool_.totalReservedBytes());
  }
}

// 🚀 Adaptive LOD
void VkStrokeRenderer::setZoomLevel(float zoom) {
  int prev = dynamicSubsPerSeg_;
  if (zoom < 0.3f) dynamicSubsPerSeg_ = 4;
  else if (zoom < 0.6f) dynamicSubsPerSeg_ = 6;
  else if (zoom > 4.0f) dynamicSubsPerSeg_ = 16;
  else if (zoom > 2.0f) dynamicSubsPerSeg_ = 12;
  else dynamicSubsPerSeg_ = 8;
  if (dynamicSubsPerSeg_ != prev) {
    LOGI("[FlueraVk] \xF0\x9F\x94\x8D LOD zoom=%.2f subsPerSeg=%d->%d", zoom, prev, dynamicSubsPerSeg_);
  }
}

void VkStrokeRenderer::destroy() {



  // 🚀 Stop tessellation worker thread first
  if (tessThreadStarted_) {
    tessThread_.stop();
    tessThreadStarted_ = false;
  }

  destroyComputeResources(); // 🚀 Free compute resources first

  if (!instance_)



    return;



  if (device_)



    vkDeviceWaitIdle(device_);







  for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {



    if (frameFences_[i])



      vkDestroyFence(device_, frameFences_[i], nullptr);



    if (imageAvailSems_[i])



      vkDestroySemaphore(device_, imageAvailSems_[i], nullptr);



    if (renderDoneSems_[i])



      vkDestroySemaphore(device_, renderDoneSems_[i], nullptr);



  }







  if (vertexBuffer_)



    vkDestroyBuffer(device_, vertexBuffer_, nullptr);



  if (vertexMemory_) {



    if (mappedVertexMemory_) {



      vkUnmapMemory(device_, vertexMemory_);



      mappedVertexMemory_ = nullptr;



    }



    vkFreeMemory(device_, vertexMemory_, nullptr);



  }







  if (cmdPool_)



    vkDestroyCommandPool(device_, cmdPool_, nullptr);



  if (pipeline_)



    vkDestroyPipeline(device_, pipeline_, nullptr);



  if (pipelineLayout_)



    vkDestroyPipelineLayout(device_, pipelineLayout_, nullptr);



  if (renderPass_)



    vkDestroyRenderPass(device_, renderPass_, nullptr);







  destroySwapchain();







  if (surface_)



    vkDestroySurfaceKHR(instance_, surface_, nullptr);



  if (device_)



    vkDestroyDevice(device_, nullptr);



  if (instance_)



    vkDestroyInstance(instance_, nullptr);







  if (window_)



    ANativeWindow_release(window_);







  instance_ = VK_NULL_HANDLE;



  device_ = VK_NULL_HANDLE;



  surface_ = VK_NULL_HANDLE;



  window_ = nullptr;



  initialized_ = false;



  frameTimesUs_.clear();



  statsDrawCalls_ = 0;



  statsTotalFrames_ = 0;



  statsActive_ = false;



  hasLastFrameTime_ = false;







  LOGI("VkStrokeRenderer destroyed");



}







// ═══════════════════════════════════════════════════════════════════



// PERFORMANCE STATS



// ═══════════════════════════════════════════════════════════════════







VkStrokeStats VkStrokeRenderer::getStats() const {



  VkStrokeStats s{};







  // Compute percentiles from rolling frame time buffer



  if (!frameTimesUs_.empty()) {



    std::vector<float> sorted(frameTimesUs_);



    std::sort(sorted.begin(), sorted.end());



    int n = (int)sorted.size();



    s.frameTimeP50Us = sorted[n / 2];



    s.frameTimeP90Us = sorted[std::min((int)(n * 0.9f), n - 1)];



    s.frameTimeP99Us = sorted[std::min((int)(n * 0.99f), n - 1)];



  }







  s.vertexCount = vertexCount_;



  s.drawCalls = statsDrawCalls_;



  s.swapchainImages = (uint32_t)swapImages_.size();



  s.totalFrames = statsTotalFrames_;



  s.active = statsActive_;







  // Device info



  strncpy(s.deviceName, deviceProps_.deviceName, sizeof(s.deviceName) - 1);



  s.deviceName[sizeof(s.deviceName) - 1] = '\0';



  s.apiVersionMajor = VK_VERSION_MAJOR(deviceProps_.apiVersion);



  s.apiVersionMinor = VK_VERSION_MINOR(deviceProps_.apiVersion);



  s.apiVersionPatch = VK_VERSION_PATCH(deviceProps_.apiVersion);







  return s;



}

// ═══════════════════════════════════════════════════════════════════
// 🚀 GPU COMPUTE TESSELLATION — Implementation
// ═══════════════════════════════════════════════════════════════════

// ComputeParams defined at top of file (mirrors Params in stroke_compute.comp)


static VkBuffer createBuffer(VkDevice device, VkPhysicalDevice physDevice,
                              VkDeviceSize size, VkBufferUsageFlags usage,
                              VkMemoryPropertyFlags memProps,
                              VkDeviceMemory &memory) {
  VkBuffer buffer;
  VkBufferCreateInfo ci{};
  ci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  ci.size = size;
  ci.usage = usage;
  ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  if (vkCreateBuffer(device, &ci, nullptr, &buffer) != VK_SUCCESS)
    return VK_NULL_HANDLE;

  VkMemoryRequirements req;
  vkGetBufferMemoryRequirements(device, buffer, &req);

  VkPhysicalDeviceMemoryProperties memProp;
  vkGetPhysicalDeviceMemoryProperties(physDevice, &memProp);
  uint32_t memIdx = UINT32_MAX;
  for (uint32_t i = 0; i < memProp.memoryTypeCount; i++) {
    if ((req.memoryTypeBits & (1 << i)) &&
        (memProp.memoryTypes[i].propertyFlags & memProps) == memProps) {
      memIdx = i;
      break;
    }
  }
  if (memIdx == UINT32_MAX) { vkDestroyBuffer(device, buffer, nullptr); return VK_NULL_HANDLE; }

  VkMemoryAllocateInfo ai{};
  ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  ai.allocationSize = req.size;
  ai.memoryTypeIndex = memIdx;
  if (vkAllocateMemory(device, &ai, nullptr, &memory) != VK_SUCCESS) {
    vkDestroyBuffer(device, buffer, nullptr);
    return VK_NULL_HANDLE;
  }
  vkBindBufferMemory(device, buffer, memory, 0);
  return buffer;
}

bool VkStrokeRenderer::createComputeBuffers() {
  auto hostFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  auto deviceFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
  auto ssboUsage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;

  // Points SSBO (host-visible — written by CPU from FFI buffer)
  pointsSSBO_ = createBuffer(device_, physDevice_, MAX_POINTS_SSBO,
                             ssboUsage, hostFlags, pointsSSBOMemory_);
  if (!pointsSSBO_) return false;
  vkMapMemory(device_, pointsSSBOMemory_, 0, MAX_POINTS_SSBO, 0, &mappedPointsSSBO_);

  // Params UBO (host-visible)
  computeParamsUBO_ = createBuffer(device_, physDevice_, sizeof(ComputeParams),
                                   VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, hostFlags,
                                   computeParamsMemory_);
  if (!computeParamsUBO_) return false;
  vkMapMemory(device_, computeParamsMemory_, 0, sizeof(ComputeParams), 0, &mappedComputeParams_);

  // Vertex output SSBO (device-local preferred, but host-visible for readback)
  // Max: 1000 segments × 8 subs × 6 verts × 6 floats = 288000 floats
  VkDeviceSize vertOutSize = 1000 * SUBS_PER_SEG * 6 * 6 * sizeof(float);
  computeVertexSSBO_ = createBuffer(device_, physDevice_, vertOutSize,
                                    ssboUsage | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                                    hostFlags, computeVertexSSBOMemory_);
  if (!computeVertexSSBO_) return false;

  // Cap SSBO (max 2 caps × 12 segments × 3 verts × 6 floats)
  VkDeviceSize capSize = 2 * 16 * 3 * 6 * sizeof(float);
  computeCapSSBO_ = createBuffer(device_, physDevice_, capSize,
                                 ssboUsage | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                                 hostFlags, computeCapSSBOMemory_);
  if (!computeCapSSBO_) return false;

  // Cap counter SSBO (single int, host-visible for reset)
  computeCapCounterSSBO_ = createBuffer(device_, physDevice_, sizeof(int32_t),
                                        ssboUsage, hostFlags, computeCapCounterMemory_);
  if (!computeCapCounterSSBO_) return false;
  vkMapMemory(device_, computeCapCounterMemory_, 0, sizeof(int32_t), 0, &mappedCapCounter_);
  *(int32_t*)mappedCapCounter_ = 0;

  return true;
}

bool VkStrokeRenderer::createComputePipeline() {
  if (!createComputeBuffers()) {
    LOGI("[FlueraVk] Compute buffers failed, using CPU tessellation");
    return false;
  }

  // ── Descriptor set layout: 5 bindings ──
  VkDescriptorSetLayoutBinding bindings[5] = {};
  // 0: Params UBO
  bindings[0].binding = 0;
  bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  bindings[0].descriptorCount = 1;
  bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  // 1: Points SSBO (read)
  bindings[1].binding = 1;
  bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[1].descriptorCount = 1;
  bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  // 2: Vertices SSBO (write)
  bindings[2].binding = 2;
  bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[2].descriptorCount = 1;
  bindings[2].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  // 3: Cap counter SSBO
  bindings[3].binding = 3;
  bindings[3].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[3].descriptorCount = 1;
  bindings[3].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  // 4: Caps SSBO (write)
  bindings[4].binding = 4;
  bindings[4].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[4].descriptorCount = 1;
  bindings[4].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

  VkDescriptorSetLayoutCreateInfo layoutCI{};
  layoutCI.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  layoutCI.bindingCount = 5;
  layoutCI.pBindings = bindings;
  if (vkCreateDescriptorSetLayout(device_, &layoutCI, nullptr, &computeDescSetLayout_) != VK_SUCCESS)
    return false;

  // ── Descriptor pool ──
  VkDescriptorPoolSize poolSizes[2] = {};
  poolSizes[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  poolSizes[0].descriptorCount = 1;
  poolSizes[1].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  poolSizes[1].descriptorCount = 4;

  VkDescriptorPoolCreateInfo poolCI{};
  poolCI.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  poolCI.maxSets = 1;
  poolCI.poolSizeCount = 2;
  poolCI.pPoolSizes = poolSizes;
  if (vkCreateDescriptorPool(device_, &poolCI, nullptr, &computeDescPool_) != VK_SUCCESS)
    return false;

  // ── Allocate descriptor set ──
  VkDescriptorSetAllocateInfo allocInfo{};
  allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  allocInfo.descriptorPool = computeDescPool_;
  allocInfo.descriptorSetCount = 1;
  allocInfo.pSetLayouts = &computeDescSetLayout_;
  if (vkAllocateDescriptorSets(device_, &allocInfo, &computeDescSet_) != VK_SUCCESS)
    return false;

  // ── Write descriptor set ──
  VkDescriptorBufferInfo paramsBI{computeParamsUBO_, 0, sizeof(ComputeParams)};
  VkDescriptorBufferInfo pointsBI{pointsSSBO_, 0, MAX_POINTS_SSBO};
  VkDeviceSize vertOutSize = 1000 * SUBS_PER_SEG * 6 * 6 * sizeof(float);
  VkDescriptorBufferInfo vertsBI{computeVertexSSBO_, 0, vertOutSize};
  VkDescriptorBufferInfo capCntBI{computeCapCounterSSBO_, 0, sizeof(int32_t)};
  VkDeviceSize capSize = 2 * 16 * 3 * 6 * sizeof(float);
  VkDescriptorBufferInfo capsBI{computeCapSSBO_, 0, capSize};

  VkWriteDescriptorSet writes[5] = {};
  for (int i = 0; i < 5; i++) {
    writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[i].dstSet = computeDescSet_;
    writes[i].dstBinding = i;
    writes[i].descriptorCount = 1;
  }
  writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  writes[0].pBufferInfo = &paramsBI;
  writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  writes[1].pBufferInfo = &pointsBI;
  writes[2].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  writes[2].pBufferInfo = &vertsBI;
  writes[3].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  writes[3].pBufferInfo = &capCntBI;
  writes[4].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  writes[4].pBufferInfo = &capsBI;
  vkUpdateDescriptorSets(device_, 5, writes, 0, nullptr);

  // ── Pipeline layout ──
  VkPipelineLayoutCreateInfo plCI{};
  plCI.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  plCI.setLayoutCount = 1;
  plCI.pSetLayouts = &computeDescSetLayout_;
  if (vkCreatePipelineLayout(device_, &plCI, nullptr, &computePipelineLayout_) != VK_SUCCESS)
    return false;

  // ── SPIR-V shader module (embedded from vk_compute_shader.h) ──
  VkShaderModuleCreateInfo smCI{};
  smCI.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  smCI.codeSize = stroke_compute_spv_size;
  smCI.pCode = stroke_compute_spv;
  VkShaderModule compShaderModule;
  if (vkCreateShaderModule(device_, &smCI, nullptr, &compShaderModule) != VK_SUCCESS) {
    LOGE("[FlueraVk] Failed to create compute shader module");
    return false;
  }

  // ── Compute pipeline ──
  VkPipelineShaderStageCreateInfo stageCI{};
  stageCI.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  stageCI.stage = VK_SHADER_STAGE_COMPUTE_BIT;
  stageCI.module = compShaderModule;
  stageCI.pName = "main";

  VkComputePipelineCreateInfo cpCI{};
  cpCI.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
  cpCI.stage = stageCI;
  cpCI.layout = computePipelineLayout_;
  if (vkCreateComputePipelines(device_, VK_NULL_HANDLE, 1, &cpCI, nullptr, &computePipeline_) != VK_SUCCESS) {
    vkDestroyShaderModule(device_, compShaderModule, nullptr);
    LOGE("[FlueraVk] Failed to create compute pipeline");
    return false;
  }
  vkDestroyShaderModule(device_, compShaderModule, nullptr); // No longer needed

  computeAvailable_ = true;
  LOGI("[FlueraVk] \xF0\x9F\x9A\x80 Compute tessellation pipeline ready");

  // 🔥 Warm-up: dispatch 1-workgroup dummy compute to pre-compile pipeline
  {
    VkCommandBufferAllocateInfo ai{};
    ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    ai.commandPool = cmdPool_;
    ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    ai.commandBufferCount = 1;
    VkCommandBuffer cmd;
    if (vkAllocateCommandBuffers(device_, &ai, &cmd) == VK_SUCCESS) {
      VkCommandBufferBeginInfo bi{};
      bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
      bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
      vkBeginCommandBuffer(cmd, &bi);
      vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, computePipeline_);
      vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE,
                               computePipelineLayout_, 0, 1, &computeDescSet_, 0, nullptr);
      vkCmdDispatch(cmd, 1, 1, 1);
      vkEndCommandBuffer(cmd);
      VkSubmitInfo si{};
      si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
      si.commandBufferCount = 1;
      si.pCommandBuffers = &cmd;
      vkQueueSubmit(queue_, 1, &si, VK_NULL_HANDLE);
      vkQueueWaitIdle(queue_);
      vkFreeCommandBuffers(device_, cmdPool_, 1, &cmd);
      LOGI("[FlueraVk] 🔥 Shader warm-up complete");
    }
  }

  return true;
}

void VkStrokeRenderer::dispatchCompute(const float *points, int pointCount,
                                       int brushType, float r, float g, float b,
                                       float a, float strokeWidth,
                                       float minPressure, float maxPressure,
                                       float pencilBaseOpacity, float pencilMaxOpacity) {
  if (!computeAvailable_ || !computePipeline_) return;

  // 🚀 Incremental + adaptive LOD
  int subsPerSeg = dynamicSubsPerSeg_;
  int startSeg = 0;
  if (prevComputePointCount_ >= 2 && pointCount > prevComputePointCount_) {
    startSeg = std::max(0, prevComputePointCount_ - 2);
  }
  int newSubdivs = (pointCount - 1 - startSeg) * subsPerSeg;
  int totalSubdivs = (pointCount - 1) * subsPerSeg;
  int vertexOffset = startSeg * subsPerSeg;

  // Upload points to SSBO
  size_t pointBytes = pointCount * 5 * sizeof(float);
  if (pointBytes > MAX_POINTS_SSBO) pointBytes = MAX_POINTS_SSBO;
  memcpy(mappedPointsSSBO_, points, pointBytes);

  // Upload params (with incremental fields)
  ComputeParams params{};
  params.colorR = r;
  params.colorG = g;
  params.colorB = b;
  params.colorA = a;
  params.strokeWidth = strokeWidth;
  params.pointCount = pointCount;
  params.brushType = brushType;
  params.minPressure = minPressure;
  params.maxPressure = maxPressure;
  params.pencilBaseOpacity = pencilBaseOpacity;
  params.pencilMaxOpacity = pencilMaxOpacity;
  params.subsPerSeg = subsPerSeg;
  params.totalSubdivs = newSubdivs;  // Only new portion!
  params.startSeg = startSeg;
  params.vertexOffset = vertexOffset;
  memcpy(mappedComputeParams_, &params, sizeof(ComputeParams));

  // Reset cap counter
  *(int32_t*)mappedCapCounter_ = 0;

  // Dispatch: only new subdivisions
  uint32_t groups = (newSubdivs + 63) / 64;

  prevComputePointCount_ = pointCount;

  // The vertex count is ALL accumulated vertices
  vertexCount_ = totalSubdivs * 6;

  LOGI("[FlueraVk] Compute dispatch: %d new/%d total subdivs, %d groups, %d verts",
       newSubdivs, totalSubdivs, groups, vertexCount_);
}

void VkStrokeRenderer::destroyComputeResources() {
  if (!device_) return;

  auto destroyBuf = [this](VkBuffer &buf, VkDeviceMemory &mem) {
    if (buf) { vkDestroyBuffer(device_, buf, nullptr); buf = VK_NULL_HANDLE; }
    if (mem) { vkFreeMemory(device_, mem, nullptr); mem = VK_NULL_HANDLE; }
  };

  if (computePipeline_) { vkDestroyPipeline(device_, computePipeline_, nullptr); computePipeline_ = VK_NULL_HANDLE; }
  if (computePipelineLayout_) { vkDestroyPipelineLayout(device_, computePipelineLayout_, nullptr); computePipelineLayout_ = VK_NULL_HANDLE; }
  if (computeDescPool_) { vkDestroyDescriptorPool(device_, computeDescPool_, nullptr); computeDescPool_ = VK_NULL_HANDLE; }
  if (computeDescSetLayout_) { vkDestroyDescriptorSetLayout(device_, computeDescSetLayout_, nullptr); computeDescSetLayout_ = VK_NULL_HANDLE; }

  destroyBuf(pointsSSBO_, pointsSSBOMemory_);
  destroyBuf(computeParamsUBO_, computeParamsMemory_);
  destroyBuf(computeVertexSSBO_, computeVertexSSBOMemory_);
  destroyBuf(computeCapSSBO_, computeCapSSBOMemory_);
  destroyBuf(computeCapCounterSSBO_, computeCapCounterMemory_);

  mappedPointsSSBO_ = nullptr;
  mappedComputeParams_ = nullptr;
  mappedCapCounter_ = nullptr;
  computeAvailable_ = false;
}
