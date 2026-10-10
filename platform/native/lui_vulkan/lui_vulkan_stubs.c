/* The Vulkan backend of Lui: an offscreen GPU renderer producing the
   same pixels as the CPU rasterizer. It mirrors the GL backend's
   architecture — one instanced-quad draw per batch evaluating the same
   signed-distance math in the fragment shader, separable blur passes
   for effect backdrops, premultiplied-alpha blending — over the same
   instance encoding (eleven float4s per instance, from Lui_gpu).

   v1 is deliberately simple: a headless device, one command buffer
   per frame, vkQueueWaitIdle for synchronization, and all images kept
   in VK_IMAGE_LAYOUT_GENERAL (which permits attachment writes,
   sampled reads and transfer copies alike) with coarse memory barriers
   between dependent operations.

   The Vulkan SDK need not be installed to build this: the loader is
   dlopen'ed and the declarations needed are self-contained below, so
   the library builds anywhere, the OCaml layer just reports "no
   Vulkan" at init on machines without it. On non-Linux systems every
   external fails with a message, as the other native backends do. */

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <string.h>

#if defined(__linux__)

#include <stdint.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdio.h>

/* {1 The Vulkan declarations needed} */

typedef uint64_t VkDeviceSize;
typedef uint32_t VkFlags;
typedef uint32_t VkBool32;
typedef uint64_t VkHandle; /* every handle fits in a uint64 on any ABI
                              (dispatchable handles are pointers,
                              non-dispatchable are uint64) */

#define VK_MAKE_API_VERSION(variant, major, minor, patch) \
	((((uint32_t)(variant)) << 29U) | (((uint32_t)(major)) << 22U) | \
	 (((uint32_t)(minor)) << 12U) | ((uint32_t)(patch)))
#define VK_API_VERSION_1_1 VK_MAKE_API_VERSION(0, 1, 1, 0)
#define VK_QUEUE_FAMILY_IGNORED (~0U)
#define VK_SUBPASS_EXTERNAL (~0U)
#define VK_WHOLE_SIZE (~0ULL)
#define VK_NULL_HANDLE ((VkHandle)0)
#define VK_SUCCESS 0

enum {
	ST_APPLICATION_INFO = 0, ST_INSTANCE_CREATE_INFO = 1,
	ST_DEVICE_QUEUE_CREATE_INFO = 2, ST_DEVICE_CREATE_INFO = 3,
	ST_SUBMIT_INFO = 4, ST_MEMORY_ALLOCATE_INFO = 5,
	ST_BUFFER_CREATE_INFO = 12, ST_IMAGE_CREATE_INFO = 14,
	ST_IMAGE_VIEW_CREATE_INFO = 15, ST_SHADER_MODULE_CREATE_INFO = 16,
	ST_PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
	ST_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
	ST_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
	ST_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
	ST_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
	ST_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
	ST_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
	ST_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
	ST_GRAPHICS_PIPELINE_CREATE_INFO = 28,
	ST_PIPELINE_LAYOUT_CREATE_INFO = 30, ST_SAMPLER_CREATE_INFO = 31,
	ST_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
	ST_DESCRIPTOR_POOL_CREATE_INFO = 33,
	ST_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
	ST_WRITE_DESCRIPTOR_SET = 35, ST_FRAMEBUFFER_CREATE_INFO = 37,
	ST_RENDER_PASS_CREATE_INFO = 38, ST_COMMAND_POOL_CREATE_INFO = 39,
	ST_COMMAND_BUFFER_ALLOCATE_INFO = 40,
	ST_COMMAND_BUFFER_BEGIN_INFO = 42, ST_RENDER_PASS_BEGIN_INFO = 43,
	ST_IMAGE_MEMORY_BARRIER = 45, ST_MEMORY_BARRIER = 46
};

enum {
	FMT_R8_UNORM = 9, FMT_R8G8B8A8_UNORM = 37,
	FMT_B8G8R8A8_UNORM = 44, FMT_R32G32B32A32_SFLOAT = 109
};

enum {
	VK_IMAGE_TYPE_2D = 1, VK_IMAGE_VIEW_TYPE_2D = 1,
	VK_IMAGE_TILING_OPTIMAL = 0,
	VK_IMAGE_LAYOUT_UNDEFINED = 0, VK_IMAGE_LAYOUT_GENERAL = 1,
	VK_SAMPLE_COUNT_1_BIT = 1,
	VK_ATTACHMENT_LOAD_OP_LOAD = 0, VK_ATTACHMENT_LOAD_OP_CLEAR = 1,
	VK_ATTACHMENT_STORE_OP_STORE = 0,
	VK_PIPELINE_BIND_POINT_GRAPHICS = 0,
	VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0,
	VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER = 1,
	VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = 4,
	VK_POLYGON_MODE_FILL = 0, VK_CULL_MODE_NONE = 0,
	VK_FRONT_FACE_COUNTER_CLOCKWISE = 0,
	VK_BLEND_FACTOR_ZERO = 0, VK_BLEND_FACTOR_ONE = 1,
	VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA = 7,
	VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR = 16,
	VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA = 18,
	VK_BLEND_OP_ADD = 0,
	VK_DYNAMIC_STATE_VIEWPORT = 0, VK_DYNAMIC_STATE_SCISSOR = 1,
	VK_VERTEX_INPUT_RATE_INSTANCE = 1,
	VK_SHARING_MODE_EXCLUSIVE = 0,
	VK_COMPONENT_SWIZZLE_IDENTITY = 0,
	VK_FILTER_LINEAR = 1,
	VK_SAMPLER_MIPMAP_MODE_NEAREST = 0,
	VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE = 2,
	VK_SHADER_STAGE_VERTEX_BIT = 0x01, VK_SHADER_STAGE_FRAGMENT_BIT = 0x10,
	VK_PHYSICAL_DEVICE_TYPE_CPU = 4,
	VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT = 0x02
};

enum {
	VK_QUEUE_GRAPHICS_BIT = 0x00000001,
	VK_IMAGE_ASPECT_COLOR_BIT = 0x00000001,
	VK_IMAGE_USAGE_TRANSFER_SRC_BIT = 0x00000001,
	VK_IMAGE_USAGE_TRANSFER_DST_BIT = 0x00000002,
	VK_IMAGE_USAGE_SAMPLED_BIT = 0x00000004,
	VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = 0x00000010,
	VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT = 0x00000001,
	VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT = 0x00000002,
	VK_MEMORY_PROPERTY_HOST_COHERENT_BIT = 0x00000004,
	VK_ACCESS_MEMORY_READ_BIT = 0x00008000,
	VK_ACCESS_MEMORY_WRITE_BIT = 0x00010000,
	VK_PIPELINE_STAGE_ALL_COMMANDS_BIT = 0x00010000,
	VK_COLOR_COMPONENT_ALL = 0x0000000f,
	VK_BUFFER_USAGE_TRANSFER_SRC_BIT = 0x00000001,
	VK_BUFFER_USAGE_TRANSFER_DST_BIT = 0x00000002,
	VK_BUFFER_USAGE_VERTEX_BUFFER_BIT = 0x00000080
};

typedef struct { int32_t x, y; } VkOffset2D;
typedef struct { int32_t x, y, z; } VkOffset3D;
typedef struct { uint32_t width, height; } VkExtent2D;
typedef struct { uint32_t width, height, depth; } VkExtent3D;
typedef struct { VkOffset2D offset; VkExtent2D extent; } VkRect2D;
typedef struct {
	uint32_t aspectMask, baseMipLevel, levelCount, baseArrayLayer,
	    layerCount;
} VkImageSubresourceRange;
typedef struct {
	uint32_t aspectMask, mipLevel, baseArrayLayer, layerCount;
} VkImageSubresourceLayers;
typedef struct {
	uint32_t r, g, b, a;
} VkComponentMapping;
typedef struct {
	float x, y, width, height, minDepth, maxDepth;
} VkViewport;
typedef union { float color[4]; float depthStencil[2]; } VkClearValue;
typedef struct { VkFlags propertyFlags; uint32_t heapIndex; } VkMemoryType;
typedef struct { VkDeviceSize size; VkFlags flags; } VkMemoryHeap;
typedef struct {
	uint32_t memoryTypeCount;
	VkMemoryType memoryTypes[32];
	uint32_t memoryHeapCount;
	VkMemoryHeap memoryHeaps[16];
} VkPhysicalDeviceMemoryProperties;
typedef struct {
	uint32_t queueFlags, queueCount, timestampValidBits;
	VkExtent3D minImageTransferGranularity;
} VkQueueFamilyProperties;
typedef struct {
	VkFlags sType;
	const void *pNext;
	const char *pApplicationName;
	uint32_t applicationVersion;
	const char *pEngineName;
	uint32_t engineVersion;
	uint32_t apiVersion;
} VkApplicationInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	const VkApplicationInfo *pApplicationInfo;
	uint32_t enabledLayerCount;
	const char *const *ppEnabledLayerNames;
	uint32_t enabledExtensionCount;
	const char *const *ppEnabledExtensionNames;
} VkInstanceCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t queueFamilyIndex, queueCount;
	const float *pQueuePriorities;
} VkDeviceQueueCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t queueCreateInfoCount;
	const VkDeviceQueueCreateInfo *pQueueCreateInfos;
	uint32_t enabledLayerCount;
	const char *const *ppEnabledLayerNames;
	uint32_t enabledExtensionCount;
	const char *const *ppEnabledExtensionNames;
	const void *pEnabledFeatures;
} VkDeviceCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t queueFamilyIndex;
} VkCommandPoolCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkHandle commandPool;
	uint32_t level, commandBufferCount;
} VkCommandBufferAllocateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	const void *pInheritanceInfo;
} VkCommandBufferBeginInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkHandle renderPass, framebuffer;
	VkRect2D renderArea;
	uint32_t clearValueCount;
	const VkClearValue *pClearValues;
} VkRenderPassBeginInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	VkDeviceSize size;
	uint32_t usage, sharingMode, queueFamilyIndexCount;
	const uint32_t *pQueueFamilyIndices;
} VkBufferCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t imageType, format;
	VkExtent3D extent;
	uint32_t mipLevels, arrayLayers, samples, tiling, usage, sharingMode,
	    queueFamilyIndexCount;
	const uint32_t *pQueueFamilyIndices;
	uint32_t initialLayout;
} VkImageCreateInfo;
typedef struct {
	VkDeviceSize size, alignment;
	uint32_t memoryTypeBits;
} VkMemoryRequirements;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkDeviceSize allocationSize;
	uint32_t memoryTypeIndex;
} VkMemoryAllocateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	VkHandle image;
	uint32_t viewType, format;
	VkComponentMapping components;
	VkImageSubresourceRange subresourceRange;
} VkImageViewCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t magFilter, minFilter, mipmapMode, addressModeU, addressModeV,
	    addressModeW;
	float mipLodBias;
	uint32_t anisotropyEnable;
	float maxAnisotropy;
	uint32_t compareEnable, compareOp;
	float minLod, maxLod;
	uint32_t borderColor, unnormalizedCoordinates;
} VkSamplerCreateInfo;
typedef struct {
	uint32_t binding, descriptorType, descriptorCount, stageFlags;
	const VkHandle *pImmutableSamplers;
} VkDescriptorSetLayoutBinding;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t bindingCount;
	const VkDescriptorSetLayoutBinding *pBindings;
} VkDescriptorSetLayoutCreateInfo;
typedef struct { uint32_t type, descriptorCount; } VkDescriptorPoolSize;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t maxSets, poolSizeCount;
	const VkDescriptorPoolSize *pPoolSizes;
} VkDescriptorPoolCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkHandle descriptorPool;
	uint32_t descriptorSetCount;
	const VkHandle *pSetLayouts;
} VkDescriptorSetAllocateInfo;
typedef struct {
	VkHandle sampler, imageView;
	uint32_t imageLayout;
} VkDescriptorImageInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkHandle dstSet;
	uint32_t dstBinding, dstArrayElement, descriptorCount, descriptorType;
	const VkDescriptorImageInfo *pImageInfo;
	const void *pBufferInfo;
	const void *pTexelBufferView;
} VkWriteDescriptorSet;
typedef struct {
	uint32_t stageFlags, offset, size;
} VkPushConstantRange;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t setLayoutCount;
	const VkHandle *pSetLayouts;
	uint32_t pushConstantRangeCount;
	const VkPushConstantRange *pPushConstantRanges;
} VkPipelineLayoutCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	size_t codeSize;
	const uint32_t *pCode;
} VkShaderModuleCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t stage;
	VkHandle module;
	const char *pName;
	const void *pSpecializationInfo;
} VkPipelineShaderStageCreateInfo;
typedef struct {
	uint32_t binding, stride, inputRate;
} VkVertexInputBindingDescription;
typedef struct {
	uint32_t location, binding, format, offset;
} VkVertexInputAttributeDescription;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t vertexBindingDescriptionCount;
	const VkVertexInputBindingDescription *pVertexBindingDescriptions;
	uint32_t vertexAttributeDescriptionCount;
	const VkVertexInputAttributeDescription *pVertexAttributeDescriptions;
} VkPipelineVertexInputStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t topology, primitiveRestartEnable;
} VkPipelineInputAssemblyStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t viewportCount;
	const VkViewport *pViewports;
	uint32_t scissorCount;
	const VkRect2D *pScissors;
} VkPipelineViewportStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t depthClampEnable, rasterizerDiscardEnable, polygonMode,
	    cullMode, frontFace, depthBiasEnable;
	float depthBiasConstantFactor, depthBiasClamp, depthBiasSlopeFactor,
	    lineWidth;
} VkPipelineRasterizationStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t rasterizationSamples, sampleShadingEnable;
	float minSampleShading;
	const void *pSampleMask;
	uint32_t alphaToCoverageEnable, alphaToOneEnable;
} VkPipelineMultisampleStateCreateInfo;
typedef struct {
	uint32_t blendEnable;
	uint32_t srcColorBlendFactor, dstColorBlendFactor, colorBlendOp;
	uint32_t srcAlphaBlendFactor, dstAlphaBlendFactor, alphaBlendOp;
	uint32_t colorWriteMask;
} VkPipelineColorBlendAttachmentState;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t logicOpEnable, logicOp, attachmentCount;
	const VkPipelineColorBlendAttachmentState *pAttachments;
	float blendConstants[4];
} VkPipelineColorBlendStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t dynamicStateCount;
	const uint32_t *pDynamicStates;
} VkPipelineDynamicStateCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t stageCount;
	const VkPipelineShaderStageCreateInfo *pStages;
	const void *pVertexInputState, *pInputAssemblyState,
	    *pTessellationState, *pViewportState, *pRasterizationState,
	    *pMultisampleState, *pDepthStencilState, *pColorBlendState,
	    *pDynamicState;
	VkHandle layout, renderPass;
	uint32_t subpass;
	VkHandle basePipelineHandle;
	int32_t basePipelineIndex;
} VkGraphicsPipelineCreateInfo;
typedef struct {
	VkFlags flags;
	uint32_t format, samples, loadOp, storeOp, stencilLoadOp,
	    stencilStoreOp, initialLayout, finalLayout;
} VkAttachmentDescription;
typedef struct { uint32_t attachment, layout; } VkAttachmentReference;
typedef struct {
	VkFlags flags;
	uint32_t pipelineBindPoint, inputAttachmentCount;
	const VkAttachmentReference *pInputAttachments;
	uint32_t colorAttachmentCount;
	const VkAttachmentReference *pColorAttachments,
	    *pResolveAttachments, *pDepthStencilAttachment;
	uint32_t preserveAttachmentCount;
	const uint32_t *pPreserveAttachments;
} VkSubpassDescription;
typedef struct {
	uint32_t srcSubpass, dstSubpass, srcStageMask, dstStageMask,
	    srcAccessMask, dstAccessMask, dependencyFlags;
} VkSubpassDependency;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	uint32_t attachmentCount;
	const VkAttachmentDescription *pAttachments;
	uint32_t subpassCount;
	const VkSubpassDescription *pSubpasses;
	uint32_t dependencyCount;
	const VkSubpassDependency *pDependencies;
} VkRenderPassCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	VkFlags flags;
	VkHandle renderPass;
	uint32_t attachmentCount;
	const VkHandle *pAttachments;
	uint32_t width, height, layers;
} VkFramebufferCreateInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	uint32_t waitSemaphoreCount;
	const VkHandle *pWaitSemaphores;
	const uint32_t *pWaitDstStageMask;
	uint32_t commandBufferCount;
	const VkHandle *pCommandBuffers;
	uint32_t signalSemaphoreCount;
	const VkHandle *pSignalSemaphores;
} VkSubmitInfo;
typedef struct {
	uint32_t sType;
	const void *pNext;
	uint32_t srcAccessMask, dstAccessMask;
} VkMemoryBarrier;
typedef struct {
	uint32_t sType;
	const void *pNext;
	uint32_t srcAccessMask, dstAccessMask, oldLayout, newLayout,
	    srcQueueFamilyIndex, dstQueueFamilyIndex;
	VkHandle image;
	VkImageSubresourceRange subresourceRange;
} VkImageMemoryBarrier;
typedef struct {
	VkDeviceSize bufferOffset;
	uint32_t bufferRowLength, bufferImageHeight;
	VkImageSubresourceLayers imageSubresource;
	VkOffset3D imageOffset;
	VkExtent3D imageExtent;
} VkBufferImageCopy;
typedef struct {
	VkImageSubresourceLayers srcSubresource;
	VkOffset3D srcOffset;
	VkImageSubresourceLayers dstSubresource;
	VkOffset3D dstOffset;
	VkExtent3D extent;
} VkImageCopy;

/* The function pointers used, resolved from libvulkan.so.1 at init. */
typedef struct {
	VkHandle (*GetInstanceProcAddr)(VkHandle, const char *);
	int32_t (*CreateInstance)(const VkInstanceCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroyInstance)(VkHandle, const void *);
	int32_t (*EnumeratePhysicalDevices)(VkHandle, uint32_t *, VkHandle *);
	void (*GetPhysicalDeviceProperties)(VkHandle, void *);
	void (*GetPhysicalDeviceFeatures)(VkHandle, void *);
	void (*GetPhysicalDeviceMemoryProperties)(VkHandle,
	    VkPhysicalDeviceMemoryProperties *);
	void (*GetPhysicalDeviceQueueFamilyProperties)(VkHandle, uint32_t *,
	    VkQueueFamilyProperties *);
	int32_t (*CreateDevice)(VkHandle, const VkDeviceCreateInfo *,
	    const void *, VkHandle *);
	VkHandle (*GetDeviceProcAddr)(VkHandle, const char *);
	void (*DestroyDevice)(VkHandle, const void *);
	void (*GetDeviceQueue)(VkHandle, uint32_t, uint32_t, VkHandle *);
	int32_t (*DeviceWaitIdle)(VkHandle);
	int32_t (*QueueWaitIdle)(VkHandle);
	int32_t (*CreateCommandPool)(VkHandle,
	    const VkCommandPoolCreateInfo *, const void *, VkHandle *);
	void (*DestroyCommandPool)(VkHandle, VkHandle, const void *);
	int32_t (*AllocateCommandBuffers)(VkHandle,
	    const VkCommandBufferAllocateInfo *, VkHandle *);
	int32_t (*BeginCommandBuffer)(VkHandle,
	    const VkCommandBufferBeginInfo *);
	int32_t (*EndCommandBuffer)(VkHandle);
	int32_t (*ResetCommandBuffer)(VkHandle, VkFlags);
	int32_t (*CreateBuffer)(VkHandle, const VkBufferCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroyBuffer)(VkHandle, VkHandle, const void *);
	void (*GetBufferMemoryRequirements)(VkHandle, VkHandle,
	    VkMemoryRequirements *);
	int32_t (*CreateImage)(VkHandle, const VkImageCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroyImage)(VkHandle, VkHandle, const void *);
	void (*GetImageMemoryRequirements)(VkHandle, VkHandle,
	    VkMemoryRequirements *);
	int32_t (*AllocateMemory)(VkHandle, const VkMemoryAllocateInfo *,
	    const void *, VkHandle *);
	void (*FreeMemory)(VkHandle, VkHandle, const void *);
	int32_t (*BindBufferMemory)(VkHandle, VkHandle, VkHandle,
	    VkDeviceSize);
	int32_t (*BindImageMemory)(VkHandle, VkHandle, VkHandle,
	    VkDeviceSize);
	int32_t (*MapMemory)(VkHandle, VkHandle, VkDeviceSize, VkDeviceSize,
	    VkFlags, void **);
	void (*UnmapMemory)(VkHandle, VkHandle);
	int32_t (*CreateImageView)(VkHandle, const VkImageViewCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroyImageView)(VkHandle, VkHandle, const void *);
	int32_t (*CreateSampler)(VkHandle, const VkSamplerCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroySampler)(VkHandle, VkHandle, const void *);
	int32_t (*CreateDescriptorSetLayout)(VkHandle,
	    const VkDescriptorSetLayoutCreateInfo *, const void *,
	    VkHandle *);
	void (*DestroyDescriptorSetLayout)(VkHandle, VkHandle, const void *);
	int32_t (*CreateDescriptorPool)(VkHandle,
	    const VkDescriptorPoolCreateInfo *, const void *, VkHandle *);
	void (*DestroyDescriptorPool)(VkHandle, VkHandle, const void *);
	int32_t (*AllocateDescriptorSets)(VkHandle,
	    const VkDescriptorSetAllocateInfo *, VkHandle *);
	void (*UpdateDescriptorSets)(VkHandle, uint32_t,
	    const VkWriteDescriptorSet *, uint32_t, const void *);
	int32_t (*CreatePipelineLayout)(VkHandle,
	    const VkPipelineLayoutCreateInfo *, const void *, VkHandle *);
	void (*DestroyPipelineLayout)(VkHandle, VkHandle, const void *);
	int32_t (*CreateShaderModule)(VkHandle,
	    const VkShaderModuleCreateInfo *, const void *, VkHandle *);
	void (*DestroyShaderModule)(VkHandle, VkHandle, const void *);
	int32_t (*CreateGraphicsPipelines)(VkHandle, VkHandle, uint32_t,
	    const VkGraphicsPipelineCreateInfo *, const void *, VkHandle *);
	void (*DestroyPipeline)(VkHandle, VkHandle, const void *);
	int32_t (*CreateRenderPass)(VkHandle, const VkRenderPassCreateInfo *,
	    const void *, VkHandle *);
	void (*DestroyRenderPass)(VkHandle, VkHandle, const void *);
	int32_t (*CreateFramebuffer)(VkHandle,
	    const VkFramebufferCreateInfo *, const void *, VkHandle *);
	void (*DestroyFramebuffer)(VkHandle, VkHandle, const void *);
	void (*CmdBeginRenderPass)(VkHandle, const VkRenderPassBeginInfo *,
	    uint32_t);
	void (*CmdEndRenderPass)(VkHandle);
	void (*CmdBindPipeline)(VkHandle, uint32_t, VkHandle);
	void (*CmdBindVertexBuffers)(VkHandle, uint32_t, uint32_t,
	    const VkHandle *, const VkDeviceSize *);
	void (*CmdBindDescriptorSets)(VkHandle, uint32_t, VkHandle, uint32_t,
	    uint32_t, const VkHandle *, uint32_t, const uint32_t *);
	void (*CmdSetViewport)(VkHandle, uint32_t, uint32_t,
	    const VkViewport *);
	void (*CmdSetScissor)(VkHandle, uint32_t, uint32_t, const VkRect2D *);
	void (*CmdPushConstants)(VkHandle, VkHandle, uint32_t, uint32_t,
	    uint32_t, const void *);
	void (*CmdDraw)(VkHandle, uint32_t, uint32_t, uint32_t, uint32_t);
	void (*CmdPipelineBarrier)(VkHandle, uint32_t, uint32_t, VkFlags,
	    uint32_t, const VkMemoryBarrier *, uint32_t, const void *,
	    uint32_t, const VkImageMemoryBarrier *);
	void (*CmdCopyImage)(VkHandle, VkHandle, uint32_t, VkHandle,
	    uint32_t, uint32_t, const VkImageCopy *);
	void (*CmdCopyBufferToImage)(VkHandle, VkHandle, VkHandle, uint32_t,
	    uint32_t, const VkBufferImageCopy *);
	void (*CmdCopyImageToBuffer)(VkHandle, VkHandle, uint32_t, VkHandle,
	    uint32_t, const VkBufferImageCopy *);
	int32_t (*QueueSubmit)(VkHandle, uint32_t, const VkSubmitInfo *,
	    VkHandle);
} VkFns;

/* {1 The renderer} */

typedef struct {
	VkHandle img, mem, view, ds, dsp, fb;
	int w, h, fmt;
} Tex;

typedef struct {
	void *lib;
	VkFns vk;
	VkHandle inst, pdev, dev, queue, pool, cmd;
	uint32_t qfam;
	int w, h, dual, max_size;
	uint32_t mem_dev, mem_host;
	VkHandle frame_img, frame_mem, frame_view, frame_fb;
	VkHandle rp_clear, rp_load;
	VkHandle dsl0, dsl1, dslp, pl_main, pl_pass;
	VkHandle dpool, ds0, ds_backdrop, sampler;
	VkHandle vb, vb_mem;
	void *vb_map;
	VkDeviceSize vb_cap;
	VkHandle stg, stg_mem;
	void *stg_map;
	VkDeviceSize stg_cap, stg_used;
	VkHandle rb, rb_mem;
	void *rb_map;
	VkDeviceSize rb_cap;
	Tex *texs;
	int ntexs, texs_cap;
	VkHandle *pipes;
	int npipes, pipes_cap;
	int rp_open, recording;
	char driver[256];
	char err[512];
} Ctx;


static int fail(Ctx *c, const char *what, int res)
{
	snprintf(c->err, sizeof c->err, "%s failed: VkResult %d", what, res);
	return -1;
}

static int mem_type(Ctx *c, uint32_t bits, uint32_t want, uint32_t *out)
{
	VkPhysicalDeviceMemoryProperties mp;
	uint32_t i;
	memset(&mp, 0, sizeof mp);
	c->vk.GetPhysicalDeviceMemoryProperties(c->pdev, &mp);
	for (i = 0; i < mp.memoryTypeCount; i++)
		if ((bits & (1u << i)) &&
		    (mp.memoryTypes[i].propertyFlags & want) == want) {
			*out = i;
			return 0;
		}
	return -1;
}

static int make_buffer(Ctx *c, VkDeviceSize size, uint32_t usage,
    uint32_t mem_props, VkHandle *buf, VkHandle *mem, void **map)
{
	VkBufferCreateInfo bi;
	VkMemoryRequirements req;
	VkMemoryAllocateInfo ai;
	uint32_t mt;
	memset(&bi, 0, sizeof bi);
	bi.sType = ST_BUFFER_CREATE_INFO;
	bi.size = size;
	bi.usage = usage;
	bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	if (c->vk.CreateBuffer(c->dev, &bi, NULL, buf))
		return fail(c, "vkCreateBuffer", -1);
	c->vk.GetBufferMemoryRequirements(c->dev, *buf, &req);
	if (mem_type(c, req.memoryTypeBits, mem_props, &mt) < 0 &&
	    mem_type(c, req.memoryTypeBits,
		VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
		VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &mt) < 0)
		return fail(c, "no suitable memory type", -1);
	memset(&ai, 0, sizeof ai);
	ai.sType = ST_MEMORY_ALLOCATE_INFO;
	ai.allocationSize = req.size;
	ai.memoryTypeIndex = mt;
	if (c->vk.AllocateMemory(c->dev, &ai, NULL, mem))
		return fail(c, "vkAllocateMemory", -1);
	if (c->vk.BindBufferMemory(c->dev, *buf, *mem, 0))
		return fail(c, "vkBindBufferMemory", -1);
	if (map && c->vk.MapMemory(c->dev, *mem, 0, size, 0, map))
		return fail(c, "vkMapMemory", -1);
	return 0;
}

/* A barrier ordering every prior write before every later access: all
   images stay in VK_IMAGE_LAYOUT_GENERAL, so ordering, not layout, is
   all that must be sequenced. */
static void barrier(Ctx *c)
{
	VkMemoryBarrier b;
	memset(&b, 0, sizeof b);
	b.sType = ST_MEMORY_BARRIER;
	b.srcAccessMask = VK_ACCESS_MEMORY_WRITE_BIT;
	b.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT |
	    VK_ACCESS_MEMORY_WRITE_BIT;
	c->vk.CmdPipelineBarrier(c->cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
	    VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 1, &b, 0, NULL, 0, NULL);
}

/* Transition a fresh image from UNDEFINED to GENERAL in the current
   command buffer. */
static void to_general(Ctx *c, VkHandle img)
{
	VkImageMemoryBarrier b;
	memset(&b, 0, sizeof b);
	b.sType = ST_IMAGE_MEMORY_BARRIER;
	b.dstAccessMask = VK_ACCESS_MEMORY_WRITE_BIT;
	b.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	b.newLayout = VK_IMAGE_LAYOUT_GENERAL;
	b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	b.image = img;
	b.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	b.subresourceRange.levelCount = 1;
	b.subresourceRange.layerCount = 1;
	c->vk.CmdPipelineBarrier(c->cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
	    VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, NULL, 0, NULL, 1, &b);
}

/* Submit the work recorded so far in a throwaway command buffer and
   wait for it: used at init, before the frame command buffer exists. */
static int submit_and_wait(Ctx *c, VkHandle cb)
{
	VkSubmitInfo si;
	memset(&si, 0, sizeof si);
	si.sType = ST_SUBMIT_INFO;
	si.commandBufferCount = 1;
	si.pCommandBuffers = &cb;
	if (c->vk.QueueSubmit(c->queue, 1, &si, VK_NULL_HANDLE))
		return fail(c, "vkQueueSubmit", -1);
	if (c->vk.QueueWaitIdle(c->queue))
		return fail(c, "vkQueueWaitIdle", -1);
	return 0;
}

static int make_render_pass(Ctx *c, uint32_t load_op, VkHandle *out)
{
	VkAttachmentDescription att;
	VkAttachmentReference ref;
	VkSubpassDescription sub;
	VkSubpassDependency dep;
	VkRenderPassCreateInfo ri;
	memset(&att, 0, sizeof att);
	att.format = FMT_B8G8R8A8_UNORM;
	att.samples = VK_SAMPLE_COUNT_1_BIT;
	att.loadOp = load_op;
	att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
	att.stencilLoadOp = 2; /* DONT_CARE */
	att.stencilStoreOp = 1; /* DONT_CARE */
	att.initialLayout = VK_IMAGE_LAYOUT_GENERAL;
	att.finalLayout = VK_IMAGE_LAYOUT_GENERAL;
	ref.attachment = 0;
	ref.layout = VK_IMAGE_LAYOUT_GENERAL;
	memset(&sub, 0, sizeof sub);
	sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
	sub.colorAttachmentCount = 1;
	sub.pColorAttachments = &ref;
	memset(&dep, 0, sizeof dep);
	dep.srcSubpass = VK_SUBPASS_EXTERNAL;
	dep.dstSubpass = 0;
	dep.srcStageMask = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
	dep.dstStageMask = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
	dep.srcAccessMask = VK_ACCESS_MEMORY_WRITE_BIT;
	dep.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT |
	    VK_ACCESS_MEMORY_WRITE_BIT;
	memset(&ri, 0, sizeof ri);
	ri.sType = ST_RENDER_PASS_CREATE_INFO;
	ri.attachmentCount = 1;
	ri.pAttachments = &att;
	ri.subpassCount = 1;
	ri.pSubpasses = &sub;
	ri.dependencyCount = 1;
	ri.pDependencies = &dep;
	if (c->vk.CreateRenderPass(c->dev, &ri, NULL, out))
		return fail(c, "vkCreateRenderPass", -1);
	return 0;
}

static VkHandle make_image(Ctx *c, int w, int h, uint32_t fmt,
    uint32_t usage)
{
	VkImageCreateInfo ii;
	VkHandle img;
	memset(&ii, 0, sizeof ii);
	ii.sType = ST_IMAGE_CREATE_INFO;
	ii.imageType = VK_IMAGE_TYPE_2D;
	ii.format = fmt;
	ii.extent.width = (uint32_t)w;
	ii.extent.height = (uint32_t)h;
	ii.extent.depth = 1;
	ii.mipLevels = 1;
	ii.arrayLayers = 1;
	ii.samples = VK_SAMPLE_COUNT_1_BIT;
	ii.tiling = VK_IMAGE_TILING_OPTIMAL;
	ii.usage = usage;
	ii.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	if (c->vk.CreateImage(c->dev, &ii, NULL, &img))
		return VK_NULL_HANDLE;
	return img;
}

static int image_mem(Ctx *c, VkHandle img, VkHandle *mem)
{
	VkMemoryRequirements req;
	VkMemoryAllocateInfo ai;
	uint32_t mt;
	c->vk.GetImageMemoryRequirements(c->dev, img, &req);
	if (mem_type(c, req.memoryTypeBits,
		VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &mt) < 0 &&
	    mem_type(c, req.memoryTypeBits, 0, &mt) < 0)
		return fail(c, "no suitable memory type", -1);
	memset(&ai, 0, sizeof ai);
	ai.sType = ST_MEMORY_ALLOCATE_INFO;
	ai.allocationSize = req.size;
	ai.memoryTypeIndex = mt;
	if (c->vk.AllocateMemory(c->dev, &ai, NULL, mem))
		return fail(c, "vkAllocateMemory", -1);
	if (c->vk.BindImageMemory(c->dev, img, *mem, 0))
		return fail(c, "vkBindImageMemory", -1);
	return 0;
}

static VkHandle make_view(Ctx *c, VkHandle img, uint32_t fmt)
{
	VkImageViewCreateInfo vi;
	VkHandle view;
	memset(&vi, 0, sizeof vi);
	vi.sType = ST_IMAGE_VIEW_CREATE_INFO;
	vi.image = img;
	vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
	vi.format = fmt;
	vi.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	vi.subresourceRange.levelCount = 1;
	vi.subresourceRange.layerCount = 1;
	if (c->vk.CreateImageView(c->dev, &vi, NULL, &view))
		return VK_NULL_HANDLE;
	return view;
}

static VkHandle make_fb(Ctx *c, VkHandle view, int w, int h)
{
	VkFramebufferCreateInfo fi;
	VkHandle fb;
	memset(&fi, 0, sizeof fi);
	fi.sType = ST_FRAMEBUFFER_CREATE_INFO;
	fi.renderPass = c->rp_load;
	fi.attachmentCount = 1;
	fi.pAttachments = &view;
	fi.width = (uint32_t)w;
	fi.height = (uint32_t)h;
	fi.layers = 1;
	if (c->vk.CreateFramebuffer(c->dev, &fi, NULL, &fb))
		return VK_NULL_HANDLE;
	return fb;
}

static int alloc_sets(Ctx *c, const VkHandle *layouts, int n, VkHandle *out)
{
	VkDescriptorSetAllocateInfo ai;
	memset(&ai, 0, sizeof ai);
	ai.sType = ST_DESCRIPTOR_SET_ALLOCATE_INFO;
	ai.descriptorPool = c->dpool;
	ai.descriptorSetCount = (uint32_t)n;
	ai.pSetLayouts = layouts;
	if (c->vk.AllocateDescriptorSets(c->dev, &ai, out))
		return fail(c, "vkAllocateDescriptorSets", -1);
	return 0;
}

/* Write the sampler+view pair of binding into set. */
static void set_image(Ctx *c, VkHandle set, int binding, VkHandle view)
{
	VkDescriptorImageInfo ii;
	VkWriteDescriptorSet w;
	ii.sampler = c->sampler;
	ii.imageView = view;
	ii.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
	memset(&w, 0, sizeof w);
	w.sType = ST_WRITE_DESCRIPTOR_SET;
	w.dstSet = set;
	w.dstBinding = (uint32_t)binding;
	w.descriptorCount = 1;
	w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	w.pImageInfo = &ii;
	c->vk.UpdateDescriptorSets(c->dev, 1, &w, 0, NULL);
}

static int tex_at(Ctx *c, int id, Tex **out)
{
	if (id < 0 || id >= c->ntexs || !c->texs[id].img)
		return fail(c, "bad texture id", -1);
	*out = &c->texs[id];
	return 0;
}

static int tex_create(Ctx *c, int w, int h, uint32_t fmt)
{
	Tex *t;
	int id;
	uint32_t usage = VK_IMAGE_USAGE_SAMPLED_BIT |
	    VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
	    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
	if (c->ntexs == c->texs_cap) {
		int cap = c->texs_cap ? c->texs_cap * 2 : 16;
		Tex *nt = realloc(c->texs, sizeof(Tex) * cap);
		if (!nt)
			return fail(c, "out of memory", -1);
		c->texs = nt;
		c->texs_cap = cap;
	}
	id = c->ntexs++;
	t = &c->texs[id];
	memset(t, 0, sizeof *t);
	t->w = w;
	t->h = h;
	t->fmt = (int)fmt;
	t->img = make_image(c, w, h, fmt, usage);
	if (!t->img || image_mem(c, t->img, &t->mem) < 0)
		return fail(c, "texture image", -1);
	t->view = make_view(c, t->img, fmt);
	if (!t->view || !(t->fb = make_fb(c, t->view, w, h)))
		return fail(c, "texture view/fb", -1);
	{ VkHandle l[2] = { c->dsl1, c->dslp };
	  VkHandle s[2];
	  if (alloc_sets(c, l, 2, s) < 0)
		return fail(c, "texture descriptors", -1);
	  t->ds = s[0];
	  t->dsp = s[1]; }
	set_image(c, t->ds, 0, t->view);
	set_image(c, t->ds, 1, c->texs[0].view); /* empty backdrop */
	set_image(c, t->dsp, 0, t->view);
	if (c->recording)
		to_general(c, t->img);
	return id;
}

static void tex_destroy(Ctx *c, Tex *t)
{
	if (t->fb)
		c->vk.DestroyFramebuffer(c->dev, t->fb, NULL);
	if (t->view)
		c->vk.DestroyImageView(c->dev, t->view, NULL);
	if (t->img)
		c->vk.DestroyImage(c->dev, t->img, NULL);
	if (t->mem)
		c->vk.FreeMemory(c->dev, t->mem, NULL);
	memset(t, 0, sizeof *t);
}

static int ensure_staging(Ctx *c, VkDeviceSize need)
{
	if (need <= c->stg_cap)
		return 0;
	VkDeviceSize cap = c->stg_cap ? c->stg_cap * 2 : (1 << 20);
	while (cap < need)
		cap *= 2;
	if (c->stg) {
		c->vk.DestroyBuffer(c->dev, c->stg, NULL);
		c->vk.FreeMemory(c->dev, c->stg_mem, NULL);
		c->stg = VK_NULL_HANDLE;
	}
	if (make_buffer(c, cap, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
		VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
		VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &c->stg, &c->stg_mem,
		&c->stg_map) < 0)
		return -1;
	c->stg_cap = cap;
	return 0;
}

static int ensure_vb(Ctx *c, VkDeviceSize need)
{
	if (need <= c->vb_cap)
		return 0;
	VkDeviceSize cap = c->vb_cap ? c->vb_cap * 2 : (1 << 20);
	while (cap < need)
		cap *= 2;
	if (c->vb) {
		c->vk.DestroyBuffer(c->dev, c->vb, NULL);
		c->vk.FreeMemory(c->dev, c->vb_mem, NULL);
		c->vb = VK_NULL_HANDLE;
	}
	if (make_buffer(c, cap, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
		VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
		VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &c->vb, &c->vb_mem,
		&c->vb_map) < 0)
		return -1;
	c->vb_cap = cap;
	return 0;
}

static void destroy_ctx(Ctx *c)
{
	int i;
	if (!c)
		return;
	if (c->dev) {
		c->vk.DeviceWaitIdle(c->dev);
		for (i = 0; i < c->ntexs; i++)
			tex_destroy(c, &c->texs[i]);
		for (i = 0; i < c->npipes; i++)
			if (c->pipes[i])
				c->vk.DestroyPipeline(c->dev, c->pipes[i],
				    NULL);
		if (c->vb)
			c->vk.DestroyBuffer(c->dev, c->vb, NULL);
		if (c->vb_mem)
			c->vk.FreeMemory(c->dev, c->vb_mem, NULL);
		if (c->stg)
			c->vk.DestroyBuffer(c->dev, c->stg, NULL);
		if (c->stg_mem)
			c->vk.FreeMemory(c->dev, c->stg_mem, NULL);
		if (c->rb)
			c->vk.DestroyBuffer(c->dev, c->rb, NULL);
		if (c->rb_mem)
			c->vk.FreeMemory(c->dev, c->rb_mem, NULL);
		if (c->frame_fb)
			c->vk.DestroyFramebuffer(c->dev, c->frame_fb, NULL);
		if (c->frame_view)
			c->vk.DestroyImageView(c->dev, c->frame_view, NULL);
		if (c->frame_img)
			c->vk.DestroyImage(c->dev, c->frame_img, NULL);
		if (c->frame_mem)
			c->vk.FreeMemory(c->dev, c->frame_mem, NULL);
		if (c->rp_clear)
			c->vk.DestroyRenderPass(c->dev, c->rp_clear, NULL);
		if (c->rp_load)
			c->vk.DestroyRenderPass(c->dev, c->rp_load, NULL);
		if (c->pl_main)
			c->vk.DestroyPipelineLayout(c->dev, c->pl_main, NULL);
		if (c->pl_pass)
			c->vk.DestroyPipelineLayout(c->dev, c->pl_pass, NULL);
		if (c->dsl0)
			c->vk.DestroyDescriptorSetLayout(c->dev, c->dsl0,
			    NULL);
		if (c->dsl1)
			c->vk.DestroyDescriptorSetLayout(c->dev, c->dsl1,
			    NULL);
		if (c->dslp)
			c->vk.DestroyDescriptorSetLayout(c->dev, c->dslp,
			    NULL);
		if (c->dpool)
			c->vk.DestroyDescriptorPool(c->dev, c->dpool, NULL);
		if (c->sampler)
			c->vk.DestroySampler(c->dev, c->sampler, NULL);
		if (c->pool)
			c->vk.DestroyCommandPool(c->dev, c->pool, NULL);
		if (c->vk.DestroyDevice)
			c->vk.DestroyDevice(c->dev, NULL);
	}
	if (c->inst && c->vk.DestroyInstance)
		c->vk.DestroyInstance(c->inst, NULL);
	if (c->lib)
		dlclose(c->lib);
	free(c->texs);
	free(c->pipes);
	free(c);
}

/* {1 Context creation} */

static int create_ctx(Ctx *c, int w, int h)
{
	const char *names[] = {
		"EnumeratePhysicalDevices",
		"GetPhysicalDeviceProperties",
		"GetPhysicalDeviceFeatures",
		"GetPhysicalDeviceMemoryProperties",
		"GetPhysicalDeviceQueueFamilyProperties",
		"CreateDevice", "GetDeviceProcAddr", "DestroyDevice",
		"GetDeviceQueue", "DeviceWaitIdle", "QueueWaitIdle",
		"CreateCommandPool", "DestroyCommandPool",
		"AllocateCommandBuffers", "BeginCommandBuffer",
		"EndCommandBuffer", "ResetCommandBuffer", "CreateBuffer",
		"DestroyBuffer", "GetBufferMemoryRequirements", "CreateImage",
		"DestroyImage", "GetImageMemoryRequirements", "AllocateMemory",
		"FreeMemory", "BindBufferMemory", "BindImageMemory",
		"MapMemory", "UnmapMemory", "CreateImageView",
		"DestroyImageView", "CreateSampler", "DestroySampler",
		"CreateDescriptorSetLayout", "DestroyDescriptorSetLayout",
		"CreateDescriptorPool", "DestroyDescriptorPool",
		"AllocateDescriptorSets", "UpdateDescriptorSets",
		"CreatePipelineLayout", "DestroyPipelineLayout",
		"CreateShaderModule", "DestroyShaderModule",
		"CreateGraphicsPipelines", "DestroyPipeline",
		"CreateRenderPass", "DestroyRenderPass", "CreateFramebuffer",
		"DestroyFramebuffer", "CmdBeginRenderPass", "CmdEndRenderPass",
		"CmdBindPipeline", "CmdBindVertexBuffers",
		"CmdBindDescriptorSets", "CmdSetViewport", "CmdSetScissor",
		"CmdPushConstants", "CmdDraw", "CmdPipelineBarrier",
		"CmdCopyImage", "CmdCopyBufferToImage", "CmdCopyImageToBuffer",
		"QueueSubmit", "DestroyInstance"
	};
	VkHandle *slots[] = {
		(VkHandle *)&c->vk.EnumeratePhysicalDevices,
		(VkHandle *)&c->vk.GetPhysicalDeviceProperties,
		(VkHandle *)&c->vk.GetPhysicalDeviceFeatures,
		(VkHandle *)&c->vk.GetPhysicalDeviceMemoryProperties,
		(VkHandle *)&c->vk.GetPhysicalDeviceQueueFamilyProperties,
		(VkHandle *)&c->vk.CreateDevice,
		(VkHandle *)&c->vk.GetDeviceProcAddr,
		(VkHandle *)&c->vk.DestroyDevice,
		(VkHandle *)&c->vk.GetDeviceQueue,
		(VkHandle *)&c->vk.DeviceWaitIdle,
		(VkHandle *)&c->vk.QueueWaitIdle,
		(VkHandle *)&c->vk.CreateCommandPool,
		(VkHandle *)&c->vk.DestroyCommandPool,
		(VkHandle *)&c->vk.AllocateCommandBuffers,
		(VkHandle *)&c->vk.BeginCommandBuffer,
		(VkHandle *)&c->vk.EndCommandBuffer,
		(VkHandle *)&c->vk.ResetCommandBuffer,
		(VkHandle *)&c->vk.CreateBuffer,
		(VkHandle *)&c->vk.DestroyBuffer,
		(VkHandle *)&c->vk.GetBufferMemoryRequirements,
		(VkHandle *)&c->vk.CreateImage,
		(VkHandle *)&c->vk.DestroyImage,
		(VkHandle *)&c->vk.GetImageMemoryRequirements,
		(VkHandle *)&c->vk.AllocateMemory,
		(VkHandle *)&c->vk.FreeMemory,
		(VkHandle *)&c->vk.BindBufferMemory,
		(VkHandle *)&c->vk.BindImageMemory,
		(VkHandle *)&c->vk.MapMemory, (VkHandle *)&c->vk.UnmapMemory,
		(VkHandle *)&c->vk.CreateImageView,
		(VkHandle *)&c->vk.DestroyImageView,
		(VkHandle *)&c->vk.CreateSampler,
		(VkHandle *)&c->vk.DestroySampler,
		(VkHandle *)&c->vk.CreateDescriptorSetLayout,
		(VkHandle *)&c->vk.DestroyDescriptorSetLayout,
		(VkHandle *)&c->vk.CreateDescriptorPool,
		(VkHandle *)&c->vk.DestroyDescriptorPool,
		(VkHandle *)&c->vk.AllocateDescriptorSets,
		(VkHandle *)&c->vk.UpdateDescriptorSets,
		(VkHandle *)&c->vk.CreatePipelineLayout,
		(VkHandle *)&c->vk.DestroyPipelineLayout,
		(VkHandle *)&c->vk.CreateShaderModule,
		(VkHandle *)&c->vk.DestroyShaderModule,
		(VkHandle *)&c->vk.CreateGraphicsPipelines,
		(VkHandle *)&c->vk.DestroyPipeline,
		(VkHandle *)&c->vk.CreateRenderPass,
		(VkHandle *)&c->vk.DestroyRenderPass,
		(VkHandle *)&c->vk.CreateFramebuffer,
		(VkHandle *)&c->vk.DestroyFramebuffer,
		(VkHandle *)&c->vk.CmdBeginRenderPass,
		(VkHandle *)&c->vk.CmdEndRenderPass,
		(VkHandle *)&c->vk.CmdBindPipeline,
		(VkHandle *)&c->vk.CmdBindVertexBuffers,
		(VkHandle *)&c->vk.CmdBindDescriptorSets,
		(VkHandle *)&c->vk.CmdSetViewport,
		(VkHandle *)&c->vk.CmdSetScissor,
		(VkHandle *)&c->vk.CmdPushConstants, (VkHandle *)&c->vk.CmdDraw,
		(VkHandle *)&c->vk.CmdPipelineBarrier,
		(VkHandle *)&c->vk.CmdCopyImage,
		(VkHandle *)&c->vk.CmdCopyBufferToImage,
		(VkHandle *)&c->vk.CmdCopyImageToBuffer,
		(VkHandle *)&c->vk.QueueSubmit,
		(VkHandle *)&c->vk.DestroyInstance
	};
	uint32_t i, ndev = 0;
	VkHandle devs[8];

	c->lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
	if (!c->lib)
		c->lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
	if (!c->lib) {
		snprintf(c->err, sizeof c->err,
		    "cannot load libvulkan.so.1: %s", dlerror());
		return -1;
	}
	c->vk.GetInstanceProcAddr = (void *)dlsym(c->lib,
	    "vkGetInstanceProcAddr");
	if (!c->vk.GetInstanceProcAddr) {
		snprintf(c->err, sizeof c->err, "no vkGetInstanceProcAddr");
		return -1;
	}
	{ VkApplicationInfo ai;
	  VkInstanceCreateInfo ci;
	  memset(&ai, 0, sizeof ai);
	  ai.sType = ST_APPLICATION_INFO;
	  ai.pApplicationName = "lui";
	  ai.apiVersion = VK_API_VERSION_1_1;
	  memset(&ci, 0, sizeof ci);
	  ci.sType = ST_INSTANCE_CREATE_INFO;
	  ci.pApplicationInfo = &ai;
	  if (c->vk.CreateInstance == NULL)
		c->vk.CreateInstance = (void *)c->vk.GetInstanceProcAddr(
		    VK_NULL_HANDLE, "vkCreateInstance");
	  int r = c->vk.CreateInstance(&ci, NULL, &c->inst);
	  if (r != VK_SUCCESS)
		return fail(c, "vkCreateInstance", r); }
	for (i = 0; i < sizeof names / sizeof names[0]; i++) {
		char fn[64];
		snprintf(fn, sizeof fn, "vk%s", names[i]);
		*slots[i] = c->vk.GetInstanceProcAddr(c->inst, fn);
		if (!*slots[i]) {
			snprintf(c->err, sizeof c->err,
			    "cannot resolve vk%s", names[i]);
			return -1;
		}
	}
	if (c->vk.EnumeratePhysicalDevices(c->inst, &ndev, NULL) ||
	    ndev == 0) {
		snprintf(c->err, sizeof c->err,
		    "no Vulkan physical device");
		return -1;
	}
	if (ndev > 8)
		ndev = 8;
	c->vk.EnumeratePhysicalDevices(c->inst, &ndev, devs);
	c->pdev = devs[0];
	{ /* device name and max texture size, from the raw properties */
	  char props[2048];
	  uint32_t type;
	  memset(props, 0, sizeof props);
	  c->vk.GetPhysicalDeviceProperties(c->pdev, props);
	  type = *(uint32_t *)(props + 16);
	  snprintf(c->driver, sizeof c->driver, "%.200s (type %u)",
	      props + 20, type);
	  c->max_size = *(uint32_t *)(props + 296); /* maxImageDimension2D */
	  if (c->max_size <= 0 || c->max_size > 65536)
		c->max_size = 16384; }
	{ /* queue family: first with graphics */
	  uint32_t nq = 0, k;
	  VkQueueFamilyProperties qs[16];
	  c->vk.GetPhysicalDeviceQueueFamilyProperties(c->pdev, &nq,
	      NULL);
	  if (nq > 16)
		nq = 16;
	  c->vk.GetPhysicalDeviceQueueFamilyProperties(c->pdev, &nq, qs);
	  c->qfam = 0;
	  for (k = 0; k < nq; k++)
		if (qs[k].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
			c->qfam = k;
			break;
		} }
	{ /* dual-source blending feature */
	  uint32_t feats[56];
	  memset(feats, 0, sizeof feats);
	  c->vk.GetPhysicalDeviceFeatures(c->pdev, feats);
	  c->dual = feats[7] ? 1 : 0; }
	{ float prio = 1.0f;
	  VkDeviceQueueCreateInfo qi;
	  VkDeviceCreateInfo di;
	  uint32_t feats[56];
	  memset(&qi, 0, sizeof qi);
	  qi.sType = ST_DEVICE_QUEUE_CREATE_INFO;
	  qi.queueFamilyIndex = c->qfam;
	  qi.queueCount = 1;
	  qi.pQueuePriorities = &prio;
	  memset(feats, 0, sizeof feats);
	  feats[7] = c->dual ? 1 : 0; /* dualSrcBlend */
	  memset(&di, 0, sizeof di);
	  di.sType = ST_DEVICE_CREATE_INFO;
	  di.queueCreateInfoCount = 1;
	  di.pQueueCreateInfos = &qi;
	  di.pEnabledFeatures = feats;
	  int r = c->vk.CreateDevice(c->pdev, &di, NULL, &c->dev);
	  if (r != VK_SUCCESS)
		return fail(c, "vkCreateDevice", r);
	  /* Resolve every entry point again at device level: some
	     loaders return NULL for device commands from
	     vkGetInstanceProcAddr. */
	  for (i = 0; i < sizeof names / sizeof names[0]; i++) {
		char fn[64];
		VkHandle p;
		snprintf(fn, sizeof fn, "vk%s", names[i]);
		p = c->vk.GetDeviceProcAddr
		    ? c->vk.GetDeviceProcAddr(c->dev, fn)
		    : VK_NULL_HANDLE;
		if (p)
			*slots[i] = p;
		if (!*slots[i]) {
			snprintf(c->err, sizeof c->err,
			    "cannot resolve vk%s", names[i]);
			return -1;
		}
	  }
	  c->vk.GetDeviceQueue(c->dev, c->qfam, 0, &c->queue); }
	{ VkCommandPoolCreateInfo pi;
	  VkCommandBufferAllocateInfo ai;
	  memset(&pi, 0, sizeof pi);
	  pi.sType = ST_COMMAND_POOL_CREATE_INFO;
	  pi.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	  pi.queueFamilyIndex = c->qfam;
	  if (c->vk.CreateCommandPool(c->dev, &pi, NULL, &c->pool))
		return fail(c, "vkCreateCommandPool", -1);
	  memset(&ai, 0, sizeof ai);
	  ai.sType = ST_COMMAND_BUFFER_ALLOCATE_INFO;
	  ai.commandPool = c->pool;
	  ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	  ai.commandBufferCount = 1;
	  if (c->vk.AllocateCommandBuffers(c->dev, &ai, &c->cmd))
		return fail(c, "vkAllocateCommandBuffers", -1); }
	if (make_render_pass(c, VK_ATTACHMENT_LOAD_OP_CLEAR, &c->rp_clear) ||
	    make_render_pass(c, VK_ATTACHMENT_LOAD_OP_LOAD, &c->rp_load))
		return -1;
	{ /* the frame image: BGRA8, so readback needs no swizzle */
	  c->frame_img = make_image(c, w, h, FMT_B8G8R8A8_UNORM,
	      VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
		  VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
	  if (!c->frame_img || image_mem(c, c->frame_img, &c->frame_mem))
		return fail(c, "frame image", -1);
	  c->frame_view = make_view(c, c->frame_img,
	      FMT_B8G8R8A8_UNORM);
	  if (!c->frame_view)
		return fail(c, "frame view", -1);
	  c->frame_fb = make_fb(c, c->frame_view, w, h);
	  if (!c->frame_fb)
		return fail(c, "frame framebuffer", -1); }
	{ /* sampler: linear, clamp — as the other backends' textures */
	  VkSamplerCreateInfo si;
	  memset(&si, 0, sizeof si);
	  si.sType = ST_SAMPLER_CREATE_INFO;
	  si.magFilter = VK_FILTER_LINEAR;
	  si.minFilter = VK_FILTER_LINEAR;
	  si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
	  si.addressModeU = si.addressModeV = si.addressModeW =
	      VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
	  si.maxLod = 1.0f;
	  if (c->vk.CreateSampler(c->dev, &si, NULL, &c->sampler))
		return fail(c, "vkCreateSampler", -1); }
	{ /* descriptor set layouts:
	     set 0 {0 mask, 1 color} (frame atlases)
	     set 1 {0 image, 1 backdrop} (per-batch textures)
	     pass set {0 uSrc} (backdrop pass sources) */
	  VkDescriptorSetLayoutBinding b[2];
	  VkDescriptorSetLayoutCreateInfo li;
	  memset(b, 0, sizeof b);
	  b[0].binding = 0;
	  b[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	  b[0].descriptorCount = 1;
	  b[0].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
	  b[1] = b[0];
	  b[1].binding = 1;
	  memset(&li, 0, sizeof li);
	  li.sType = ST_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	  li.bindingCount = 2;
	  li.pBindings = b;
	  if (c->vk.CreateDescriptorSetLayout(c->dev, &li, NULL,
		  &c->dsl0) ||
	      c->vk.CreateDescriptorSetLayout(c->dev, &li, NULL,
		  &c->dsl1))
		return fail(c, "vkCreateDescriptorSetLayout", -1);
	  li.bindingCount = 1;
	  if (c->vk.CreateDescriptorSetLayout(c->dev, &li, NULL,
		  &c->dslp))
		return fail(c, "vkCreateDescriptorSetLayout", -1); }
	{ VkDescriptorPoolSize ps;
	  VkDescriptorPoolCreateInfo pi;
	  ps.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	  ps.descriptorCount = 1024;
	  memset(&pi, 0, sizeof pi);
	  pi.sType = ST_DESCRIPTOR_POOL_CREATE_INFO;
	  pi.maxSets = 512;
	  pi.poolSizeCount = 1;
	  pi.pPoolSizes = &ps;
	  if (c->vk.CreateDescriptorPool(c->dev, &pi, NULL, &c->dpool))
		return fail(c, "vkCreateDescriptorPool", -1); }
	{ /* pipeline layouts + push constants */
	  VkPushConstantRange pc;
	  VkPipelineLayoutCreateInfo li;
	  VkHandle sets2[2] = { VK_NULL_HANDLE, VK_NULL_HANDLE };
	  memset(&pc, 0, sizeof pc);
	  pc.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
	  pc.offset = 0;
	  pc.size = 8; /* uSize */
	  memset(&li, 0, sizeof li);
	  li.sType = ST_PIPELINE_LAYOUT_CREATE_INFO;
	  li.setLayoutCount = 2;
	  li.pSetLayouts = sets2;
	  li.pushConstantRangeCount = 1;
	  li.pPushConstantRanges = &pc;
	  /* layouts created after dsl exist — fill in below */
	  sets2[0] = c->dsl0;
	  sets2[1] = c->dsl1;
	  if (c->vk.CreatePipelineLayout(c->dev, &li, NULL, &c->pl_main))
		return fail(c, "vkCreatePipelineLayout", -1);
	  pc.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
	  pc.size = 48;
	  li.setLayoutCount = 1;
	  sets2[0] = c->dslp;
	  li.pSetLayouts = sets2;
	  if (c->vk.CreatePipelineLayout(c->dev, &li, NULL, &c->pl_pass))
		return fail(c, "vkCreatePipelineLayout", -1); }
	/* The empty texture is id 0: bound wherever a slot has none. */
	if (tex_create(c, 1, 1, FMT_R8G8B8A8_UNORM) != 0)
		return -1;
	{ VkHandle l0 = c->dsl0, l1 = c->dsl1;
	  if (alloc_sets(c, &l0, 1, &c->ds0) ||
	      alloc_sets(c, &l1, 1, &c->ds_backdrop))
		return -1;
	  set_image(c, c->ds0, 0, c->texs[0].view);
	  set_image(c, c->ds0, 1, c->texs[0].view);
	  set_image(c, c->ds_backdrop, 0, c->texs[0].view);
	  set_image(c, c->ds_backdrop, 1, c->texs[0].view); }
	{ /* one-time: move the frame and the empty texture to
	     GENERAL */
	  VkCommandBufferBeginInfo bi;
	  memset(&bi, 0, sizeof bi);
	  bi.sType = ST_COMMAND_BUFFER_BEGIN_INFO;
	  if (c->vk.BeginCommandBuffer(c->cmd, &bi))
		return fail(c, "vkBeginCommandBuffer", -1);
	  to_general(c, c->frame_img);
	  to_general(c, c->texs[0].img);
	  if (c->vk.EndCommandBuffer(c->cmd))
		return fail(c, "vkEndCommandBuffer", -1);
	  if (submit_and_wait(c, c->cmd))
		return -1; }
	c->w = w;
	c->h = h;
	return 0;
}

/* {2 Pipelines} */

static VkHandle make_shader(Ctx *c, const uint32_t *code, size_t len)
{
	VkShaderModuleCreateInfo si;
	VkHandle m;
	memset(&si, 0, sizeof si);
	si.sType = ST_SHADER_MODULE_CREATE_INFO;
	si.codeSize = len;
	si.pCode = code;
	if (c->vk.CreateShaderModule(c->dev, &si, NULL, &m))
		return VK_NULL_HANDLE;
	return m;
}

/* flags: bit0 hole blend, bit1 backdrop-pass pipeline. */
static int make_pipeline(Ctx *c, const void *vspv, size_t vlen,
    const void *fspv, size_t flen, int flags)
{
	VkHandle vm, fm;
	VkPipelineShaderStageCreateInfo st[2];
	VkVertexInputBindingDescription vib;
	VkVertexInputAttributeDescription via[15];
	VkPipelineVertexInputStateCreateInfo vis;
	VkPipelineInputAssemblyStateCreateInfo ias;
	VkViewport vp;
	VkRect2D sc;
	VkPipelineViewportStateCreateInfo vps;
	VkPipelineRasterizationStateCreateInfo ras;
	VkPipelineMultisampleStateCreateInfo ms;
	VkPipelineColorBlendAttachmentState att;
	VkPipelineColorBlendStateCreateInfo cbs;
	uint32_t dyn[2];
	VkPipelineDynamicStateCreateInfo ds;
	VkGraphicsPipelineCreateInfo pi;
	VkHandle pipe;
	int i, pass = flags & 2;
	if (c->npipes == c->pipes_cap) {
		int cap = c->pipes_cap ? c->pipes_cap * 2 : 8;
		VkHandle *np = realloc(c->pipes, sizeof(VkHandle) * cap);
		if (!np)
			return fail(c, "out of memory", -1);
		c->pipes = np;
		c->pipes_cap = cap;
	}
	vm = make_shader(c, vspv, vlen);
	fm = make_shader(c, fspv, flen);
	if (!vm || !fm)
		return fail(c, "vkCreateShaderModule", -1);
	memset(st, 0, sizeof st);
	st[0].sType = ST_PIPELINE_SHADER_STAGE_CREATE_INFO;
	st[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
	st[0].module = vm;
	st[0].pName = "main";
	st[1].sType = ST_PIPELINE_SHADER_STAGE_CREATE_INFO;
	st[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
	st[1].module = fm;
	st[1].pName = "main";
	memset(&vib, 0, sizeof vib);
	vib.stride = 240; /* 15 float4s per instance */
	vib.inputRate = VK_VERTEX_INPUT_RATE_INSTANCE;
	memset(via, 0, sizeof via);
	for (i = 0; i < 15; i++) {
		via[i].location = (uint32_t)i;
		via[i].binding = 0;
		via[i].format = FMT_R32G32B32A32_SFLOAT;
		via[i].offset = (uint32_t)(i * 16);
	}
	memset(&vis, 0, sizeof vis);
	vis.sType = ST_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
	if (!pass) {
		vis.vertexBindingDescriptionCount = 1;
		vis.pVertexBindingDescriptions = &vib;
		vis.vertexAttributeDescriptionCount = 15;
		vis.pVertexAttributeDescriptions = via;
	}
	memset(&ias, 0, sizeof ias);
	ias.sType = ST_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
	ias.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
	memset(&vp, 0, sizeof vp);
	vp.width = (float)c->w;
	vp.height = (float)c->h;
	vp.maxDepth = 1.0f;
	memset(&sc, 0, sizeof sc);
	sc.extent.width = (uint32_t)c->w;
	sc.extent.height = (uint32_t)c->h;
	memset(&vps, 0, sizeof vps);
	vps.sType = ST_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
	vps.viewportCount = 1;
	vps.pViewports = &vp;
	vps.scissorCount = 1;
	vps.pScissors = &sc;
	memset(&ras, 0, sizeof ras);
	ras.sType = ST_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
	ras.polygonMode = VK_POLYGON_MODE_FILL;
	ras.cullMode = VK_CULL_MODE_NONE;
	ras.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
	ras.lineWidth = 1.0f;
	memset(&ms, 0, sizeof ms);
	ms.sType = ST_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
	ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
	memset(&att, 0, sizeof att);
	att.colorWriteMask = VK_COLOR_COMPONENT_ALL;
	if (!pass) {
		/* Premultiplied colors blend over what is drawn; a hole
		   takes their coverage away. With dual-source blending the
		   source's alpha is per channel; without it, the mean. */
		uint32_t src = (flags & 1) ? VK_BLEND_FACTOR_ZERO
		    : VK_BLEND_FACTOR_ONE;
		uint32_t dstc = c->dual ? VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR
		    : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
		uint32_t dsta = c->dual ? VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA
		    : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
		att.blendEnable = 1;
		att.srcColorBlendFactor = src;
		att.dstColorBlendFactor = dstc;
		att.colorBlendOp = VK_BLEND_OP_ADD;
		att.srcAlphaBlendFactor = src;
		att.dstAlphaBlendFactor = dsta;
		att.alphaBlendOp = VK_BLEND_OP_ADD;
	}
	memset(&cbs, 0, sizeof cbs);
	cbs.sType = ST_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
	cbs.attachmentCount = 1;
	cbs.pAttachments = &att;
	dyn[0] = VK_DYNAMIC_STATE_VIEWPORT;
	dyn[1] = VK_DYNAMIC_STATE_SCISSOR;
	memset(&ds, 0, sizeof ds);
	ds.sType = ST_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
	ds.dynamicStateCount = 2;
	ds.pDynamicStates = dyn;
	memset(&pi, 0, sizeof pi);
	pi.sType = ST_GRAPHICS_PIPELINE_CREATE_INFO;
	pi.stageCount = 2;
	pi.pStages = st;
	pi.pVertexInputState = &vis;
	pi.pInputAssemblyState = &ias;
	pi.pViewportState = &vps;
	pi.pRasterizationState = &ras;
	pi.pMultisampleState = &ms;
	pi.pColorBlendState = &cbs;
	pi.pDynamicState = &ds;
	pi.layout = pass ? c->pl_pass : c->pl_main;
	pi.renderPass = c->rp_load;
	pi.subpass = 0;
	if (c->vk.CreateGraphicsPipelines(c->dev, VK_NULL_HANDLE, 1, &pi,
		NULL, &pipe)) {
		c->vk.DestroyShaderModule(c->dev, vm, NULL);
		c->vk.DestroyShaderModule(c->dev, fm, NULL);
		return fail(c, "vkCreateGraphicsPipelines", -1);
	}
	c->vk.DestroyShaderModule(c->dev, vm, NULL);
	c->vk.DestroyShaderModule(c->dev, fm, NULL);
	c->pipes[c->npipes] = pipe;
	return c->npipes++;
}

/* {2 Frame plumbing} */

static void rp_begin(Ctx *c, VkHandle rp, VkHandle fb, int w, int h,
    const float *clear)
{
	VkRenderPassBeginInfo bi;
	VkClearValue cv;
	memset(&bi, 0, sizeof bi);
	bi.sType = ST_RENDER_PASS_BEGIN_INFO;
	bi.renderPass = rp;
	bi.framebuffer = fb;
	bi.renderArea.extent.width = (uint32_t)w;
	bi.renderArea.extent.height = (uint32_t)h;
	if (clear) {
		memcpy(cv.color, clear, sizeof cv.color);
		bi.clearValueCount = 1;
		bi.pClearValues = &cv;
	}
	c->vk.CmdBeginRenderPass(c->cmd, &bi, 0);
	c->rp_open = 1;
}

static void rp_end(Ctx *c)
{
	if (c->rp_open) {
		c->vk.CmdEndRenderPass(c->cmd);
		c->rp_open = 0;
	}
}

/* {1 Runtime GLSL compilation}

   Effect bodies are strings created by the scene, so their fragment
   shaders compile at runtime: via libshaderc when a shared library is
   installed, else by invoking a glslangValidator binary (PATH or
   LUI_VK_GLSLANG), else reporting that effects cannot compile. */
static int compile_glsl(Ctx *c, const char *src, size_t slen,
    unsigned char **out, size_t *olen)
{
	static void *shaderc = (void *)-1;
	void *(*init)(void) = NULL;
	void *(*opt_init)(void) = NULL;
	void *(*opt_env)(void *, int, int) = NULL;
	void *(*into)(void *, const char *, size_t, int, const char *,
	    const char *, void *) = NULL;
	int (*status)(void *) = NULL;
	size_t (*len)(void *) = NULL;
	const void *(*bytes)(void *) = NULL;
	void (*rel)(void *) = NULL;
	(void)shaderc;
	/* libshaderc, if present */
	{ static int tried;
	  static void *lib;
	  if (!tried) {
		tried = 1;
		lib = dlopen("libshaderc_shared.so.1", RTLD_NOW | RTLD_LOCAL);
		if (!lib)
			lib = dlopen("libshaderc_shared.so",
			    RTLD_NOW | RTLD_LOCAL);
		if (!lib)
			lib = dlopen("libshaderc.so.1", RTLD_NOW | RTLD_LOCAL);
		if (!lib)
			lib = dlopen("libshaderc.so", RTLD_NOW | RTLD_LOCAL);
	  }
	  if (lib) {
		init = dlsym(lib, "shaderc_compiler_initialize");
		opt_init = dlsym(lib, "shaderc_compile_options_initialize");
		opt_env = dlsym(lib,
		    "shaderc_compile_options_set_target_env");
		into = dlsym(lib, "shaderc_compile_into_spv");
		status = dlsym(lib, "shaderc_result_get_compilation_status");
		len = dlsym(lib, "shaderc_result_get_length");
		bytes = dlsym(lib, "shaderc_result_get_bytes");
		rel = dlsym(lib, "shaderc_result_release");
		if (init && opt_init && opt_env && into && status && len &&
		    bytes && rel) {
			void *cc = init();
			void *o = opt_init();
			void *r;
			unsigned char *res = NULL;
			/* shaderc_target_env_vulkan, env vulkan1.2 */
			opt_env(o, 0, (2 << 22));
			r = into(cc, src, slen, 4 /* fragment */,
			    "lui_effect.frag", "main", o);
			if (r && status(r) == 0) {
				size_t n = len(r);
				res = malloc(n);
				if (res)
					memcpy(res, bytes(r), n);
				*olen = n;
			}
			if (r)
				rel(r);
			if (res) {
				*out = res;
				return 0;
			}
		}
	  } }
	/* a glslangValidator executable */
	{ const char *exe = getenv("LUI_VK_GLSLANG");
	  char tmp_src[] = "/tmp/lui_vk_fxXXXXXX";
	  char tmp_out[] = "/tmp/lui_vk_fxXXXXXX.spv";
	  int fd = -1;
	  pid_t pid;
	  int st = 0;
	  if (!exe || !*exe)
		exe = "glslangValidator";
	  fd = mkstemp(tmp_src);
	  if (fd < 0)
		goto no;
	  if (write(fd, src, slen) != (ssize_t)slen) {
		close(fd);
		goto no;
	  }
	  close(fd);
	  memcpy(tmp_out, tmp_src, sizeof tmp_src);
	  strcat(tmp_out, ".spv");
	  pid = fork();
	  if (pid == 0) {
		int devnull = open("/dev/null", 2);
		if (devnull >= 0) {
			dup2(devnull, 1);
			dup2(devnull, 2);
		}
		execlp(exe, exe, "-V", "-S", "frag", tmp_src, "-o",
		    tmp_out, (char *)NULL);
		_exit(127);
	  }
	  if (pid < 0 || waitpid(pid, &st, 0) < 0 || !WIFEXITED(st) ||
	      WEXITSTATUS(st) != 0)
		goto no;
	  { FILE *f = fopen(tmp_out, "rb");
	    long n;
	    unsigned char *res;
	    if (!f)
		goto no;
	    fseek(f, 0, SEEK_END);
	    n = ftell(f);
	    fseek(f, 0, SEEK_SET);
	    res = malloc((size_t)n);
	    if (!res || fread(res, 1, (size_t)n, f) != (size_t)n) {
		fclose(f);
		free(res);
		goto no;
	    }
	    fclose(f);
	    *out = res;
	    *olen = (size_t)n; }
	  unlink(tmp_src);
	  unlink(tmp_out);
	  return 0;
	no:
	  snprintf(c->err, sizeof c->err,
	      "cannot compile effect GLSL: no libshaderc and no "
	      "glslangValidator (set LUI_VK_GLSLANG)");
	  return -1; }
}

/* {1 OCaml} */

#define Ctx_val(v) (*(Ctx **)Data_custom_val(v))

static void ctx_finalize(value v)
{
	Ctx *c = Ctx_val(v);
	if (c) {
		destroy_ctx(c);
		*(Ctx **)Data_custom_val(v) = NULL;
	}
}

static struct custom_operations ctx_ops = {
	.identifier = "lui_vulkan.ctx",
	.finalize = ctx_finalize,
	.compare = custom_compare_default,
	.hash = custom_hash_default,
	.serialize = custom_serialize_default,
	.deserialize = custom_deserialize_default,
	.compare_ext = custom_compare_ext_default,
	.fixed_length = custom_fixed_length_default
};

static value box_ctx(Ctx *c)
{
	value v = caml_alloc_custom(&ctx_ops, sizeof(Ctx *), 0, 1);
	*(Ctx **)Data_custom_val(v) = c;
	return v;
}

CAMLprim value lui_vk_create(value w, value h)
{
	CAMLparam2(w, h);
	Ctx *c = calloc(1, sizeof(Ctx));
	if (!c)
		caml_failwith("lui_vk_create: out of memory");
	c->w = Int_val(w);
	c->h = Int_val(h);
	if (create_ctx(c, c->w, c->h) < 0) {
		char msg[600];
		snprintf(msg, sizeof msg, "lui_vk_create: %s",
		    c->err[0] ? c->err : "unknown error");
		destroy_ctx(c);
		caml_failwith(msg);
	}
	CAMLreturn(box_ctx(c));
}

CAMLprim value lui_vk_destroy(value ctx)
{
	CAMLparam1(ctx);
	Ctx *c = Ctx_val(ctx);
	if (c) {
		destroy_ctx(c);
		*(Ctx **)Data_custom_val(ctx) = NULL;
	}
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_driver(value ctx)
{
	CAMLparam1(ctx);
	Ctx *c = Ctx_val(ctx);
	CAMLreturn(caml_copy_string(c && c->driver[0] ? c->driver : "none"));
}

CAMLprim value lui_vk_dual(value ctx)
{
	return Val_bool(Ctx_val(ctx)->dual);
}

CAMLprim value lui_vk_max_size(value ctx)
{
	return Val_int(Ctx_val(ctx)->max_size);
}

CAMLprim value lui_vk_pipeline(value ctx, value vspv, value fspv,
    value flags)
{
	CAMLparam4(ctx, vspv, fspv, flags);
	Ctx *c = Ctx_val(ctx);
	int id = make_pipeline(c, Bytes_val(vspv),
	    caml_string_length(vspv), Bytes_val(fspv),
	    caml_string_length(fspv), Int_val(flags));
	if (id < 0)
		caml_failwith(c->err);
	CAMLreturn(Val_int(id));
}

CAMLprim value lui_vk_tex_new(value ctx, value w, value h, value fmt)
{
	CAMLparam4(ctx, w, h, fmt);
	Ctx *c = Ctx_val(ctx);
	uint32_t f = Int_val(fmt) == 0 ? FMT_R8_UNORM
	    : Int_val(fmt) == 1 ? FMT_R8G8B8A8_UNORM
				: FMT_B8G8R8A8_UNORM;
	int id = tex_create(c, Int_val(w), Int_val(h), f);
	if (id < 0)
		caml_failwith(c->err);
	CAMLreturn(Val_int(id));
}

CAMLprim value lui_vk_tex_delete(value ctx, value id)
{
	CAMLparam2(ctx, id);
	Ctx *c = Ctx_val(ctx);
	Tex *t;
	if (tex_at(c, Int_val(id), &t) == 0)
		tex_destroy(c, t);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_bind_atlas(value ctx, value slot, value id)
{
	CAMLparam3(ctx, slot, id);
	Ctx *c = Ctx_val(ctx);
	Tex *t;
	if (tex_at(c, Int_val(id), &t) == 0)
		set_image(c, c->ds0, Int_val(slot), t->view);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_bind_backdrop(value ctx, value id)
{
	CAMLparam2(ctx, id);
	Ctx *c = Ctx_val(ctx);
	Tex *t;
	if (tex_at(c, Int_val(id), &t) == 0)
		set_image(c, c->ds_backdrop, 1, t->view);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_begin(value ctx)
{
	CAMLparam1(ctx);
	Ctx *c = Ctx_val(ctx);
	VkCommandBufferBeginInfo bi;
	c->vk.ResetCommandBuffer(c->cmd, 0);
	memset(&bi, 0, sizeof bi);
	bi.sType = ST_COMMAND_BUFFER_BEGIN_INFO;
	if (c->vk.BeginCommandBuffer(c->cmd, &bi))
		caml_failwith("lui_vk_begin: vkBeginCommandBuffer failed");
	c->recording = 1;
	c->rp_open = 0;
	c->stg_used = 0;
	CAMLreturn(Val_unit);
}

/* Ends, submits and restarts the frame command buffer. Splitting the
   submission keeps same-queue ordering, so copies already recorded
   complete before the draws submitted after them. Only safe outside
   a render pass. */
static int flush_cmd(Ctx *c)
{
	VkCommandBufferBeginInfo bi;
	if (c->rp_open)
		return fail(c, "cannot flush inside a render pass", -1);
	if (c->vk.EndCommandBuffer(c->cmd))
		return fail(c, "vkEndCommandBuffer", -1);
	if (submit_and_wait(c, c->cmd) < 0)
		return -1;
	c->vk.ResetCommandBuffer(c->cmd, 0);
	memset(&bi, 0, sizeof bi);
	bi.sType = ST_COMMAND_BUFFER_BEGIN_INFO;
	if (c->vk.BeginCommandBuffer(c->cmd, &bi))
		return fail(c, "vkBeginCommandBuffer", -1);
	c->stg_used = 0;
	return 0;
}

CAMLprim value lui_vk_tex_upload(value ctx, value id, value x, value y,
    value w, value h, value data)
{
	CAMLparam5(ctx, id, x, y, w);
	CAMLxparam2(h, data);
	Ctx *c = Ctx_val(ctx);
	Tex *t;
	VkBufferImageCopy r;
	int bpp;
	if (tex_at(c, Int_val(id), &t) < 0)
		caml_failwith(c->err);
	bpp = t->fmt == FMT_R8_UNORM ? 1 : 4;
	{ VkDeviceSize size =
	    (VkDeviceSize)Int_val(w) * Int_val(h) * bpp;
	/* Every upload of a frame needs its own staging offset: the copies
	   run at submission time, when the buffer must still hold each
	   upload's bytes. Growing is safe only before the frame's first
	   copy (recorded copies keep the old buffer handle); past that the
	   recording is flushed into its own submission first. */
	if (c->stg_used + size > c->stg_cap && c->stg_used > 0 &&
	    flush_cmd(c) < 0)
		caml_failwith(c->err);
	if (ensure_staging(c, c->stg_used + size) < 0)
		caml_failwith(c->err);
	memcpy((char *)c->stg_map + c->stg_used, Bytes_val(data), size);
	memset(&r, 0, sizeof r);
	r.bufferOffset = c->stg_used;
	c->stg_used = (c->stg_used + size + 63) & ~(VkDeviceSize)63;
	r.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	r.imageSubresource.layerCount = 1;
	r.imageOffset.x = Int_val(x);
	r.imageOffset.y = Int_val(y);
	r.imageExtent.width = (uint32_t)Int_val(w);
	r.imageExtent.height = (uint32_t)Int_val(h);
	r.imageExtent.depth = 1;
	c->vk.CmdCopyBufferToImage(c->cmd, c->stg, t->img,
	    VK_IMAGE_LAYOUT_GENERAL, 1, &r);
	}
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_tex_upload_bytecode(value *argv, int argc)
{
	(void)argc;
	return lui_vk_tex_upload(argv[0], argv[1], argv[2], argv[3],
	    argv[4], argv[5], argv[6]);
}

CAMLprim value lui_vk_instances(value ctx, value ba)
{
	CAMLparam2(ctx, ba);
	Ctx *c = Ctx_val(ctx);
	VkDeviceSize n =
	    (VkDeviceSize)Caml_ba_array_val(ba)->dim[0] * 4;
	if (n > 0) {
		if (ensure_vb(c, n) < 0)
			caml_failwith(c->err);
		memcpy(c->vb_map, Caml_ba_data_val(ba), n);
	}
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_frame(value ctx, value r, value g, value b, value a)
{
	CAMLparam5(ctx, r, g, b, a);
	Ctx *c = Ctx_val(ctx);
	float clear[4] = { (float)Double_val(r), (float)Double_val(g),
		(float)Double_val(b), (float)Double_val(a) };
	float us[2] = { (float)c->w, (float)c->h };
	VkViewport vp;
	barrier(c); /* uploads recorded before the frame become visible */
	rp_begin(c, c->rp_clear, c->frame_fb, c->w, c->h, clear);
	/* A negative viewport height flips the clip-space y back down,
	   so the shared shader math — written for y up — is unchanged
	   and frames land top-down. */
	memset(&vp, 0, sizeof vp);
	vp.y = (float)c->h;
	vp.width = (float)c->w;
	vp.height = -(float)c->h;
	vp.maxDepth = 1.0f;
	c->vk.CmdSetViewport(c->cmd, 0, 1, &vp);
	c->vk.CmdPushConstants(c->cmd, c->pl_main,
	    VK_SHADER_STAGE_VERTEX_BIT, 0, 8, us);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_frame_bytecode(value *argv, int argc)
{
	(void)argc;
	return lui_vk_frame(argv[0], argv[1], argv[2], argv[3], argv[4]);
}

CAMLprim value lui_vk_rp_end(value ctx)
{
	Ctx *c = Ctx_val(ctx);
	rp_end(c);
	return Val_unit;
}

CAMLprim value lui_vk_resume(value ctx)
{
	Ctx *c = Ctx_val(ctx);
	VkViewport vp;
	rp_end(c);
	rp_begin(c, c->rp_load, c->frame_fb, c->w, c->h, NULL);
	memset(&vp, 0, sizeof vp);
	vp.y = (float)c->h;
	vp.width = (float)c->w;
	vp.height = -(float)c->h;
	vp.maxDepth = 1.0f;
	c->vk.CmdSetViewport(c->cmd, 0, 1, &vp);
	return Val_unit;
}

/* ds_sel: 0 = the texture's own set (its image), 1 = the backdrop set
   (backdrop0 bound to uBackdrop). ds_id: a texture id for sel 0. */
CAMLprim value lui_vk_draw(value ctx, value pipe, value ds_sel,
    value ds_id, value l, value t, value r, value b, value first,
    value count)
{
	CAMLparam5(ctx, pipe, ds_sel, ds_id, l);
	CAMLxparam5(t, r, b, first, count);
	Ctx *c = Ctx_val(ctx);
	VkRect2D sc;
	VkHandle set, zero = 0;
	int p = Int_val(pipe);
	if (p < 0 || p >= c->npipes)
		caml_failwith("lui_vk_draw: bad pipeline");
	c->vk.CmdBindPipeline(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
	    c->pipes[p]);
	c->vk.CmdBindDescriptorSets(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
	    c->pl_main, 0, 1, &c->ds0, 0, NULL);
	if (Int_val(ds_sel) == 1)
		set = c->ds_backdrop;
	else {
		Tex *tx;
		if (tex_at(c, Int_val(ds_id), &tx) < 0)
			set = c->texs[0].ds;
		else
			set = tx->ds;
	}
	c->vk.CmdBindDescriptorSets(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
	    c->pl_main, 1, 1, &set, 0, NULL);
	if (c->vb) {
		c->vk.CmdBindVertexBuffers(c->cmd, 0, 1, &c->vb, &zero);
	}
	sc.offset.x = Int_val(l);
	sc.offset.y = Int_val(t);
	sc.extent.width = (uint32_t)(Int_val(r) - Int_val(l));
	sc.extent.height = (uint32_t)(Int_val(b) - Int_val(t));
	c->vk.CmdSetScissor(c->cmd, 0, 1, &sc);
	c->vk.CmdDraw(c->cmd, 4, (uint32_t)Int_val(count), 0,
	    (uint32_t)Int_val(first));
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_draw_bytecode(value *argv, int argc)
{
	(void)argc;
	return lui_vk_draw(argv[0], argv[1], argv[2], argv[3], argv[4],
	    argv[5], argv[6], argv[7], argv[8], argv[9]);
}

/* Copy the (x,y,w,h) region of the frame into the top-left of the
   destination texture. Must be called outside any render pass. */
CAMLprim value lui_vk_copy_frame(value ctx, value dst, value x, value y,
    value w, value h)
{
	CAMLparam5(ctx, dst, x, y, w);
	CAMLxparam1(h);
	Ctx *c = Ctx_val(ctx);
	Tex *t;
	VkImageCopy r;
	if (tex_at(c, Int_val(dst), &t) < 0)
		caml_failwith(c->err);
	barrier(c);
	memset(&r, 0, sizeof r);
	r.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	r.srcSubresource.layerCount = 1;
	r.srcOffset.x = Int_val(x);
	r.srcOffset.y = Int_val(y);
	r.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	r.dstSubresource.layerCount = 1;
	r.extent.width = (uint32_t)Int_val(w);
	r.extent.height = (uint32_t)Int_val(h);
	r.extent.depth = 1;
	c->vk.CmdCopyImage(c->cmd, c->frame_img, VK_IMAGE_LAYOUT_GENERAL,
	    t->img, VK_IMAGE_LAYOUT_GENERAL, 1, &r);
	barrier(c);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_copy_frame_bytecode(value *argv, int argc)
{
	(void)argc;
	return lui_vk_copy_frame(argv[0], argv[1], argv[2], argv[3],
	    argv[4], argv[5]);
}

/* One backdrop pass: draw pipe's fullscreen quad over the (w,h) texels
   at the start of dst, sampling src. dims packs the push constants:
   origin.xy, limit.xy, shift.xy, dir.xy, down, radius — fourteen ints
   — and sigma is a float. */
CAMLprim value lui_vk_pass(value ctx, value pipe, value src, value dst,
    value w, value h, value dims, value sigma)
{
	CAMLparam5(ctx, pipe, src, dst, w);
	CAMLxparam3(h, dims, sigma);
	Ctx *c = Ctx_val(ctx);
	Tex *ts, *td;
	int p = Int_val(pipe);
	VkRect2D sc;
	VkViewport vp;
	uint32_t pc[12];
	const int *d = NULL;
	if (p < 0 || p >= c->npipes)
		caml_failwith("lui_vk_pass: bad pipeline");
	if (tex_at(c, Int_val(src), &ts) < 0 ||
	    tex_at(c, Int_val(dst), &td) < 0)
		caml_failwith(c->err);
	if (Wosize_val(dims) < 10)
		caml_failwith("lui_vk_pass: bad dims");
	{ int k;
	  for (k = 0; k < 10; k++)
		pc[k] = (uint32_t)Int_val(Field(dims, k)); }
	(void)d;
	{ float s = (float)Double_val(sigma), z = 0.0f;
	  memcpy(&pc[10], &s, 4);
	  memcpy(&pc[11], &z, 4); }
	barrier(c);
	rp_begin(c, c->rp_load, td->fb, td->w, td->h, NULL);
	c->vk.CmdBindPipeline(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
	    c->pipes[p]);
	c->vk.CmdBindDescriptorSets(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
	    c->pl_pass, 0, 1, &ts->dsp, 0, NULL);
	memset(&vp, 0, sizeof vp);
	vp.width = (float)td->w;
	vp.height = (float)td->h;
	vp.maxDepth = 1.0f;
	c->vk.CmdSetViewport(c->cmd, 0, 1, &vp);
	sc.offset.x = 0;
	sc.offset.y = 0;
	sc.extent.width = (uint32_t)Int_val(w);
	sc.extent.height = (uint32_t)Int_val(h);
	c->vk.CmdSetScissor(c->cmd, 0, 1, &sc);
	c->vk.CmdPushConstants(c->cmd, c->pl_pass,
	    VK_SHADER_STAGE_FRAGMENT_BIT, 0, 48, pc);
	c->vk.CmdDraw(c->cmd, 4, 1, 0, 0);
	rp_end(c);
	barrier(c);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_pass_bytecode(value *argv, int argc)
{
	(void)argc;
	return lui_vk_pass(argv[0], argv[1], argv[2], argv[3], argv[4],
	    argv[5], argv[6], argv[7]);
}

CAMLprim value lui_vk_end_frame(value ctx)
{
	CAMLparam1(ctx);
	Ctx *c = Ctx_val(ctx);
	rp_end(c);
	if (c->vk.EndCommandBuffer(c->cmd))
		caml_failwith("lui_vk_end_frame: vkEndCommandBuffer failed");
	c->recording = 0;
	if (submit_and_wait(c, c->cmd))
		caml_failwith(c->err);
	CAMLreturn(Val_unit);
}

CAMLprim value lui_vk_read(value ctx)
{
	CAMLparam1(ctx);
	Ctx *c = Ctx_val(ctx);
	VkDeviceSize need = (VkDeviceSize)c->w * c->h * 4;
	VkCommandBufferBeginInfo bi;
	VkBufferImageCopy r;
	CAMLlocal1(res);
	if (c->rb_cap < need) {
		VkDeviceSize cap = need;
		if (c->rb) {
			c->vk.DestroyBuffer(c->dev, c->rb, NULL);
			c->vk.FreeMemory(c->dev, c->rb_mem, NULL);
			c->rb = VK_NULL_HANDLE;
		}
		if (make_buffer(c, cap, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
			VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &c->rb,
			&c->rb_mem, &c->rb_map) < 0)
			caml_failwith(c->err);
		c->rb_cap = cap;
	}
	c->vk.ResetCommandBuffer(c->cmd, 0);
	memset(&bi, 0, sizeof bi);
	bi.sType = ST_COMMAND_BUFFER_BEGIN_INFO;
	if (c->vk.BeginCommandBuffer(c->cmd, &bi))
		caml_failwith("lui_vk_read: begin failed");
	barrier(c);
	/* the frame is sampled after this copy completes */
	memset(&r, 0, sizeof r);
	r.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	r.imageSubresource.layerCount = 1;
	r.imageExtent.width = (uint32_t)c->w;
	r.imageExtent.height = (uint32_t)c->h;
	r.imageExtent.depth = 1;
	c->vk.CmdCopyImageToBuffer(c->cmd, c->frame_img,
	    VK_IMAGE_LAYOUT_GENERAL, c->rb, 1, &r);
	barrier(c);
	c->vk.EndCommandBuffer(c->cmd);
	if (submit_and_wait(c, c->cmd))
		caml_failwith(c->err);
	res = caml_alloc_string(need);
	memcpy(Bytes_val(res), c->rb_map, need);
	CAMLreturn(res);
}

CAMLprim value lui_vk_compile(value ctx, value src)
{
	CAMLparam2(ctx, src);
	Ctx *c = Ctx_val(ctx);
	unsigned char *spv = NULL;
	size_t n = 0;
	size_t slen = caml_string_length(src);
	char *buf;
	CAMLlocal1(res);
	buf = malloc(slen + 1);
	if (!buf)
		caml_failwith("lui_vk_compile: out of memory");
	memcpy(buf, Bytes_val(src), slen);
	buf[slen] = 0;
	if (compile_glsl(c, buf, slen, &spv, &n) < 0 || !spv) {
		char msg[600];
		snprintf(msg, sizeof msg, "lui_vk_compile: %s", c->err);
		free(buf);
		caml_failwith(msg);
	}
	free(buf);
	res = caml_alloc_string(n);
	memcpy(Bytes_val(res), spv, n);
	free(spv);
	CAMLreturn(res);
}

#else /* !__linux__ */

#define VK_STUB(name) \
	CAMLprim value name(value a) \
	{ \
		caml_failwith(#name ": this backend requires Linux"); \
		return Val_unit; \
	}
#define VK_STUB2(name) \
	CAMLprim value name(value a, value b) \
	{ \
		caml_failwith(#name ": this backend requires Linux"); \
		return Val_unit; \
	}
#define VK_STUB3(name) \
	CAMLprim value name(value a, value b, value c) \
	{ \
		caml_failwith(#name ": this backend requires Linux"); \
		return Val_unit; \
	}
#define VK_STUB4(name) \
	CAMLprim value name(value a, value b, value c, value d) \
	{ \
		caml_failwith(#name ": this backend requires Linux"); \
		return Val_unit; \
	}
#define VK_STUB5(name) \
	CAMLprim value name(value a, value b, value c, value d, value e) \
	{ \
		caml_failwith(#name ": this backend requires Linux"); \
		return Val_unit; \
	}

VK_STUB2(lui_vk_create)
VK_STUB(lui_vk_destroy)
VK_STUB(lui_vk_driver)
VK_STUB(lui_vk_dual)
VK_STUB(lui_vk_max_size)
VK_STUB4(lui_vk_pipeline)
VK_STUB4(lui_vk_tex_new)
VK_STUB2(lui_vk_tex_delete)
VK_STUB3(lui_vk_bind_atlas)
VK_STUB2(lui_vk_bind_backdrop)
VK_STUB(lui_vk_begin)
VK_STUB(lui_vk_rp_end)
VK_STUB(lui_vk_resume)
VK_STUB2(lui_vk_instances)
VK_STUB(lui_vk_end_frame)
VK_STUB(lui_vk_read)

CAMLprim value lui_vk_tex_upload(value a, value b, value c, value d,
    value e, value f, value g)
{
	(void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
	caml_failwith("lui_vk_tex_upload: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_tex_upload_bytecode(value *argv, int argc)
{
	(void)argv; (void)argc;
	caml_failwith("lui_vk_tex_upload: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_frame(value a, value b, value c, value d, value e)
{
	(void)a; (void)b; (void)c; (void)d; (void)e;
	caml_failwith("lui_vk_frame: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_frame_bytecode(value *argv, int argc)
{
	(void)argv; (void)argc;
	caml_failwith("lui_vk_frame: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_draw(value a, value b, value c, value d, value e,
    value f, value g, value h, value i, value j)
{
	(void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
	(void)h; (void)i; (void)j;
	caml_failwith("lui_vk_draw: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_draw_bytecode(value *argv, int argc)
{
	(void)argv; (void)argc;
	caml_failwith("lui_vk_draw: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_copy_frame(value a, value b, value c, value d,
    value e, value f)
{
	(void)a; (void)b; (void)c; (void)d; (void)e; (void)f;
	caml_failwith("lui_vk_copy_frame: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_copy_frame_bytecode(value *argv, int argc)
{
	(void)argv; (void)argc;
	caml_failwith("lui_vk_copy_frame: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_pass(value a, value b, value c, value d, value e,
    value f, value g, value h)
{
	(void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
	(void)h;
	caml_failwith("lui_vk_pass: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_pass_bytecode(value *argv, int argc)
{
	(void)argv; (void)argc;
	caml_failwith("lui_vk_pass: this backend requires Linux");
	return Val_unit;
}
CAMLprim value lui_vk_compile(value a, value b)
{
	(void)a; (void)b;
	caml_failwith("lui_vk_compile: this backend requires Linux");
	return Val_unit;
}

#endif
