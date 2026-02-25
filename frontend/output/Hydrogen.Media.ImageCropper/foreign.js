// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                    // hydrogen // imagecropper
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Image cropping system with zoom, rotate, and touch gesture support

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // cropper state
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize image cropper
 * @param {Element} container - Container element
 * @param {Object} callbacks - Event callbacks
 * @param {Object} options - Configuration options
 * @returns {Object} Cropper controller
 */
export const initCropperImpl = (container) => (callbacks) => (options) => () => {
  const { aspectRatio, cropShape, minZoom, maxZoom, restrictPosition } = options;
  
  const image = container.querySelector('.cropper-image');
  const cropArea = container.querySelector('[data-crop-area]');
  
  if (!image || !cropArea) {
    console.warn('ImageCropper: Missing image or crop area element');
    return { destroy: () => {} };
  }
  
  // State
  let zoom = 1;
  let rotation = 0;
  let flipH = false;
  let flipV = false;
  let cropX = 0;
  let cropY = 0;
  let cropWidth = 200;
  let cropHeight = aspectRatio > 0 ? 200 / aspectRatio : 200;
  let isDragging = false;
  let isResizing = false;
  let resizeHandle = null;
  let startX = 0;
  let startY = 0;
  let startCropX = 0;
  let startCropY = 0;
  let startCropWidth = 0;
  let startCropHeight = 0;
  
  // Touch state for pinch-zoom
  let initialPinchDistance = 0;
  let initialZoom = 1;
  
  /**
   * Update crop area position and size
   */
  const updateCropArea = () => {
    cropArea.style.left = `${cropX}px`;
    cropArea.style.top = `${cropY}px`;
    cropArea.style.width = `${cropWidth}px`;
    cropArea.style.height = `${cropHeight}px`;
    
    callbacks.onCrop({
      area: { x: cropX, y: cropY, width: cropWidth, height: cropHeight },
      zoom: zoom,
      rotation: rotation
    })();
  };
  
  /**
   * Update image transform
   */
  const updateImageTransform = () => {
    const scaleX = flipH ? -zoom : zoom;
    const scaleY = flipV ? -zoom : zoom;
    image.style.transform = `scale(${scaleX}, ${scaleY}) rotate(${rotation}deg)`;
  };
  
  /**
   * Handle mouse down on crop area
   */
  const handleMouseDown = (e) => {
    e.preventDefault();
    
    const handle = e.target.closest('[data-handle]');
    if (handle) {
      // Resizing
      isResizing = true;
      resizeHandle = handle.dataset.handle;
    } else if (e.target.closest('[data-crop-area]')) {
      // Dragging
      isDragging = true;
    } else {
      return;
    }
    
    startX = e.clientX;
    startY = e.clientY;
    startCropX = cropX;
    startCropY = cropY;
    startCropWidth = cropWidth;
    startCropHeight = cropHeight;
    
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  };
  
  /**
   * Handle mouse move
   */
  const handleMouseMove = (e) => {
    const deltaX = e.clientX - startX;
    const deltaY = e.clientY - startY;
    
    if (isDragging) {
      cropX = startCropX + deltaX;
      cropY = startCropY + deltaY;
      
      if (restrictPosition) {
        const containerRect = container.getBoundingClientRect();
        cropX = Math.max(0, Math.min(containerRect.width - cropWidth, cropX));
        cropY = Math.max(0, Math.min(containerRect.height - cropHeight, cropY));
      }
    } else if (isResizing) {
      resizeCropArea(deltaX, deltaY);
    }
    
    updateCropArea();
  };
  
  /**
   * Resize crop area based on handle
   */
  const resizeCropArea = (deltaX, deltaY) => {
    const minSize = 50;
    
    switch (resizeHandle) {
      case 'nw':
        cropX = startCropX + deltaX;
        cropY = startCropY + deltaY;
        cropWidth = Math.max(minSize, startCropWidth - deltaX);
        cropHeight = aspectRatio > 0 ? cropWidth / aspectRatio : Math.max(minSize, startCropHeight - deltaY);
        break;
      case 'ne':
        cropY = startCropY + deltaY;
        cropWidth = Math.max(minSize, startCropWidth + deltaX);
        cropHeight = aspectRatio > 0 ? cropWidth / aspectRatio : Math.max(minSize, startCropHeight - deltaY);
        break;
      case 'sw':
        cropX = startCropX + deltaX;
        cropWidth = Math.max(minSize, startCropWidth - deltaX);
        cropHeight = aspectRatio > 0 ? cropWidth / aspectRatio : Math.max(minSize, startCropHeight + deltaY);
        break;
      case 'se':
        cropWidth = Math.max(minSize, startCropWidth + deltaX);
        cropHeight = aspectRatio > 0 ? cropWidth / aspectRatio : Math.max(minSize, startCropHeight + deltaY);
        break;
      case 'n':
        cropY = startCropY + deltaY;
        cropHeight = Math.max(minSize, startCropHeight - deltaY);
        if (aspectRatio > 0) cropWidth = cropHeight * aspectRatio;
        break;
      case 's':
        cropHeight = Math.max(minSize, startCropHeight + deltaY);
        if (aspectRatio > 0) cropWidth = cropHeight * aspectRatio;
        break;
      case 'e':
        cropWidth = Math.max(minSize, startCropWidth + deltaX);
        if (aspectRatio > 0) cropHeight = cropWidth / aspectRatio;
        break;
      case 'w':
        cropX = startCropX + deltaX;
        cropWidth = Math.max(minSize, startCropWidth - deltaX);
        if (aspectRatio > 0) cropHeight = cropWidth / aspectRatio;
        break;
    }
  };
  
  /**
   * Handle mouse up
   */
  const handleMouseUp = () => {
    isDragging = false;
    isResizing = false;
    resizeHandle = null;
    
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
  };
  
  /**
   * Handle touch start
   */
  const handleTouchStart = (e) => {
    if (e.touches.length === 2) {
      // Pinch zoom
      initialPinchDistance = getPinchDistance(e.touches);
      initialZoom = zoom;
      return;
    }
    
    if (e.touches.length === 1) {
      const touch = e.touches[0];
      const handle = document.elementFromPoint(touch.clientX, touch.clientY)?.closest('[data-handle]');
      
      if (handle) {
        isResizing = true;
        resizeHandle = handle.dataset.handle;
      } else {
        isDragging = true;
      }
      
      startX = touch.clientX;
      startY = touch.clientY;
      startCropX = cropX;
      startCropY = cropY;
      startCropWidth = cropWidth;
      startCropHeight = cropHeight;
    }
  };
  
  /**
   * Handle touch move
   */
  const handleTouchMove = (e) => {
    e.preventDefault();
    
    if (e.touches.length === 2) {
      // Pinch zoom
      const newDistance = getPinchDistance(e.touches);
      const scale = newDistance / initialPinchDistance;
      zoom = Math.max(minZoom, Math.min(maxZoom, initialZoom * scale));
      updateImageTransform();
      callbacks.onZoomChange(zoom)();
      return;
    }
    
    if (e.touches.length === 1) {
      const touch = e.touches[0];
      const deltaX = touch.clientX - startX;
      const deltaY = touch.clientY - startY;
      
      if (isDragging) {
        cropX = startCropX + deltaX;
        cropY = startCropY + deltaY;
      } else if (isResizing) {
        resizeCropArea(deltaX, deltaY);
      }
      
      updateCropArea();
    }
  };
  
  /**
   * Handle touch end
   */
  const handleTouchEnd = () => {
    isDragging = false;
    isResizing = false;
    resizeHandle = null;
    initialPinchDistance = 0;
  };
  
  /**
   * Get distance between two touch points
   */
  const getPinchDistance = (touches) => {
    const dx = touches[0].clientX - touches[1].clientX;
    const dy = touches[0].clientY - touches[1].clientY;
    return Math.sqrt(dx * dx + dy * dy);
  };
  
  /**
   * Handle wheel for zoom
   */
  const handleWheel = (e) => {
    e.preventDefault();
    
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    zoom = Math.max(minZoom, Math.min(maxZoom, zoom + delta));
    
    updateImageTransform();
    callbacks.onZoomChange(zoom)();
  };
  
  /**
   * Handle keyboard controls
   */
  const handleKeyDown = (e) => {
    const step = e.shiftKey ? 10 : 1;
    
    switch (e.key) {
      case 'ArrowLeft':
        e.preventDefault();
        cropX -= step;
        break;
      case 'ArrowRight':
        e.preventDefault();
        cropX += step;
        break;
      case 'ArrowUp':
        e.preventDefault();
        cropY -= step;
        break;
      case 'ArrowDown':
        e.preventDefault();
        cropY += step;
        break;
      case '+':
      case '=':
        e.preventDefault();
        zoom = Math.min(maxZoom, zoom + 0.1);
        updateImageTransform();
        callbacks.onZoomChange(zoom)();
        break;
      case '-':
        e.preventDefault();
        zoom = Math.max(minZoom, zoom - 0.1);
        updateImageTransform();
        callbacks.onZoomChange(zoom)();
        break;
      case 'r':
      case 'R':
        e.preventDefault();
        rotation = (rotation + 90) % 360;
        updateImageTransform();
        callbacks.onRotationChange(rotation)();
        break;
      case 'Escape':
        e.preventDefault();
        // Reset
        zoom = 1;
        rotation = 0;
        updateImageTransform();
        break;
      default:
        return;
    }
    
    updateCropArea();
  };
  
  /**
   * Handle image load
   */
  const handleImageLoad = () => {
    // Center crop area
    const containerRect = container.getBoundingClientRect();
    const imgRect = image.getBoundingClientRect();
    
    cropWidth = Math.min(200, imgRect.width * 0.8);
    cropHeight = aspectRatio > 0 ? cropWidth / aspectRatio : Math.min(200, imgRect.height * 0.8);
    cropX = (containerRect.width - cropWidth) / 2;
    cropY = (containerRect.height - cropHeight) / 2;
    
    updateCropArea();
    
    callbacks.onImageLoad({
      naturalWidth: image.naturalWidth,
      naturalHeight: image.naturalHeight,
      src: image.src
    })();
  };
  
  /**
   * Handle image error
   */
  const handleImageError = () => {
    callbacks.onImageError('Failed to load image')();
  };
  
  // Attach event listeners
  container.addEventListener('mousedown', handleMouseDown);
  container.addEventListener('touchstart', handleTouchStart, { passive: false });
  container.addEventListener('touchmove', handleTouchMove, { passive: false });
  container.addEventListener('touchend', handleTouchEnd);
  container.addEventListener('wheel', handleWheel, { passive: false });
  container.addEventListener('keydown', handleKeyDown);
  image.addEventListener('load', handleImageLoad);
  image.addEventListener('error', handleImageError);
  
  // Initialize if image already loaded
  if (image.complete) {
    handleImageLoad();
  }
  
  return {
    container,
    image,
    cropArea,
    getState: () => ({ zoom, rotation, flipH, flipV, cropX, cropY, cropWidth, cropHeight }),
    setZoom: (z) => {
      zoom = Math.max(minZoom, Math.min(maxZoom, z));
      updateImageTransform();
    },
    setRotation: (r) => {
      rotation = r % 360;
      updateImageTransform();
    },
    flipHorizontal: () => {
      flipH = !flipH;
      updateImageTransform();
    },
    flipVertical: () => {
      flipV = !flipV;
      updateImageTransform();
    },
    reset: () => {
      zoom = 1;
      rotation = 0;
      flipH = false;
      flipV = false;
      updateImageTransform();
      handleImageLoad();
    },
    destroy: () => {
      container.removeEventListener('mousedown', handleMouseDown);
      container.removeEventListener('touchstart', handleTouchStart);
      container.removeEventListener('touchmove', handleTouchMove);
      container.removeEventListener('touchend', handleTouchEnd);
      container.removeEventListener('wheel', handleWheel);
      container.removeEventListener('keydown', handleKeyDown);
      image.removeEventListener('load', handleImageLoad);
      image.removeEventListener('error', handleImageError);
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    }
  };
};

/**
 * Destroy cropper instance
 */
export const destroyCropperImpl = (cropper) => () => {
  if (cropper && cropper.destroy) {
    cropper.destroy();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // crop operations
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get cropped image as canvas
 */
export const getCroppedCanvasImpl = (cropper) => (options) => () => {
  const { width, height } = options;
  const state = cropper.getState();
  const image = cropper.image;
  
  const canvas = document.createElement('canvas');
  canvas.width = width || state.cropWidth;
  canvas.height = height || state.cropHeight;
  
  const ctx = canvas.getContext('2d');
  
  // Apply transformations
  ctx.translate(canvas.width / 2, canvas.height / 2);
  ctx.rotate((state.rotation * Math.PI) / 180);
  ctx.scale(state.flipH ? -1 : 1, state.flipV ? -1 : 1);
  ctx.translate(-canvas.width / 2, -canvas.height / 2);
  
  // Calculate source coordinates
  const scaleX = image.naturalWidth / image.width;
  const scaleY = image.naturalHeight / image.height;
  
  const sx = state.cropX * scaleX;
  const sy = state.cropY * scaleY;
  const sw = state.cropWidth * scaleX;
  const sh = state.cropHeight * scaleY;
  
  ctx.drawImage(image, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
  
  return canvas;
};

/**
 * Get cropped image as Blob
 */
export const getCroppedBlobImpl = (cropper) => (options) => (onComplete) => () => {
  const { format, quality } = options;
  const canvas = getCroppedCanvasImpl(cropper)({ width: 0, height: 0 })();
  
  const mimeType = format === 'png' ? 'image/png' 
    : format === 'webp' ? 'image/webp' 
    : 'image/jpeg';
  
  canvas.toBlob((blob) => {
    onComplete(blob)();
  }, mimeType, quality);
};

/**
 * Get cropped image as DataURL
 */
export const getCroppedDataUrlImpl = (cropper) => (options) => () => {
  const { format, quality } = options;
  const canvas = getCroppedCanvasImpl(cropper)({ width: 0, height: 0 })();
  
  const mimeType = format === 'png' ? 'image/png' 
    : format === 'webp' ? 'image/webp' 
    : 'image/jpeg';
  
  return canvas.toDataURL(mimeType, quality);
};

/**
 * Set zoom level
 */
export const setZoomImpl = (cropper) => (zoom) => () => {
  if (cropper && cropper.setZoom) {
    cropper.setZoom(zoom);
  }
};

/**
 * Set rotation angle
 */
export const setRotationImpl = (cropper) => (rotation) => () => {
  if (cropper && cropper.setRotation) {
    cropper.setRotation(rotation);
  }
};

/**
 * Flip horizontal
 */
export const flipHorizontalImpl = (cropper) => () => {
  if (cropper && cropper.flipHorizontal) {
    cropper.flipHorizontal();
  }
};

/**
 * Flip vertical
 */
export const flipVerticalImpl = (cropper) => () => {
  if (cropper && cropper.flipVertical) {
    cropper.flipVertical();
  }
};

/**
 * Reset cropper to initial state
 */
export const resetCropperImpl = (cropper) => () => {
  if (cropper && cropper.reset) {
    cropper.reset();
  }
};

/**
 * Load image from File object
 */
export const loadImageFromFileImpl = (cropper) => (file) => () => {
  if (!cropper || !cropper.image) return;
  
  const reader = new FileReader();
  reader.onload = (e) => {
    cropper.image.src = e.target.result;
  };
  reader.readAsDataURL(file);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Unsafe cropper element placeholder
 */
export const unsafeCropperElement = {
  container: null,
  image: null,
  cropArea: null,
  getState: () => ({
    zoom: 1,
    rotation: 0,
    flipH: false,
    flipV: false,
    cropX: 0,
    cropY: 0,
    cropWidth: 200,
    cropHeight: 200
  }),
  setZoom: () => {},
  setRotation: () => {},
  flipHorizontal: () => {},
  flipVertical: () => {},
  reset: () => {},
  destroy: () => {}
};

/**
 * Unsafe Foreign placeholder
 */
export const unsafeForeign = null;

/**
 * Unsafe canvas placeholder
 */
export const unsafeCanvas = null;

/**
 * Convert Int to Number
 */
export const toNumberImpl = (n) => n;

/**
 * Convert Number to Int
 */
export const toIntImpl = (n) => Math.round(n);

/**
 * Generate array range [start, end]
 */
export const rangeImpl = (start) => (end) => {
  if (end < start) return [];
  const result = [];
  for (let i = start; i <= end; i++) {
    result.push(i);
  }
  return result;
};
