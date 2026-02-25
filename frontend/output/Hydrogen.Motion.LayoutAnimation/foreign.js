// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                // hydrogen // layout-animation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Automatic layout animations using FLIP technique

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // FLIP animation
// ═══════════════════════════════════════════════════════════════════════════════

export const measureElement = (element) => () => {
  const rect = element.getBoundingClientRect();
  return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
    top: rect.top,
    left: rect.left,
    right: rect.right,
    bottom: rect.bottom,
  };
};

export const flipAnimateImpl = (element) => (first) => (last) => (config) => () => {
  // Calculate deltas (First - Last = Invert)
  const deltaX = first.left - last.left;
  const deltaY = first.top - last.top;
  const deltaW = first.width / last.width;
  const deltaH = first.height / last.height;
  
  // Apply inverse transform
  element.style.transformOrigin = "top left";
  element.style.transform = `translate(${deltaX}px, ${deltaY}px) scale(${deltaW}, ${deltaH})`;
  
  // Force reflow
  element.getBoundingClientRect();
  
  // Play animation (remove transform)
  element.style.transition = `transform ${config.duration}ms ${config.easing}`;
  element.style.transform = "";
  
  // Cleanup
  const cleanup = () => {
    element.style.transformOrigin = "";
    element.style.transition = "";
    element.removeEventListener("transitionend", cleanup);
  };
  
  element.addEventListener("transitionend", cleanup);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                           // layout controller
// ═══════════════════════════════════════════════════════════════════════════════

export const createLayoutControllerImpl = (element) => (config) => () => {
  const controller = {
    element,
    config,
    paused: false,
    rects: new Map(),
    
    // Store current positions
    snapshot: () => {
      const items = element.querySelectorAll("[data-layout-item]");
      for (const item of items) {
        const id = item.getAttribute("data-layout-item");
        controller.rects.set(id, item.getBoundingClientRect());
      }
    },
    
    // Animate from snapshot to current positions
    animate: () => {
      if (controller.paused) return;
      
      const items = element.querySelectorAll("[data-layout-item]");
      const stagger = parseFloat(element.getAttribute("data-layout-stagger")) || 0;
      let delay = 0;
      
      for (const item of items) {
        const id = item.getAttribute("data-layout-item");
        const first = controller.rects.get(id);
        
        if (!first) continue;
        
        const last = item.getBoundingClientRect();
        
        // Skip if no change
        if (first.left === last.left && first.top === last.top &&
            first.width === last.width && first.height === last.height) {
          continue;
        }
        
        const animatePosition = item.getAttribute("data-animate-position") !== "false";
        const animateSize = item.getAttribute("data-animate-size") !== "false";
        
        // Calculate deltas
        const deltaX = animatePosition ? first.left - last.left : 0;
        const deltaY = animatePosition ? first.top - last.top : 0;
        const deltaW = animateSize ? first.width / last.width : 1;
        const deltaH = animateSize ? first.height / last.height : 1;
        
        // Apply inverse transform
        item.style.transformOrigin = "top left";
        item.style.transform = `translate(${deltaX}px, ${deltaY}px) scale(${deltaW}, ${deltaH})`;
        
        // Animate with delay
        setTimeout(() => {
          item.style.transition = `transform ${config.duration}ms ${config.easing}`;
          item.style.transform = "";
          
          const cleanup = () => {
            item.style.transformOrigin = "";
            item.style.transition = "";
            item.removeEventListener("transitionend", cleanup);
          };
          
          item.addEventListener("transitionend", cleanup);
        }, delay);
        
        delay += stagger;
      }
    },
  };
  
  // Auto-animate on DOM changes
  const observer = new MutationObserver(() => {
    controller.snapshot();
    requestAnimationFrame(() => {
      controller.animate();
    });
  });
  
  observer.observe(element, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["class", "style"],
  });
  
  // Take initial snapshot
  controller.snapshot();
  
  return controller;
};

export const animateLayout = (controller) => () => {
  controller.snapshot();
  requestAnimationFrame(() => {
    controller.animate();
  });
};

export const forceLayout = (controller) => () => {
  controller.rects.clear();
};

export const pauseLayout = (controller) => () => {
  controller.paused = true;
};

export const resumeLayout = (controller) => () => {
  controller.paused = false;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                     // shared element animations
// ═══════════════════════════════════════════════════════════════════════════════

// Track shared elements across views
const sharedElements = new Map();

const initSharedElements = () => {
  const elements = document.querySelectorAll("[data-shared-element]");
  
  for (const element of elements) {
    const id = element.getAttribute("data-shared-element");
    const existing = sharedElements.get(id);
    
    if (existing && existing !== element) {
      // Animate transition between elements
      animateSharedTransition(existing, element);
    }
    
    sharedElements.set(id, element);
  }
};

const animateSharedTransition = (from, to) => {
  const transition = to.getAttribute("data-shared-transition") || "morph";
  const zIndex = parseInt(to.getAttribute("data-shared-zindex") || "1000", 10);
  
  // Get positions
  const fromRect = from.getBoundingClientRect();
  const toRect = to.getBoundingClientRect();
  
  // Create clone for animation
  const clone = from.cloneNode(true);
  clone.style.position = "fixed";
  clone.style.top = fromRect.top + "px";
  clone.style.left = fromRect.left + "px";
  clone.style.width = fromRect.width + "px";
  clone.style.height = fromRect.height + "px";
  clone.style.zIndex = zIndex;
  clone.style.pointerEvents = "none";
  clone.style.margin = "0";
  document.body.appendChild(clone);
  
  // Hide original elements during animation
  from.style.visibility = "hidden";
  to.style.visibility = "hidden";
  
  // Animate
  requestAnimationFrame(() => {
    clone.style.transition = "all 300ms ease-out";
    clone.style.top = toRect.top + "px";
    clone.style.left = toRect.left + "px";
    clone.style.width = toRect.width + "px";
    clone.style.height = toRect.height + "px";
    
    if (transition === "crossfade") {
      clone.style.opacity = "0";
    }
    
    const cleanup = () => {
      clone.remove();
      from.style.visibility = "";
      to.style.visibility = "";
      clone.removeEventListener("transitionend", cleanup);
    };
    
    clone.addEventListener("transitionend", cleanup);
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // crossfade
// ═══════════════════════════════════════════════════════════════════════════════

const initCrossfade = () => {
  const containers = document.querySelectorAll("[data-crossfade]");
  
  for (const container of containers) {
    if (container._crossfadeInitialized) continue;
    container._crossfadeInitialized = true;
    
    const duration = parseFloat(container.getAttribute("data-crossfade-duration")) || 300;
    
    // Observe for current changes
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.attributeName === "data-crossfade-current") {
          const current = container.getAttribute("data-crossfade-current");
          animateCrossfade(container, current, duration);
        }
      }
    });
    
    observer.observe(container, { attributes: true });
  }
};

const animateCrossfade = (container, current, duration) => {
  const items = container.querySelectorAll("[data-crossfade-key]");
  
  for (const item of items) {
    const key = item.getAttribute("data-crossfade-key");
    const isActive = key === current;
    
    if (isActive) {
      item.style.display = "";
      item.style.opacity = "0";
      item.style.transition = `opacity ${duration}ms ease-out`;
      requestAnimationFrame(() => {
        item.style.opacity = "1";
      });
    } else {
      item.style.transition = `opacity ${duration}ms ease-out`;
      item.style.opacity = "0";
      setTimeout(() => {
        if (item.getAttribute("data-crossfade-key") !== current) {
          item.style.display = "none";
        }
      }, duration);
    }
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // initialization
// ═══════════════════════════════════════════════════════════════════════════════

const initLayoutAnimations = () => {
  initSharedElements();
  initCrossfade();
  
  // Initialize layout roots
  const roots = document.querySelectorAll("[data-layout-root]");
  for (const root of roots) {
    if (root._layoutInitialized) continue;
    root._layoutInitialized = true;
    
    const duration = parseFloat(root.getAttribute("data-layout-duration")) || 300;
    const easing = root.getAttribute("data-layout-easing") || "ease-out";
    
    createLayoutControllerImpl(root)({ duration, easing })();
  }
};

// Auto-initialize when DOM is ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initLayoutAnimations);
  } else {
    initLayoutAnimations();
  }
  
  // Re-initialize on dynamic content
  const observer = new MutationObserver(() => {
    initLayoutAnimations();
  });
  
  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
  }
}
