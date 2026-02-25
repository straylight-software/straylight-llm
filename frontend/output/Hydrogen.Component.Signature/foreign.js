// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // signature
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Signature pad FFI for canvas drawing, touch support, and stroke management

/**
 * Initialize signature pad
 * @param {Element} container - Signature pad container
 * @param {Object} options - Configuration options
 * @returns {Object} Signature pad controller
 */
export const initSignaturePadImpl = (container, options) => {
  const { penColor, penThickness, backgroundColor, onDraw } = options;

  const canvas = container.querySelector(".signature-canvas");
  if (!canvas) return null;

  const ctx = canvas.getContext("2d");

  // State
  let isDrawing = false;
  let lastPoint = null;
  let currentStroke = [];
  let strokes = [];
  let isErasing = false;

  // Set initial background
  ctx.fillStyle = backgroundColor;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // Configure drawing
  ctx.strokeStyle = penColor;
  ctx.lineWidth = penThickness;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  /**
   * Get point from event
   */
  const getPoint = (e) => {
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;

    let clientX, clientY, pressure;

    if (e.touches && e.touches.length > 0) {
      clientX = e.touches[0].clientX;
      clientY = e.touches[0].clientY;
      pressure = e.touches[0].force || null;
    } else {
      clientX = e.clientX;
      clientY = e.clientY;
      pressure = e.pressure || null;
    }

    return {
      x: (clientX - rect.left) * scaleX,
      y: (clientY - rect.top) * scaleY,
      pressure,
    };
  };

  /**
   * Start drawing
   */
  const handleStart = (e) => {
    if (container.dataset.readonly === "true") return;

    e.preventDefault();
    isDrawing = true;
    isErasing = container.dataset.eraser === "true";
    lastPoint = getPoint(e);
    currentStroke = [lastPoint];

    ctx.beginPath();
    ctx.moveTo(lastPoint.x, lastPoint.y);
  };

  /**
   * Continue drawing
   */
  const handleMove = (e) => {
    if (!isDrawing) return;

    e.preventDefault();
    const point = getPoint(e);

    if (isErasing) {
      // Eraser mode
      ctx.globalCompositeOperation = "destination-out";
      ctx.lineWidth = penThickness * 3;
    } else {
      ctx.globalCompositeOperation = "source-over";
      ctx.lineWidth = point.pressure
        ? penThickness * (0.5 + point.pressure)
        : penThickness;
    }

    // Draw smooth curve using quadratic bezier
    if (lastPoint) {
      const midPoint = {
        x: (lastPoint.x + point.x) / 2,
        y: (lastPoint.y + point.y) / 2,
      };

      ctx.quadraticCurveTo(lastPoint.x, lastPoint.y, midPoint.x, midPoint.y);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(midPoint.x, midPoint.y);
    }

    currentStroke.push(point);
    lastPoint = point;
  };

  /**
   * End drawing
   */
  const handleEnd = (e) => {
    if (!isDrawing) return;

    e.preventDefault();
    isDrawing = false;

    // Complete the stroke
    if (lastPoint) {
      ctx.lineTo(lastPoint.x, lastPoint.y);
      ctx.stroke();
    }

    // Save stroke
    if (currentStroke.length > 1) {
      strokes.push({
        points: currentStroke,
        color: isErasing ? "eraser" : penColor,
        thickness: penThickness,
      });
    }

    currentStroke = [];
    lastPoint = null;
    ctx.globalCompositeOperation = "source-over";

    onDraw();
  };

  /**
   * Cancel drawing
   */
  const handleCancel = () => {
    isDrawing = false;
    currentStroke = [];
    lastPoint = null;
  };

  // Attach event listeners
  // Mouse events
  canvas.addEventListener("mousedown", handleStart);
  canvas.addEventListener("mousemove", handleMove);
  canvas.addEventListener("mouseup", handleEnd);
  canvas.addEventListener("mouseleave", handleCancel);

  // Touch events
  canvas.addEventListener("touchstart", handleStart, { passive: false });
  canvas.addEventListener("touchmove", handleMove, { passive: false });
  canvas.addEventListener("touchend", handleEnd, { passive: false });
  canvas.addEventListener("touchcancel", handleCancel);

  // Pointer events for stylus support
  if (window.PointerEvent) {
    canvas.addEventListener("pointerdown", handleStart);
    canvas.addEventListener("pointermove", handleMove);
    canvas.addEventListener("pointerup", handleEnd);
    canvas.addEventListener("pointerleave", handleCancel);
  }

  return {
    container,
    canvas,
    ctx,
    strokes,
    setPenColor: (color) => {
      ctx.strokeStyle = color;
    },
    setPenThickness: (thickness) => {
      ctx.lineWidth = thickness;
    },
    setEraserMode: (enabled) => {
      container.dataset.eraser = enabled ? "true" : "false";
    },
    clear: () => {
      ctx.fillStyle = backgroundColor;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      strokes = [];
    },
    undo: () => {
      if (strokes.length === 0) return false;

      strokes.pop();
      redraw();
      return true;
    },
    isEmpty: () => strokes.length === 0,
    getStrokeData: () => ({
      strokes,
      width: canvas.width,
      height: canvas.height,
    }),
    toDataURL: (format) => canvas.toDataURL(format || "image/png"),
    toSVG: () => strokesToSVG(strokes, canvas.width, canvas.height),
    toJSON: () =>
      JSON.stringify({
        strokes,
        width: canvas.width,
        height: canvas.height,
      }),
    fromJSON: (json) => {
      try {
        const data = JSON.parse(json);
        strokes = data.strokes || [];
        redraw();
      } catch (e) {
        console.error("Invalid signature JSON:", e);
      }
    },
    destroy: () => {
      canvas.removeEventListener("mousedown", handleStart);
      canvas.removeEventListener("mousemove", handleMove);
      canvas.removeEventListener("mouseup", handleEnd);
      canvas.removeEventListener("mouseleave", handleCancel);
      canvas.removeEventListener("touchstart", handleStart);
      canvas.removeEventListener("touchmove", handleMove);
      canvas.removeEventListener("touchend", handleEnd);
      canvas.removeEventListener("touchcancel", handleCancel);

      if (window.PointerEvent) {
        canvas.removeEventListener("pointerdown", handleStart);
        canvas.removeEventListener("pointermove", handleMove);
        canvas.removeEventListener("pointerup", handleEnd);
        canvas.removeEventListener("pointerleave", handleCancel);
      }
    },
  };

  /**
   * Redraw all strokes
   */
  function redraw() {
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    for (const stroke of strokes) {
      if (stroke.color === "eraser") {
        ctx.globalCompositeOperation = "destination-out";
      } else {
        ctx.globalCompositeOperation = "source-over";
        ctx.strokeStyle = stroke.color;
      }
      ctx.lineWidth = stroke.thickness;

      if (stroke.points.length < 2) continue;

      ctx.beginPath();
      ctx.moveTo(stroke.points[0].x, stroke.points[0].y);

      for (let i = 1; i < stroke.points.length; i++) {
        const point = stroke.points[i];
        const prev = stroke.points[i - 1];
        const mid = {
          x: (prev.x + point.x) / 2,
          y: (prev.y + point.y) / 2,
        };

        ctx.quadraticCurveTo(prev.x, prev.y, mid.x, mid.y);
      }

      ctx.stroke();
    }

    ctx.globalCompositeOperation = "source-over";
    ctx.strokeStyle = penColor;
  }
};

/**
 * Convert strokes to SVG
 */
const strokesToSVG = (strokes, width, height) => {
  let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`;
  svg += `<rect width="${width}" height="${height}" fill="#ffffff"/>`;

  for (const stroke of strokes) {
    if (stroke.color === "eraser" || stroke.points.length < 2) continue;

    let d = `M ${stroke.points[0].x} ${stroke.points[0].y}`;

    for (let i = 1; i < stroke.points.length; i++) {
      const point = stroke.points[i];
      const prev = stroke.points[i - 1];
      const mid = {
        x: (prev.x + point.x) / 2,
        y: (prev.y + point.y) / 2,
      };

      d += ` Q ${prev.x} ${prev.y} ${mid.x} ${mid.y}`;
    }

    svg += `<path d="${d}" stroke="${stroke.color}" stroke-width="${stroke.thickness}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
  }

  svg += "</svg>";
  return svg;
};

/**
 * Destroy signature pad
 */
export const destroySignaturePadImpl = (signaturePad) => {
  if (signaturePad && signaturePad.destroy) {
    signaturePad.destroy();
  }
};

/**
 * Clear signature
 */
export const clearSignatureImpl = (signaturePad) => {
  if (signaturePad && signaturePad.clear) {
    signaturePad.clear();
  }
};

/**
 * Undo last stroke
 */
export const undoStrokeImpl = (signaturePad) => {
  if (signaturePad && signaturePad.undo) {
    return signaturePad.undo();
  }
  return false;
};

/**
 * Export signature
 * @param {Object} signaturePad - Signature pad controller
 * @param {string} format - Export format (png, svg, json)
 * @returns {string} Exported data
 */
export const exportSignatureImpl = (signaturePad, format) => {
  if (!signaturePad) return "";

  switch (format.toLowerCase()) {
    case "svg":
      return signaturePad.toSVG ? signaturePad.toSVG() : "";
    case "json":
      return signaturePad.toJSON ? signaturePad.toJSON() : "";
    case "png":
    default:
      return signaturePad.toDataURL ? signaturePad.toDataURL("image/png") : "";
  }
};

/**
 * Import signature from JSON
 */
export const importSignatureImpl = (signaturePad, json) => {
  if (signaturePad && signaturePad.fromJSON) {
    signaturePad.fromJSON(json);
  }
};

/**
 * Check if signature is empty
 */
export const isEmptyImpl = (signaturePad) => {
  if (signaturePad && signaturePad.isEmpty) {
    return signaturePad.isEmpty();
  }
  return true;
};

/**
 * Placeholder signature element
 */
export const unsafeSignatureElement = {
  container: null,
  canvas: null,
  ctx: null,
  strokes: [],
  setPenColor: () => {},
  setPenThickness: () => {},
  setEraserMode: () => {},
  clear: () => {},
  undo: () => false,
  isEmpty: () => true,
  getStrokeData: () => ({ strokes: [], width: 0, height: 0 }),
  toDataURL: () => "",
  toSVG: () => "",
  toJSON: () => "{}",
  fromJSON: () => {},
  destroy: () => {},
};
