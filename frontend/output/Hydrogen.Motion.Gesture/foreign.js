// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // hydrogen // gesture
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Unified gesture recognition for touch, mouse, and pointer events

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

const getPointerPosition = (event) => {
  if (event.touches && event.touches.length > 0) {
    return { x: event.touches[0].clientX, y: event.touches[0].clientY };
  }
  return { x: event.clientX, y: event.clientY };
};

const getTwoFingerData = (event) => {
  if (!event.touches || event.touches.length < 2) return null;
  const t1 = event.touches[0];
  const t2 = event.touches[1];
  const centerX = (t1.clientX + t2.clientX) / 2;
  const centerY = (t1.clientY + t2.clientY) / 2;
  const dx = t2.clientX - t1.clientX;
  const dy = t2.clientY - t1.clientY;
  const distance = Math.sqrt(dx * dx + dy * dy);
  const angle = Math.atan2(dy, dx) * (180 / Math.PI);
  return { centerX, centerY, distance, angle };
};

const now = () => performance.now();

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                 // pan gesture
// ═══════════════════════════════════════════════════════════════════════════════

export const createPanGestureImpl = (element) => (config) => () => {
  let state = "idle";
  let startX = 0, startY = 0;
  let currentX = 0, currentY = 0;
  let offsetX = 0, offsetY = 0;
  let velocityTracker = [];
  let lockedAxis = null;
  let enabled = true;

  const getVelocity = () => {
    if (velocityTracker.length < 2) return { vx: 0, vy: 0 };
    const recent = velocityTracker.slice(-5);
    const first = recent[0];
    const last = recent[recent.length - 1];
    const dt = (last.time - first.time) / 1000;
    if (dt === 0) return { vx: 0, vy: 0 };
    return {
      vx: (last.x - first.x) / dt,
      vy: (last.y - first.y) / dt,
    };
  };

  const buildState = () => {
    const vel = getVelocity();
    return {
      state,
      startX,
      startY,
      currentX,
      currentY,
      deltaX: currentX - startX,
      deltaY: currentY - startY,
      offsetX,
      offsetY,
      velocityX: vel.vx,
      velocityY: vel.vy,
    };
  };

  const onStart = (e) => {
    if (!enabled) return;
    const pos = getPointerPosition(e);
    startX = pos.x;
    startY = pos.y;
    currentX = pos.x;
    currentY = pos.y;
    velocityTracker = [{ x: pos.x, y: pos.y, time: now() }];
    lockedAxis = null;
    state = "idle";
  };

  const onMove = (e) => {
    if (!enabled || state === "ended") return;
    const pos = getPointerPosition(e);
    currentX = pos.x;
    currentY = pos.y;
    velocityTracker.push({ x: pos.x, y: pos.y, time: now() });
    if (velocityTracker.length > 10) velocityTracker.shift();

    const dx = Math.abs(currentX - startX);
    const dy = Math.abs(currentY - startY);
    const distance = Math.sqrt(dx * dx + dy * dy);

    if (state === "idle" && distance >= config.threshold) {
      state = "active";
      if (config.lockAxis) {
        lockedAxis = dx > dy ? "x" : "y";
      }
      config.onStart(buildState())();
    }

    if (state === "active") {
      if (config.preventScroll) {
        e.preventDefault();
      }
      config.onMove(buildState())();
    }
  };

  const onEnd = () => {
    if (!enabled || state !== "active") {
      state = "idle";
      return;
    }
    state = "ended";
    offsetX += currentX - startX;
    offsetY += currentY - startY;
    config.onEnd(buildState())();
    state = "idle";
  };

  // Pointer events (preferred)
  if (window.PointerEvent) {
    element.addEventListener("pointerdown", onStart);
    element.addEventListener("pointermove", onMove);
    element.addEventListener("pointerup", onEnd);
    element.addEventListener("pointercancel", onEnd);
  } else {
    // Fallback to touch + mouse
    element.addEventListener("touchstart", onStart, { passive: true });
    element.addEventListener("touchmove", onMove, { passive: false });
    element.addEventListener("touchend", onEnd);
    element.addEventListener("touchcancel", onEnd);
    element.addEventListener("mousedown", onStart);
    element.addEventListener("mousemove", onMove);
    element.addEventListener("mouseup", onEnd);
  }

  return {
    _type: "pan",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      if (window.PointerEvent) {
        element.removeEventListener("pointerdown", onStart);
        element.removeEventListener("pointermove", onMove);
        element.removeEventListener("pointerup", onEnd);
        element.removeEventListener("pointercancel", onEnd);
      } else {
        element.removeEventListener("touchstart", onStart);
        element.removeEventListener("touchmove", onMove);
        element.removeEventListener("touchend", onEnd);
        element.removeEventListener("touchcancel", onEnd);
        element.removeEventListener("mousedown", onStart);
        element.removeEventListener("mousemove", onMove);
        element.removeEventListener("mouseup", onEnd);
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // pinch gesture
// ═══════════════════════════════════════════════════════════════════════════════

export const createPinchGestureImpl = (element) => (config) => () => {
  let state = "idle";
  let initialDistance = 0;
  let initialScale = 1;
  let currentScale = 1;
  let centerX = 0, centerY = 0;
  let enabled = true;

  const buildState = () => ({
    state,
    scale: currentScale,
    initialScale,
    centerX,
    centerY,
    distance: initialDistance,
  });

  const onTouchStart = (e) => {
    if (!enabled || e.touches.length !== 2) return;
    const data = getTwoFingerData(e);
    if (!data) return;
    initialDistance = data.distance;
    centerX = data.centerX;
    centerY = data.centerY;
    initialScale = currentScale;
    state = "active";
    config.onStart(buildState())();
  };

  const onTouchMove = (e) => {
    if (!enabled || state !== "active" || e.touches.length !== 2) return;
    const data = getTwoFingerData(e);
    if (!data) return;
    e.preventDefault();
    
    const rawScale = initialScale * (data.distance / initialDistance);
    currentScale = Math.max(config.minScale, Math.min(config.maxScale, rawScale));
    centerX = data.centerX;
    centerY = data.centerY;
    config.onPinch(buildState())();
  };

  const onTouchEnd = () => {
    if (!enabled || state !== "active") return;
    state = "ended";
    config.onEnd(buildState())();
    state = "idle";
  };

  element.addEventListener("touchstart", onTouchStart, { passive: true });
  element.addEventListener("touchmove", onTouchMove, { passive: false });
  element.addEventListener("touchend", onTouchEnd);
  element.addEventListener("touchcancel", onTouchEnd);

  // Mouse wheel for desktop pinch emulation
  element.addEventListener("wheel", (e) => {
    if (!enabled || !e.ctrlKey) return;
    e.preventDefault();
    const delta = e.deltaY > 0 ? 0.95 : 1.05;
    const rawScale = currentScale * delta;
    currentScale = Math.max(config.minScale, Math.min(config.maxScale, rawScale));
    centerX = e.clientX;
    centerY = e.clientY;
    state = "active";
    config.onPinch(buildState())();
    state = "idle";
  }, { passive: false });

  return {
    _type: "pinch",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      element.removeEventListener("touchstart", onTouchStart);
      element.removeEventListener("touchmove", onTouchMove);
      element.removeEventListener("touchend", onTouchEnd);
      element.removeEventListener("touchcancel", onTouchEnd);
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // rotate gesture
// ═══════════════════════════════════════════════════════════════════════════════

export const createRotateGestureImpl = (element) => (config) => () => {
  let state = "idle";
  let initialAngle = 0;
  let initialRotation = 0;
  let currentRotation = 0;
  let centerX = 0, centerY = 0;
  let lastAngle = 0;
  let lastTime = 0;
  let angularVelocity = 0;
  let enabled = true;

  const buildState = () => ({
    state,
    rotation: currentRotation,
    initialRotation,
    centerX,
    centerY,
    velocity: angularVelocity,
  });

  const onTouchStart = (e) => {
    if (!enabled || e.touches.length !== 2) return;
    const data = getTwoFingerData(e);
    if (!data) return;
    initialAngle = data.angle;
    lastAngle = data.angle;
    lastTime = now();
    centerX = data.centerX;
    centerY = data.centerY;
    initialRotation = currentRotation;
  };

  const onTouchMove = (e) => {
    if (!enabled || e.touches.length !== 2) return;
    const data = getTwoFingerData(e);
    if (!data) return;
    
    let deltaAngle = data.angle - initialAngle;
    // Normalize angle wrap-around
    if (deltaAngle > 180) deltaAngle -= 360;
    if (deltaAngle < -180) deltaAngle += 360;

    if (state === "idle" && Math.abs(deltaAngle) >= config.threshold) {
      state = "active";
      config.onStart(buildState())();
    }

    if (state === "active") {
      e.preventDefault();
      currentRotation = initialRotation + deltaAngle;
      centerX = data.centerX;
      centerY = data.centerY;

      // Calculate velocity
      const currentTime = now();
      const dt = (currentTime - lastTime) / 1000;
      if (dt > 0) {
        angularVelocity = (data.angle - lastAngle) / dt;
      }
      lastAngle = data.angle;
      lastTime = currentTime;

      config.onRotate(buildState())();
    }
  };

  const onTouchEnd = () => {
    if (!enabled || state !== "active") return;
    state = "ended";
    config.onEnd(buildState())();
    state = "idle";
  };

  element.addEventListener("touchstart", onTouchStart, { passive: true });
  element.addEventListener("touchmove", onTouchMove, { passive: false });
  element.addEventListener("touchend", onTouchEnd);
  element.addEventListener("touchcancel", onTouchEnd);

  return {
    _type: "rotate",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      element.removeEventListener("touchstart", onTouchStart);
      element.removeEventListener("touchmove", onTouchMove);
      element.removeEventListener("touchend", onTouchEnd);
      element.removeEventListener("touchcancel", onTouchEnd);
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // swipe gesture
// ═══════════════════════════════════════════════════════════════════════════════

export const createSwipeGestureImpl = (element) => (config) => () => {
  let startX = 0, startY = 0;
  let startTime = 0;
  let enabled = true;

  const onStart = (e) => {
    if (!enabled) return;
    const pos = getPointerPosition(e);
    startX = pos.x;
    startY = pos.y;
    startTime = now();
  };

  const onEnd = (e) => {
    if (!enabled) return;
    const pos = getPointerPosition(e);
    const dx = pos.x - startX;
    const dy = pos.y - startY;
    const distance = Math.sqrt(dx * dx + dy * dy);
    const duration = now() - startTime;

    if (duration > config.maxDuration || distance < config.distanceThreshold) {
      return;
    }

    const velocity = distance / (duration / 1000);
    if (velocity < config.velocityThreshold * 1000) return;

    // Determine direction
    const absDx = Math.abs(dx);
    const absDy = Math.abs(dy);
    let direction;
    if (absDx > absDy) {
      direction = dx > 0 ? "right" : "left";
    } else {
      direction = dy > 0 ? "down" : "up";
    }

    config.onSwipe(direction)();
  };

  if (window.PointerEvent) {
    element.addEventListener("pointerdown", onStart);
    element.addEventListener("pointerup", onEnd);
  } else {
    element.addEventListener("touchstart", onStart, { passive: true });
    element.addEventListener("touchend", onEnd);
    element.addEventListener("mousedown", onStart);
    element.addEventListener("mouseup", onEnd);
  }

  return {
    _type: "swipe",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      if (window.PointerEvent) {
        element.removeEventListener("pointerdown", onStart);
        element.removeEventListener("pointerup", onEnd);
      } else {
        element.removeEventListener("touchstart", onStart);
        element.removeEventListener("touchend", onEnd);
        element.removeEventListener("mousedown", onStart);
        element.removeEventListener("mouseup", onEnd);
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // long press
// ═══════════════════════════════════════════════════════════════════════════════

export const createLongPressGestureImpl = (element) => (config) => () => {
  let startX = 0, startY = 0;
  let timer = null;
  let enabled = true;

  const clear = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };

  const onStart = (e) => {
    if (!enabled) return;
    const pos = getPointerPosition(e);
    startX = pos.x;
    startY = pos.y;
    config.onStart({ x: startX, y: startY })();
    
    timer = setTimeout(() => {
      config.onLongPress({ x: startX, y: startY })();
      timer = null;
    }, config.duration);
  };

  const onMove = (e) => {
    if (!enabled || !timer) return;
    const pos = getPointerPosition(e);
    const dx = pos.x - startX;
    const dy = pos.y - startY;
    const distance = Math.sqrt(dx * dx + dy * dy);
    
    if (distance > config.maxDistance) {
      clear();
      config.onCancel();
    }
  };

  const onEnd = () => {
    if (timer) {
      clear();
      config.onCancel();
    }
  };

  if (window.PointerEvent) {
    element.addEventListener("pointerdown", onStart);
    element.addEventListener("pointermove", onMove);
    element.addEventListener("pointerup", onEnd);
    element.addEventListener("pointercancel", onEnd);
  } else {
    element.addEventListener("touchstart", onStart, { passive: true });
    element.addEventListener("touchmove", onMove);
    element.addEventListener("touchend", onEnd);
    element.addEventListener("touchcancel", onEnd);
    element.addEventListener("mousedown", onStart);
    element.addEventListener("mousemove", onMove);
    element.addEventListener("mouseup", onEnd);
  }

  return {
    _type: "longpress",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      clear();
      if (window.PointerEvent) {
        element.removeEventListener("pointerdown", onStart);
        element.removeEventListener("pointermove", onMove);
        element.removeEventListener("pointerup", onEnd);
        element.removeEventListener("pointercancel", onEnd);
      } else {
        element.removeEventListener("touchstart", onStart);
        element.removeEventListener("touchmove", onMove);
        element.removeEventListener("touchend", onEnd);
        element.removeEventListener("touchcancel", onEnd);
        element.removeEventListener("mousedown", onStart);
        element.removeEventListener("mousemove", onMove);
        element.removeEventListener("mouseup", onEnd);
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                  // double tap
// ═══════════════════════════════════════════════════════════════════════════════

export const createDoubleTapGestureImpl = (element) => (config) => () => {
  let lastTap = null;
  let singleTapTimer = null;
  let enabled = true;

  const onTap = (e) => {
    if (!enabled) return;
    const pos = getPointerPosition(e);
    const currentTime = now();

    if (lastTap) {
      const dt = currentTime - lastTap.time;
      const dx = pos.x - lastTap.x;
      const dy = pos.y - lastTap.y;
      const distance = Math.sqrt(dx * dx + dy * dy);

      if (dt < config.maxDelay && distance < config.maxDistance) {
        // Double tap detected
        if (singleTapTimer) {
          clearTimeout(singleTapTimer);
          singleTapTimer = null;
        }
        lastTap = null;
        config.onDoubleTap({ x: pos.x, y: pos.y })();
        return;
      }
    }

    // Store this tap
    lastTap = { x: pos.x, y: pos.y, time: currentTime };
    
    // Set timer for single tap
    if (singleTapTimer) clearTimeout(singleTapTimer);
    singleTapTimer = setTimeout(() => {
      config.onSingleTap({ x: pos.x, y: pos.y })();
      lastTap = null;
      singleTapTimer = null;
    }, config.maxDelay);
  };

  if (window.PointerEvent) {
    element.addEventListener("pointerup", onTap);
  } else {
    element.addEventListener("touchend", onTap);
    element.addEventListener("mouseup", onTap);
  }

  return {
    _type: "doubletap",
    element,
    enable: () => { enabled = true; },
    disable: () => { enabled = false; },
    destroy: () => {
      if (singleTapTimer) clearTimeout(singleTapTimer);
      if (window.PointerEvent) {
        element.removeEventListener("pointerup", onTap);
      } else {
        element.removeEventListener("touchend", onTap);
        element.removeEventListener("mouseup", onTap);
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // gesture composition
// ═══════════════════════════════════════════════════════════════════════════════

export const composeGestures = (gestures) => () => {
  // Gestures are already composed through their enable/disable methods
  // This function can be extended to handle gesture conflicts
  return;
};

export const enableGesture = (gesture) => () => {
  if (gesture && gesture.enable) gesture.enable();
};

export const disableGesture = (gesture) => () => {
  if (gesture && gesture.disable) gesture.disable();
};

export const destroyGesture = (gesture) => () => {
  if (gesture && gesture.destroy) gesture.destroy();
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // velocity tracking
// ═══════════════════════════════════════════════════════════════════════════════

export const trackPointImpl = (pointsRef) => (maxSamples) => (point) => () => {
  const points = pointsRef.value;
  points.push({ point, time: now() });
  while (points.length > maxSamples) {
    points.shift();
  }
  pointsRef.value = points;
};

export const getVelocityImpl = (pointsRef) => () => {
  const points = pointsRef.value;
  if (points.length < 2) {
    return { vx: 0, vy: 0 };
  }
  
  const first = points[0];
  const last = points[points.length - 1];
  const dt = (last.time - first.time) / 1000;
  
  if (dt === 0) {
    return { vx: 0, vy: 0 };
  }
  
  return {
    vx: (last.point.x - first.point.x) / dt,
    vy: (last.point.y - first.point.y) / dt,
  };
};
