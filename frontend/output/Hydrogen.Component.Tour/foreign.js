// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                           // hydrogen // tour
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Product tour FFI for step navigation, highlighting, and persistence

/**
 * Initialize tour controller
 * @param {Object} config - Tour configuration
 * @param {Object} callbacks - Event callbacks
 * @returns {Object} Tour controller
 */
export const initTourImpl = (config, callbacks) => {
  const { persistKey, scrollBehavior } = config;
  const { onStart, onStep, onComplete, onSkip } = callbacks;

  let currentStep = 0;
  let steps = [];
  let isActive = false;

  // Load persisted progress
  if (persistKey) {
    const saved = localStorage.getItem(`hydrogen-tour-${persistKey}`);
    if (saved) {
      currentStep = parseInt(saved, 10) || 0;
    }
  }

  /**
   * Save progress to localStorage
   */
  const saveProgress = () => {
    if (persistKey) {
      localStorage.setItem(`hydrogen-tour-${persistKey}`, String(currentStep));
    }
  };

  /**
   * Clear persisted progress
   */
  const clearSavedProgress = () => {
    if (persistKey) {
      localStorage.removeItem(`hydrogen-tour-${persistKey}`);
    }
  };

  /**
   * Highlight target element
   */
  const highlightTarget = (target, padding = 4) => {
    const element = document.querySelector(target);
    if (!element) return;

    const rect = element.getBoundingClientRect();
    const highlight = document.querySelector(".tour-highlight");

    if (highlight) {
      highlight.style.top = `${rect.top - padding}px`;
      highlight.style.left = `${rect.left - padding}px`;
      highlight.style.width = `${rect.width + padding * 2}px`;
      highlight.style.height = `${rect.height + padding * 2}px`;
    }
  };

  /**
   * Position tooltip relative to target
   */
  const positionTooltip = (target, placement, offset = 8) => {
    const element = document.querySelector(target);
    const tooltip = document.querySelector(".tour-tooltip");

    if (!element || !tooltip) return;

    const targetRect = element.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();

    let top = 0;
    let left = 0;

    switch (placement) {
      case "top":
        top = targetRect.top - tooltipRect.height - offset;
        left = targetRect.left + (targetRect.width - tooltipRect.width) / 2;
        break;
      case "top-start":
        top = targetRect.top - tooltipRect.height - offset;
        left = targetRect.left;
        break;
      case "top-end":
        top = targetRect.top - tooltipRect.height - offset;
        left = targetRect.right - tooltipRect.width;
        break;
      case "bottom":
        top = targetRect.bottom + offset;
        left = targetRect.left + (targetRect.width - tooltipRect.width) / 2;
        break;
      case "bottom-start":
        top = targetRect.bottom + offset;
        left = targetRect.left;
        break;
      case "bottom-end":
        top = targetRect.bottom + offset;
        left = targetRect.right - tooltipRect.width;
        break;
      case "left":
        top = targetRect.top + (targetRect.height - tooltipRect.height) / 2;
        left = targetRect.left - tooltipRect.width - offset;
        break;
      case "left-start":
        top = targetRect.top;
        left = targetRect.left - tooltipRect.width - offset;
        break;
      case "left-end":
        top = targetRect.bottom - tooltipRect.height;
        left = targetRect.left - tooltipRect.width - offset;
        break;
      case "right":
        top = targetRect.top + (targetRect.height - tooltipRect.height) / 2;
        left = targetRect.right + offset;
        break;
      case "right-start":
        top = targetRect.top;
        left = targetRect.right + offset;
        break;
      case "right-end":
        top = targetRect.bottom - tooltipRect.height;
        left = targetRect.right + offset;
        break;
      default:
        top = targetRect.bottom + offset;
        left = targetRect.left + (targetRect.width - tooltipRect.width) / 2;
    }

    // Keep tooltip within viewport
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    if (left < 8) left = 8;
    if (left + tooltipRect.width > viewportWidth - 8) {
      left = viewportWidth - tooltipRect.width - 8;
    }
    if (top < 8) top = 8;
    if (top + tooltipRect.height > viewportHeight - 8) {
      top = viewportHeight - tooltipRect.height - 8;
    }

    tooltip.style.top = `${top}px`;
    tooltip.style.left = `${left}px`;
  };

  /**
   * Scroll target element into view
   */
  const scrollToTarget = (target, margin = 20) => {
    const element = document.querySelector(target);
    if (!element) return;

    const rect = element.getBoundingClientRect();
    const isInView =
      rect.top >= margin &&
      rect.bottom <= window.innerHeight - margin &&
      rect.left >= margin &&
      rect.right <= window.innerWidth - margin;

    if (!isInView) {
      element.scrollIntoView({
        behavior: scrollBehavior === "instant" ? "auto" : "smooth",
        block: "center",
        inline: "center",
      });
    }
  };

  /**
   * Go to a specific step
   */
  const goTo = (stepIndex) => {
    if (stepIndex < 0 || stepIndex >= steps.length) return false;

    currentStep = stepIndex;
    saveProgress();
    onStep(currentStep);

    const step = steps[currentStep];
    if (step) {
      if (scrollBehavior !== "none") {
        scrollToTarget(step.target, step.scrollMargin || 20);
      }

      // Wait for scroll then position
      setTimeout(() => {
        highlightTarget(step.target, step.highlightPadding || 4);
        positionTooltip(step.target, step.placement || "bottom", step.offset || 8);
      }, scrollBehavior === "smooth" ? 300 : 0);
    }

    return true;
  };

  /**
   * Handle keyboard navigation
   */
  const handleKeydown = (e) => {
    if (!isActive) return;

    switch (e.key) {
      case "ArrowRight":
      case "Enter":
        e.preventDefault();
        if (currentStep < steps.length - 1) {
          goTo(currentStep + 1);
        } else {
          complete();
        }
        break;
      case "ArrowLeft":
        e.preventDefault();
        if (currentStep > 0) {
          goTo(currentStep - 1);
        }
        break;
      case "Escape":
        e.preventDefault();
        skip();
        break;
    }
  };

  /**
   * Start the tour
   */
  const start = () => {
    isActive = true;
    document.addEventListener("keydown", handleKeydown);
    onStart();
    goTo(currentStep);
  };

  /**
   * Complete the tour
   */
  const complete = () => {
    isActive = false;
    document.removeEventListener("keydown", handleKeydown);
    clearSavedProgress();
    onComplete();
  };

  /**
   * Skip the tour
   */
  const skip = () => {
    isActive = false;
    document.removeEventListener("keydown", handleKeydown);
    saveProgress(); // Save progress even when skipping
    onSkip();
  };

  // Handle window resize
  const handleResize = () => {
    if (isActive && steps[currentStep]) {
      const step = steps[currentStep];
      highlightTarget(step.target, step.highlightPadding || 4);
      positionTooltip(step.target, step.placement || "bottom", step.offset || 8);
    }
  };

  window.addEventListener("resize", handleResize);

  return {
    setSteps: (newSteps) => {
      steps = newSteps;
    },
    start,
    next: () => {
      if (currentStep < steps.length - 1) {
        return goTo(currentStep + 1);
      }
      complete();
      return false;
    },
    prev: () => {
      if (currentStep > 0) {
        return goTo(currentStep - 1);
      }
      return false;
    },
    goTo,
    skip,
    complete,
    getCurrentStep: () => currentStep,
    getTotalSteps: () => steps.length,
    isActive: () => isActive,
    destroy: () => {
      isActive = false;
      document.removeEventListener("keydown", handleKeydown);
      window.removeEventListener("resize", handleResize);
    },
  };
};

/**
 * Destroy tour
 */
export const destroyTourImpl = (tour) => {
  if (tour && tour.destroy) {
    tour.destroy();
  }
};

/**
 * Start tour
 */
export const startTourImpl = (tour) => {
  if (tour && tour.start) {
    tour.start();
  }
};

/**
 * Go to next step
 */
export const nextStepImpl = (tour) => {
  if (tour && tour.next) {
    return tour.next();
  }
  return false;
};

/**
 * Go to previous step
 */
export const prevStepImpl = (tour) => {
  if (tour && tour.prev) {
    return tour.prev();
  }
  return false;
};

/**
 * Go to specific step
 */
export const goToStepImpl = (tour, step) => {
  if (tour && tour.goTo) {
    return tour.goTo(step);
  }
  return false;
};

/**
 * Skip tour
 */
export const skipTourImpl = (tour) => {
  if (tour && tour.skip) {
    tour.skip();
  }
};

/**
 * Get persisted progress
 */
export const getProgressImpl = (key) => {
  const saved = localStorage.getItem(`hydrogen-tour-${key}`);
  return saved ? parseInt(saved, 10) : 0;
};

/**
 * Clear persisted progress
 */
export const clearProgressImpl = (key) => {
  localStorage.removeItem(`hydrogen-tour-${key}`);
};

/**
 * Highlight element
 */
export const highlightElementImpl = (selector, padding, animate) => {
  const element = document.querySelector(selector);
  if (!element) return;

  const rect = element.getBoundingClientRect();

  // Create or get highlight overlay
  let highlight = document.querySelector(".tour-highlight-overlay");
  if (!highlight) {
    highlight = document.createElement("div");
    highlight.className = "tour-highlight-overlay fixed pointer-events-none z-[55]";
    highlight.style.boxShadow = "0 0 0 9999px rgba(0, 0, 0, 0.5)";
    highlight.style.borderRadius = "4px";
    document.body.appendChild(highlight);
  }

  if (animate) {
    highlight.style.transition = "all 300ms ease-out";
  }

  highlight.style.top = `${rect.top - padding}px`;
  highlight.style.left = `${rect.left - padding}px`;
  highlight.style.width = `${rect.width + padding * 2}px`;
  highlight.style.height = `${rect.height + padding * 2}px`;
};

/**
 * Remove highlight
 */
export const removeHighlightImpl = () => {
  const highlight = document.querySelector(".tour-highlight-overlay");
  if (highlight) {
    highlight.remove();
  }
};

/**
 * Safe array index access
 */
export const safeIndexImpl = (arr) => (idx) => {
  if (idx >= 0 && idx < arr.length) {
    return arr[idx];
  }
  return null;
};

/**
 * Replicate value n times
 */
export const replicateImpl = (n) => (val) => {
  const result = [];
  for (let i = 0; i < n; i++) {
    result.push(val);
  }
  return result;
};

/**
 * Placeholder tour element
 */
export const unsafeTourElement = {
  setSteps: () => {},
  start: () => {},
  next: () => false,
  prev: () => false,
  goTo: () => false,
  skip: () => {},
  complete: () => {},
  getCurrentStep: () => 0,
  getTotalSteps: () => 0,
  isActive: () => false,
  destroy: () => {},
};
