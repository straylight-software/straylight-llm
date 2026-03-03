// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hydrogen.Target.GPU — FFI
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unified GPU target with fallback chain: WebGPU → WebGL2 → Canvas2D
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Helper to wrap Canvas2D context retrieval with Either
export const getCanvas2DContextImpl = canvasId => () => {
  if (typeof document === 'undefined') {
    return { Left: 'document not available (not in browser)' };
  }
  
  const canvas = document.getElementById(canvasId);
  if (!canvas) {
    return { Left: `Canvas element not found: ${canvasId}` };
  }
  
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return { Left: `Could not get 2D context from: ${canvasId}` };
  }
  
  // Store canvas reference on context for export functions
  ctx._canvas = canvas;
  
  return { Right: ctx };
};
