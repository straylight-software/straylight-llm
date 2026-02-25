// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hydrogen.GPU.WebGPU.Device — FFI
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// THE ONLY JAVASCRIPT IN THE WEBGPU RUNTIME.
//
// All other WebGPU modules are pure PureScript. This file contains
// the minimal FFI required to interact with the browser's WebGPU API.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ─────────────────────────────────────────────────────────────────────────────
// INITIALIZATION
// ─────────────────────────────────────────────────────────────────────────────

export const isWebGPUSupportedImpl = () => 
  typeof navigator !== 'undefined' && navigator.gpu !== undefined;

export const requestAdapterImpl = desc => onSuccess => onError => () => {
  if (!navigator.gpu) {
    onError("WebGPU not supported")();
    return;
  }
  navigator.gpu.requestAdapter(desc).then(
    adapter => {
      if (adapter) {
        onSuccess(adapter)();
      } else {
        onError("No adapter available")();
      }
    },
    err => onError(err.message)()
  );
};

export const requestDeviceImpl = adapter => desc => onSuccess => onError => () => {
  adapter.requestDevice(desc).then(
    device => onSuccess(device)(),
    err => onError(err.message)()
  );
};

export const configureCanvasImpl = device => canvas => config => () => {
  try {
    const ctx = canvas.getContext('webgpu');
    if (!ctx) {
      return { Left: "Could not get WebGPU context" };
    }
    ctx.configure({ device, ...config });
    return { Right: ctx };
  } catch (err) {
    return { Left: err.message };
  }
};

export const getQueueImpl = device => () => device.queue;

// ─────────────────────────────────────────────────────────────────────────────
// DEVICE INFO
// ─────────────────────────────────────────────────────────────────────────────

export const getLimitsImpl = device => () => device.limits;

export const getFeaturesImpl = device => () => Array.from(device.features);

// ─────────────────────────────────────────────────────────────────────────────
// ERROR HANDLING
// ─────────────────────────────────────────────────────────────────────────────

export const onUncapturedErrorImpl = device => callback => () => {
  device.addEventListener('uncapturederror', event => {
    callback(event.error)();
  });
};

export const onDeviceLostImpl = device => callback => () => {
  device.lost.then(info => callback(info.reason)());
};

// ─────────────────────────────────────────────────────────────────────────────
// CANVAS OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const getCurrentTextureImpl = ctx => () => ctx.getCurrentTexture();

export const getPreferredCanvasFormatImpl = () => 
  navigator.gpu.getPreferredCanvasFormat();

// ─────────────────────────────────────────────────────────────────────────────
// BUFFER OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createBufferImpl = device => desc => () => 
  device.createBuffer(desc);

export const destroyBufferImpl = buffer => () => buffer.destroy();

export const writeBufferImpl = queue => buffer => offset => data => dataOffset => size => () => {
  if (size === 0) {
    queue.writeBuffer(buffer, offset, data);
  } else {
    queue.writeBuffer(buffer, offset, data, dataOffset, size);
  }
};

export const mapBufferAsyncImpl = buffer => mode => offset => size => onSuccess => onError => () => {
  buffer.mapAsync(mode, offset, size).then(
    () => onSuccess({})(),
    err => onError(err.message)()
  );
};

export const unmapBufferImpl = buffer => () => buffer.unmap();

export const getMappedRangeImpl = buffer => offset => size => () => 
  buffer.getMappedRange(offset, size);

// ─────────────────────────────────────────────────────────────────────────────
// TEXTURE OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createTextureImpl = device => desc => () => 
  device.createTexture(desc);

export const destroyTextureImpl = texture => () => texture.destroy();

export const createTextureViewImpl = texture => desc => () => 
  texture.createView(desc);

export const writeTextureImpl = queue => dest => data => dataLayout => size => () => {
  queue.writeTexture(dest, data, dataLayout, size);
};

// ─────────────────────────────────────────────────────────────────────────────
// SAMPLER OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createSamplerImpl = device => desc => () => 
  device.createSampler(desc);

// ─────────────────────────────────────────────────────────────────────────────
// SHADER OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createShaderModuleImpl = device => desc => () => 
  device.createShaderModule(desc);

// ─────────────────────────────────────────────────────────────────────────────
// PIPELINE OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createRenderPipelineImpl = device => desc => () => 
  device.createRenderPipeline(desc);

export const createComputePipelineImpl = device => desc => () => 
  device.createComputePipeline(desc);

export const createBindGroupLayoutImpl = device => desc => () => 
  device.createBindGroupLayout(desc);

export const createPipelineLayoutImpl = device => desc => () => 
  device.createPipelineLayout(desc);

// ─────────────────────────────────────────────────────────────────────────────
// BIND GROUP OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const createBindGroupImpl = device => desc => () => 
  device.createBindGroup(desc);

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND ENCODING
// ─────────────────────────────────────────────────────────────────────────────

export const createCommandEncoderImpl = device => () => 
  device.createCommandEncoder();

export const finishCommandEncoderImpl = encoder => () => 
  encoder.finish();

export const beginRenderPassImpl = encoder => desc => () => 
  encoder.beginRenderPass(desc);

export const endRenderPassImpl = pass => () => pass.end();

export const beginComputePassImpl = encoder => () => 
  encoder.beginComputePass();

export const endComputePassImpl = pass => () => pass.end();

// ─────────────────────────────────────────────────────────────────────────────
// RENDER PASS OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const setPipelineImpl = pass => pipeline => () => 
  pass.setPipeline(pipeline);

export const setBindGroupImpl = pass => index => bindGroup => () => 
  pass.setBindGroup(index, bindGroup);

export const setVertexBufferImpl = pass => slot => buffer => offset => size => () => {
  if (size === 0) {
    pass.setVertexBuffer(slot, buffer, offset);
  } else {
    pass.setVertexBuffer(slot, buffer, offset, size);
  }
};

export const setIndexBufferImpl = pass => buffer => format => offset => size => () => {
  if (size === 0) {
    pass.setIndexBuffer(buffer, format, offset);
  } else {
    pass.setIndexBuffer(buffer, format, offset, size);
  }
};

export const drawImpl = pass => vertexCount => instanceCount => firstVertex => firstInstance => () => 
  pass.draw(vertexCount, instanceCount, firstVertex, firstInstance);

export const drawIndexedImpl = pass => indexCount => instanceCount => firstIndex => baseVertex => firstInstance => () => 
  pass.drawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);

export const drawIndirectImpl = pass => buffer => offset => () => 
  pass.drawIndirect(buffer, offset);

export const setViewportImpl = pass => x => y => width => height => minDepth => maxDepth => () => 
  pass.setViewport(x, y, width, height, minDepth, maxDepth);

export const setScissorRectImpl = pass => x => y => width => height => () => 
  pass.setScissorRect(x, y, width, height);

// ─────────────────────────────────────────────────────────────────────────────
// QUEUE OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const submitImpl = queue => commandBuffers => () => 
  queue.submit(commandBuffers);

// ─────────────────────────────────────────────────────────────────────────────
// FOREIGN CONVERSION HELPERS
// ─────────────────────────────────────────────────────────────────────────────

export const toForeignAdapterDesc = desc => ({
  powerPreference: desc.powerPreference?.value0 === "LowPower" ? "low-power" : 
                   desc.powerPreference?.value0 === "HighPerformance" ? "high-performance" : undefined,
  forceFallbackAdapter: desc.forceFallbackAdapter
});

export const toForeignDeviceDesc = desc => ({
  requiredFeatures: desc.requiredFeatures,
  label: desc.label?.value0
});

export const toForeignCanvasConfig = config => ({
  format: textureFormatToString(config.format),
  usage: config.usage.reduce((acc, u) => acc | usageToInt(u), 0),
  viewFormats: config.viewFormats.map(textureFormatToString),
  colorSpace: config.colorSpace,
  alphaMode: config.alphaMode.constructor?.name === "AlphaOpaque" ? "opaque" : "premultiplied"
});

export const toForeignBufferDesc = desc => ({
  size: desc.size,
  usage: desc.usage.reduce((acc, u) => acc | bufferUsageToInt(u), 0),
  mappedAtCreation: desc.mappedAtCreation,
  label: desc.label?.value0
});

export const toForeignTextureDesc = desc => ({
  size: desc.size,
  mipLevelCount: desc.mipLevelCount,
  sampleCount: desc.sampleCount,
  dimension: dimensionToString(desc.dimension),
  format: textureFormatToString(desc.format),
  usage: desc.usage.reduce((acc, u) => acc | textureUsageToInt(u), 0),
  viewFormats: desc.viewFormats.map(textureFormatToString),
  label: desc.label?.value0
});

export const toForeignSamplerDesc = desc => ({
  addressModeU: addressModeToString(desc.addressModeU),
  addressModeV: addressModeToString(desc.addressModeV),
  addressModeW: addressModeToString(desc.addressModeW),
  magFilter: filterModeToString(desc.magFilter),
  minFilter: filterModeToString(desc.minFilter),
  mipmapFilter: mipmapFilterToString(desc.mipmapFilter),
  lodMinClamp: desc.lodMinClamp,
  lodMaxClamp: desc.lodMaxClamp,
  compare: desc.compare?.value0 ? compareFunctionToString(desc.compare.value0) : undefined,
  maxAnisotropy: desc.maxAnisotropy,
  label: desc.label?.value0
});

export const toForeignShaderDesc = desc => ({
  code: desc.code.value0, // Unwrap WGSLSource newtype
  label: desc.label?.value0
});

export const toForeignTextureDest = texture => ({ texture });

export const toForeignDataLayout = size => ({
  bytesPerRow: size.width * 4, // Assuming RGBA8
  rowsPerImage: size.height
});

export const toForeignSize = size => ({
  width: size.width,
  height: size.height
});

export const toForeignRenderPassDesc = desc => colorView => depthView => ({
  colorAttachments: desc.colorAttachments.map((att, i) => ({
    view: i === 0 ? colorView : colorView, // Use provided view
    loadOp: att.loadOp.constructor?.name === "LoadOpLoad" ? "load" : "clear",
    storeOp: att.storeOp.constructor?.name === "StoreOpStore" ? "store" : "discard",
    clearValue: att.clearValue
  })),
  depthStencilAttachment: depthView?.value0 ? {
    view: depthView.value0,
    depthLoadOp: desc.depthStencilAttachment?.value0?.depthLoadOp?.value0 ? 
      (desc.depthStencilAttachment.value0.depthLoadOp.value0.constructor?.name === "LoadOpLoad" ? "load" : "clear") : "clear",
    depthStoreOp: "store",
    depthClearValue: desc.depthStencilAttachment?.value0?.depthClearValue ?? 1.0
  } : undefined,
  label: desc.label?.value0
});

export const fromForeignLimits = limits => limits; // Pass through as-is

// Helper functions
function bufferUsageToInt(usage) {
  const map = {
    MapRead: 0x0001,
    MapWrite: 0x0002,
    CopySrc: 0x0004,
    CopyDst: 0x0008,
    Index: 0x0010,
    Vertex: 0x0020,
    Uniform: 0x0040,
    Storage: 0x0080,
    Indirect: 0x0100,
    QueryResolve: 0x0200
  };
  return map[usage.constructor?.name] || 0;
}

function textureUsageToInt(usage) {
  const map = {
    TextureCopySrc: 0x01,
    TextureCopyDst: 0x02,
    TextureBinding: 0x04,
    StorageBinding: 0x08,
    RenderAttachment: 0x10
  };
  return map[usage.constructor?.name] || 0;
}

function usageToInt(usage) {
  return textureUsageToInt(usage);
}

function textureFormatToString(format) {
  const name = format.constructor?.name || format;
  const map = {
    R8Unorm: "r8unorm",
    R8Snorm: "r8snorm",
    R8Uint: "r8uint",
    R8Sint: "r8sint",
    R16Uint: "r16uint",
    R16Sint: "r16sint",
    R16Float: "r16float",
    RG8Unorm: "rg8unorm",
    RG8Snorm: "rg8snorm",
    RG8Uint: "rg8uint",
    RG8Sint: "rg8sint",
    R32Uint: "r32uint",
    R32Sint: "r32sint",
    R32Float: "r32float",
    RG16Uint: "rg16uint",
    RG16Sint: "rg16sint",
    RG16Float: "rg16float",
    RGBA8Unorm: "rgba8unorm",
    RGBA8UnormSrgb: "rgba8unorm-srgb",
    RGBA8Snorm: "rgba8snorm",
    RGBA8Uint: "rgba8uint",
    RGBA8Sint: "rgba8sint",
    BGRA8Unorm: "bgra8unorm",
    BGRA8UnormSrgb: "bgra8unorm-srgb",
    RGB9E5Ufloat: "rgb9e5ufloat",
    RGB10A2Uint: "rgb10a2uint",
    RGB10A2Unorm: "rgb10a2unorm",
    RG11B10Ufloat: "rg11b10ufloat",
    RG32Uint: "rg32uint",
    RG32Sint: "rg32sint",
    RG32Float: "rg32float",
    RGBA16Uint: "rgba16uint",
    RGBA16Sint: "rgba16sint",
    RGBA16Float: "rgba16float",
    RGBA32Uint: "rgba32uint",
    RGBA32Sint: "rgba32sint",
    RGBA32Float: "rgba32float",
    Stencil8: "stencil8",
    Depth16Unorm: "depth16unorm",
    Depth24Plus: "depth24plus",
    Depth24PlusStencil8: "depth24plus-stencil8",
    Depth32Float: "depth32float",
    Depth32FloatStencil8: "depth32float-stencil8"
  };
  return map[name] || "bgra8unorm";
}

function dimensionToString(dim) {
  const name = dim.constructor?.name;
  return name === "Dimension1D" ? "1d" : name === "Dimension3D" ? "3d" : "2d";
}

function addressModeToString(mode) {
  const name = mode.constructor?.name;
  return name === "ClampToEdge" ? "clamp-to-edge" : 
         name === "Repeat" ? "repeat" : "mirror-repeat";
}

function filterModeToString(mode) {
  return mode.constructor?.name === "FilterNearest" ? "nearest" : "linear";
}

function mipmapFilterToString(mode) {
  return mode.constructor?.name === "MipmapNearest" ? "nearest" : "linear";
}

function compareFunctionToString(fn) {
  const map = {
    CompareNever: "never",
    CompareLess: "less",
    CompareEqual: "equal",
    CompareLessEqual: "less-equal",
    CompareGreater: "greater",
    CompareNotEqual: "not-equal",
    CompareGreaterEqual: "greater-equal",
    CompareAlways: "always"
  };
  return map[fn.constructor?.name] || "always";
}
