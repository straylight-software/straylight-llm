// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // gallery
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Image gallery with lightbox, zoom/pan, touch gestures, and keyboard navigation

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

// ═══════════════════════════════════════════════════════════════════════════════
//                                                      // gallery initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize gallery
 */
export const initGalleryImpl = (containerId, config) => {
  const container = document.getElementById(containerId);
  if (!container) return null;

  let state = {
    currentIndex: 0,
    zoom: 1,
    panX: 0,
    panY: 0,
    isDragging: false,
    startX: 0,
    startY: 0,
    lastPanX: 0,
    lastPanY: 0,
    slideshowTimer: null,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                            // thumbnail clicks
  // ─────────────────────────────────────────────────────────────────────────────

  const handleThumbnailClick = (e) => {
    const item = e.target.closest(".gallery-item");
    if (!item) return;

    const index = parseInt(item.dataset.index, 10);
    if (!isNaN(index)) {
      config.onImageClick(index)();
    }
  };

  container.addEventListener("click", handleThumbnailClick);

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                           // keyboard controls
  // ─────────────────────────────────────────────────────────────────────────────

  const handleKeyDown = (e) => {
    if (!config.enableKeyboard) return;

    const lightbox = container.querySelector(".lightbox");
    if (!lightbox) return;

    switch (e.key) {
      case "Escape":
        e.preventDefault();
        config.onLightboxClose();
        break;

      case "ArrowLeft":
        e.preventDefault();
        config.onImageChange(state.currentIndex - 1)();
        break;

      case "ArrowRight":
        e.preventDefault();
        config.onImageChange(state.currentIndex + 1)();
        break;

      case "+":
      case "=":
        if (config.enableZoom) {
          e.preventDefault();
          state.zoom = clamp(state.zoom * 1.5, 1, 4);
          updateTransform();
        }
        break;

      case "-":
        if (config.enableZoom) {
          e.preventDefault();
          state.zoom = clamp(state.zoom / 1.5, 1, 4);
          if (state.zoom === 1) {
            state.panX = 0;
            state.panY = 0;
          }
          updateTransform();
        }
        break;

      case "0":
        if (config.enableZoom) {
          e.preventDefault();
          state.zoom = 1;
          state.panX = 0;
          state.panY = 0;
          updateTransform();
        }
        break;
    }
  };

  document.addEventListener("keydown", handleKeyDown);

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                  // transform
  // ─────────────────────────────────────────────────────────────────────────────

  const updateTransform = () => {
    const img = container.querySelector(".lightbox img");
    if (!img) return;

    img.style.transform = `scale(${state.zoom}) translate(${state.panX}px, ${state.panY}px)`;
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                   // cleanup
  // ─────────────────────────────────────────────────────────────────────────────

  return {
    container,
    state,
    updateTransform,
    destroy: () => {
      container.removeEventListener("click", handleThumbnailClick);
      document.removeEventListener("keydown", handleKeyDown);
      if (state.slideshowTimer) {
        clearInterval(state.slideshowTimer);
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // touch gestures
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup touch gestures for lightbox
 */
export const setupGesturesImpl = (gallery) => {
  if (!gallery?.container) return;

  const lightbox = gallery.container.querySelector(".lightbox");
  if (!lightbox) return;

  let state = gallery.state;
  let touchStartX = 0;
  let touchStartY = 0;
  let initialDistance = 0;
  let initialZoom = 1;

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                    // swipe
  // ─────────────────────────────────────────────────────────────────────────────

  const handleTouchStart = (e) => {
    if (e.touches.length === 1) {
      touchStartX = e.touches[0].clientX;
      touchStartY = e.touches[0].clientY;
      state.isDragging = state.zoom > 1;
      state.startX = state.panX;
      state.startY = state.panY;
    } else if (e.touches.length === 2) {
      // Pinch start
      const dx = e.touches[0].clientX - e.touches[1].clientX;
      const dy = e.touches[0].clientY - e.touches[1].clientY;
      initialDistance = Math.sqrt(dx * dx + dy * dy);
      initialZoom = state.zoom;
    }
  };

  const handleTouchMove = (e) => {
    if (e.touches.length === 1 && state.zoom === 1) {
      // Swipe detection for navigation
      return;
    }

    if (e.touches.length === 1 && state.isDragging) {
      // Pan when zoomed
      e.preventDefault();
      const deltaX = e.touches[0].clientX - touchStartX;
      const deltaY = e.touches[0].clientY - touchStartY;
      state.panX = state.startX + deltaX / state.zoom;
      state.panY = state.startY + deltaY / state.zoom;
      gallery.updateTransform();
    } else if (e.touches.length === 2) {
      // Pinch zoom
      e.preventDefault();
      const dx = e.touches[0].clientX - e.touches[1].clientX;
      const dy = e.touches[0].clientY - e.touches[1].clientY;
      const distance = Math.sqrt(dx * dx + dy * dy);
      const scale = distance / initialDistance;
      state.zoom = clamp(initialZoom * scale, 1, 4);
      
      if (state.zoom === 1) {
        state.panX = 0;
        state.panY = 0;
      }
      
      gallery.updateTransform();
    }
  };

  const handleTouchEnd = (e) => {
    if (state.zoom === 1 && e.changedTouches.length === 1) {
      // Check for swipe
      const deltaX = e.changedTouches[0].clientX - touchStartX;
      const deltaY = e.changedTouches[0].clientY - touchStartY;
      
      if (Math.abs(deltaX) > 50 && Math.abs(deltaY) < 100) {
        if (deltaX > 0) {
          // Swipe right - previous
          lightbox.dispatchEvent(new CustomEvent("gallery:prev"));
        } else {
          // Swipe left - next
          lightbox.dispatchEvent(new CustomEvent("gallery:next"));
        }
      }
    }
    
    state.isDragging = false;
  };

  lightbox.addEventListener("touchstart", handleTouchStart, { passive: true });
  lightbox.addEventListener("touchmove", handleTouchMove, { passive: false });
  lightbox.addEventListener("touchend", handleTouchEnd, { passive: true });

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                              // wheel zoom
  // ─────────────────────────────────────────────────────────────────────────────

  const handleWheel = (e) => {
    e.preventDefault();
    
    const delta = e.deltaY > 0 ? 0.9 : 1.1;
    state.zoom = clamp(state.zoom * delta, 1, 4);
    
    if (state.zoom === 1) {
      state.panX = 0;
      state.panY = 0;
    }
    
    gallery.updateTransform();
  };

  lightbox.addEventListener("wheel", handleWheel, { passive: false });

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                               // mouse drag
  // ─────────────────────────────────────────────────────────────────────────────

  const handleMouseDown = (e) => {
    if (state.zoom <= 1) return;
    
    state.isDragging = true;
    state.startX = state.panX;
    state.startY = state.panY;
    touchStartX = e.clientX;
    touchStartY = e.clientY;
    e.target.style.cursor = "grabbing";
  };

  const handleMouseMove = (e) => {
    if (!state.isDragging) return;
    
    const deltaX = e.clientX - touchStartX;
    const deltaY = e.clientY - touchStartY;
    state.panX = state.startX + deltaX / state.zoom;
    state.panY = state.startY + deltaY / state.zoom;
    gallery.updateTransform();
  };

  const handleMouseUp = (e) => {
    state.isDragging = false;
    if (e.target) {
      e.target.style.cursor = state.zoom > 1 ? "grab" : "";
    }
  };

  lightbox.addEventListener("mousedown", handleMouseDown);
  lightbox.addEventListener("mousemove", handleMouseMove);
  lightbox.addEventListener("mouseup", handleMouseUp);
  lightbox.addEventListener("mouseleave", handleMouseUp);

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                             // double click
  // ─────────────────────────────────────────────────────────────────────────────

  const handleDoubleClick = (e) => {
    if (state.zoom > 1) {
      // Reset zoom
      state.zoom = 1;
      state.panX = 0;
      state.panY = 0;
    } else {
      // Zoom to 2x at click position
      const rect = e.target.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;
      state.zoom = 2;
      state.panX = -x / 2;
      state.panY = -y / 2;
    }
    gallery.updateTransform();
  };

  lightbox.addEventListener("dblclick", handleDoubleClick);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // zoom/pan
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Set zoom level
 */
export const setZoomImpl = (gallery, zoom) => {
  if (!gallery?.state) return;
  
  gallery.state.zoom = clamp(zoom, 1, 4);
  if (gallery.state.zoom === 1) {
    gallery.state.panX = 0;
    gallery.state.panY = 0;
  }
  gallery.updateTransform();
};

/**
 * Set pan position
 */
export const setPanImpl = (gallery, position) => {
  if (!gallery?.state) return;
  
  gallery.state.panX = position.x;
  gallery.state.panY = position.y;
  gallery.updateTransform();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // download/share
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Download image
 */
export const downloadImageImpl = (url) => {
  const link = document.createElement("a");
  link.href = url;
  link.download = url.split("/").pop() || "image";
  link.target = "_blank";
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};

/**
 * Share image using Web Share API
 */
export const shareImageImpl = async (data) => {
  if (!navigator.share) {
    // Fallback: copy URL to clipboard
    try {
      await navigator.clipboard.writeText(data.url);
      alert("Link copied to clipboard!");
    } catch (err) {
      console.warn("Failed to copy:", err);
    }
    return;
  }

  try {
    await navigator.share({
      title: data.title,
      text: data.text,
      url: data.url,
    });
  } catch (err) {
    if (err.name !== "AbortError") {
      console.warn("Share failed:", err);
    }
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // slideshow
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Start slideshow
 */
export const startSlideshow = (gallery, interval, onNext) => () => {
  if (!gallery?.state) return;
  
  stopSlideshow(gallery)();
  
  gallery.state.slideshowTimer = setInterval(() => {
    onNext();
  }, interval);
};

/**
 * Stop slideshow
 */
export const stopSlideshow = (gallery) => () => {
  if (!gallery?.state) return;
  
  if (gallery.state.slideshowTimer) {
    clearInterval(gallery.state.slideshowTimer);
    gallery.state.slideshowTimer = null;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                 // lazy loading
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup intersection observer for lazy loading
 */
export const setupLazyLoading = (container) => () => {
  if (!("IntersectionObserver" in window)) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const img = entry.target;
          const src = img.dataset.src;
          if (src) {
            img.src = src;
            img.removeAttribute("data-src");
          }
          observer.unobserve(img);
        }
      });
    },
    {
      rootMargin: "100px",
      threshold: 0.1,
    }
  );

  const images = container.querySelectorAll("img[data-src]");
  images.forEach((img) => {
    observer.observe(img);
  });

  return {
    disconnect: () => observer.disconnect(),
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // image loading
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Preload adjacent images
 */
export const preloadImages = (images, currentIndex, count) => () => {
  const indicesToLoad = [];
  
  // Preload next images
  for (let i = 1; i <= count; i++) {
    const nextIndex = (currentIndex + i) % images.length;
    indicesToLoad.push(nextIndex);
  }
  
  // Preload previous images
  for (let i = 1; i <= count; i++) {
    const prevIndex = (currentIndex - i + images.length) % images.length;
    indicesToLoad.push(prevIndex);
  }

  indicesToLoad.forEach((index) => {
    const img = new Image();
    img.src = images[index].src;
  });
};

/**
 * Get image dimensions
 */
export const getImageDimensions = (url) => () => {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = reject;
    img.src = url;
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // cleanup
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Destroy gallery
 */
export const destroyGalleryImpl = (gallery) => {
  if (gallery?.destroy) {
    gallery.destroy();
  }
};
