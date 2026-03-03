// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hydrogen.Target.Canvas2D — FFI
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Canvas 2D rendering backend for maximum browser compatibility.
// Works on all browsers including iOS Safari 9+ and Android 4.4+.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ─────────────────────────────────────────────────────────────────────────────
// CONTEXT
// ─────────────────────────────────────────────────────────────────────────────

export const isCanvas2DSupportedImpl = () => {
  if (typeof document === 'undefined') return false;
  const canvas = document.createElement('canvas');
  return !!(canvas && canvas.getContext && canvas.getContext('2d'));
};

export const getContext2DImpl = canvasId => onSuccess => onError => () => {
  const canvas = document.getElementById(canvasId);
  if (!canvas) {
    onError(`Canvas element not found: ${canvasId}`)();
    return;
  }
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    onError(`Could not get 2D context from: ${canvasId}`)();
    return;
  }
  // Store canvas reference on context for export functions
  ctx._canvas = canvas;
  onSuccess(ctx)();
};

export const createOffscreenContextImpl = width => height => () => {
  // Try OffscreenCanvas first (better performance)
  if (typeof OffscreenCanvas !== 'undefined') {
    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext('2d');
    ctx._canvas = canvas;
    return ctx;
  }
  // Fall back to regular canvas
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  ctx._canvas = canvas;
  return ctx;
};

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────

export const clearImpl = ctx => () => {
  const canvas = ctx._canvas || ctx.canvas;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
};

export const saveImpl = ctx => () => ctx.save();

export const restoreImpl = ctx => () => ctx.restore();

export const resetTransformImpl = ctx => () => {
  if (ctx.resetTransform) {
    ctx.resetTransform();
  } else {
    // Fallback for older browsers
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT
// ─────────────────────────────────────────────────────────────────────────────

export const toDataURLImpl = ctx => mimeType => () => {
  const canvas = ctx._canvas || ctx.canvas;
  return canvas.toDataURL(mimeType);
};

export const toBlobImpl = ctx => mimeType => callback => () => {
  const canvas = ctx._canvas || ctx.canvas;
  canvas.toBlob(blob => callback(blob)(), mimeType);
};

// ─────────────────────────────────────────────────────────────────────────────
// PRIMITIVE RENDERING
// ─────────────────────────────────────────────────────────────────────────────

export const renderRectImpl = ctx => x => y => w => h => fill => tl => tr => br => bl => () => {
  ctx.fillStyle = fill;
  
  // Check if we need rounded corners
  if (tl > 0 || tr > 0 || br > 0 || bl > 0) {
    ctx.beginPath();
    ctx.moveTo(x + tl, y);
    ctx.lineTo(x + w - tr, y);
    if (tr > 0) ctx.arcTo(x + w, y, x + w, y + tr, tr);
    ctx.lineTo(x + w, y + h - br);
    if (br > 0) ctx.arcTo(x + w, y + h, x + w - br, y + h, br);
    ctx.lineTo(x + bl, y + h);
    if (bl > 0) ctx.arcTo(x, y + h, x, y + h - bl, bl);
    ctx.lineTo(x, y + tl);
    if (tl > 0) ctx.arcTo(x, y, x + tl, y, tl);
    ctx.closePath();
    ctx.fill();
  } else {
    ctx.fillRect(x, y, w, h);
  }
};

export const renderQuadImpl = ctx => x0 => y0 => x1 => y1 => x2 => y2 => x3 => y3 => fill => () => {
  ctx.fillStyle = fill;
  ctx.beginPath();
  ctx.moveTo(x0, y0);
  ctx.lineTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.lineTo(x3, y3);
  ctx.closePath();
  ctx.fill();
};

export const renderGlyphImpl = ctx => x => y => glyphIndex => fontSize => color => () => {
  ctx.fillStyle = color;
  ctx.font = `${fontSize}px sans-serif`;
  ctx.textBaseline = 'top';
  // Convert glyph index to character (simplified)
  const char = String.fromCharCode(glyphIndex);
  ctx.fillText(char, x, y);
};

export const renderParticleImpl = ctx => x => y => size => color => () => {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, size, 0, Math.PI * 2);
  ctx.fill();
};

// Image cache for performance
const imageCache = new Map();

export const renderImageImpl = ctx => url => x => y => w => h => () => {
  let img = imageCache.get(url);
  if (!img) {
    img = new Image();
    img.crossOrigin = 'anonymous';
    img.src = url;
    imageCache.set(url, img);
  }
  if (img.complete && img.naturalWidth > 0) {
    ctx.drawImage(img, x, y, w, h);
  }
  // If not loaded, it will render on next frame when loaded
};

// Video element cache
const videoCache = new Map();

export const renderVideoImpl = ctx => url => x => y => w => h => () => {
  let video = videoCache.get(url);
  if (!video) {
    video = document.createElement('video');
    video.crossOrigin = 'anonymous';
    video.src = url;
    video.muted = true;
    videoCache.set(url, video);
  }
  if (video.readyState >= 2) { // HAVE_CURRENT_DATA
    ctx.drawImage(video, x, y, w, h);
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// PATH OPERATIONS
// ─────────────────────────────────────────────────────────────────────────────

export const beginPathImpl = ctx => () => ctx.beginPath();

export const moveToImpl = ctx => x => y => () => ctx.moveTo(x, y);

export const lineToImpl = ctx => x => y => () => ctx.lineTo(x, y);

export const quadraticCurveToImpl = ctx => cpx => cpy => x => y => () => 
  ctx.quadraticCurveTo(cpx, cpy, x, y);

export const bezierCurveToImpl = ctx => cp1x => cp1y => cp2x => cp2y => x => y => () =>
  ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y);

export const closePathImpl = ctx => () => ctx.closePath();

export const fillPathImpl = ctx => color => () => {
  ctx.fillStyle = color;
  ctx.fill();
};

export const strokePathImpl = ctx => color => width => () => {
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
};

// ─────────────────────────────────────────────────────────────────────────────
// CLIPPING
// ─────────────────────────────────────────────────────────────────────────────

export const pushClipRectImpl = ctx => x => y => w => h => tl => tr => br => bl => () => {
  ctx.save();
  ctx.beginPath();
  if (tl > 0 || tr > 0 || br > 0 || bl > 0) {
    ctx.moveTo(x + tl, y);
    ctx.lineTo(x + w - tr, y);
    if (tr > 0) ctx.arcTo(x + w, y, x + w, y + tr, tr);
    ctx.lineTo(x + w, y + h - br);
    if (br > 0) ctx.arcTo(x + w, y + h, x + w - br, y + h, br);
    ctx.lineTo(x + bl, y + h);
    if (bl > 0) ctx.arcTo(x, y + h, x, y + h - bl, bl);
    ctx.lineTo(x, y + tl);
    if (tl > 0) ctx.arcTo(x, y, x + tl, y, tl);
  } else {
    ctx.rect(x, y, w, h);
  }
  ctx.closePath();
  ctx.clip();
};

export const pushClipPathImpl = ctx => () => {
  ctx.save();
  ctx.clip();
};

export const popClipImpl = ctx => () => ctx.restore();

// No additional helpers needed - unwrapPixel is now in PureScript
