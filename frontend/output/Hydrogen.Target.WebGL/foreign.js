// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hydrogen.Target.WebGL — FFI
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// WebGL2 rendering backend for GPU-accelerated graphics.
// Falls back from WebGPU when not available.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ─────────────────────────────────────────────────────────────────────────────
// SHADERS (GLSL ES 3.0)
// ─────────────────────────────────────────────────────────────────────────────

const RECT_VERTEX_SHADER = `#version 300 es
precision highp float;

// Per-vertex attributes (unit quad)
in vec2 a_position;

// Per-instance attributes
in vec4 a_rect;        // x, y, width, height
in vec4 a_color;       // rgba
in vec4 a_cornerRadius; // tl, tr, br, bl

// Uniforms
uniform vec2 u_resolution;

// Outputs to fragment shader
out vec2 v_localPos;
out vec4 v_color;
out vec4 v_cornerRadius;
out vec2 v_size;

void main() {
    // Transform unit quad to rect position
    vec2 pos = a_rect.xy + a_position * a_rect.zw;
    
    // Convert to clip space (-1 to 1)
    vec2 clipPos = (pos / u_resolution) * 2.0 - 1.0;
    clipPos.y = -clipPos.y; // Flip Y for canvas coords
    
    gl_Position = vec4(clipPos, 0.0, 1.0);
    
    // Pass to fragment shader
    v_localPos = a_position * a_rect.zw; // Local position within rect
    v_color = a_color;
    v_cornerRadius = a_cornerRadius;
    v_size = a_rect.zw;
}
`;

const RECT_FRAGMENT_SHADER = `#version 300 es
precision highp float;

in vec2 v_localPos;
in vec4 v_color;
in vec4 v_cornerRadius;
in vec2 v_size;

out vec4 fragColor;

// Signed distance to rounded rectangle
float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

void main() {
    // Center the coordinate system
    vec2 center = v_size * 0.5;
    vec2 p = v_localPos - center;
    
    // Clamp corner radii to half size
    vec4 r = min(v_cornerRadius, vec4(min(v_size.x, v_size.y) * 0.5));
    
    // Calculate SDF
    float d = sdRoundedBox(p, center, r);
    
    // Anti-aliased edge
    float aa = fwidth(d);
    float alpha = 1.0 - smoothstep(-aa, aa, d);
    
    fragColor = vec4(v_color.rgb, v_color.a * alpha);
}
`;

const PARTICLE_VERTEX_SHADER = `#version 300 es
precision highp float;

// Per-instance attributes
in vec4 a_particle; // x, y, size, _
in vec4 a_color;    // rgba

uniform vec2 u_resolution;

out vec4 v_color;
out float v_radius;

void main() {
    vec2 pos = a_particle.xy;
    float size = a_particle.z;
    
    // Convert to clip space
    vec2 clipPos = (pos / u_resolution) * 2.0 - 1.0;
    clipPos.y = -clipPos.y;
    
    gl_Position = vec4(clipPos, 0.0, 1.0);
    gl_PointSize = size * 2.0; // Diameter
    
    v_color = a_color;
    v_radius = size;
}
`;

const PARTICLE_FRAGMENT_SHADER = `#version 300 es
precision highp float;

in vec4 v_color;
in float v_radius;

out vec4 fragColor;

void main() {
    // Distance from center of point sprite
    vec2 coord = gl_PointCoord * 2.0 - 1.0;
    float dist = length(coord);
    
    // Anti-aliased circle
    float aa = fwidth(dist);
    float alpha = 1.0 - smoothstep(1.0 - aa, 1.0, dist);
    
    fragColor = vec4(v_color.rgb, v_color.a * alpha);
}
`;

// ─────────────────────────────────────────────────────────────────────────────
// CONTEXT
// ─────────────────────────────────────────────────────────────────────────────

export const isWebGL2SupportedImpl = () => {
  if (typeof document === 'undefined') return false;
  const canvas = document.createElement('canvas');
  return !!(canvas && canvas.getContext && canvas.getContext('webgl2'));
};

export const getContextImpl = canvasId => () => {
  const canvas = document.getElementById(canvasId);
  if (!canvas) {
    return { Left: `Canvas element not found: ${canvasId}` };
  }
  
  const gl = canvas.getContext('webgl2', {
    alpha: true,
    antialias: true,
    premultipliedAlpha: true,
    preserveDrawingBuffer: false,
  });
  
  if (!gl) {
    return { Left: `WebGL2 not supported or context creation failed` };
  }
  
  // Store canvas reference
  gl._canvas = canvas;
  
  return { Right: gl };
};

// ─────────────────────────────────────────────────────────────────────────────
// RENDERER
// ─────────────────────────────────────────────────────────────────────────────

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const error = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Shader compilation failed: ${error}`);
  }
  
  return shader;
}

function createProgram(gl, vertexSource, fragmentSource) {
  const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
  const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
  
  const program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);
  
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const error = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(`Program linking failed: ${error}`);
  }
  
  // Clean up shaders (they're linked into program now)
  gl.deleteShader(vertexShader);
  gl.deleteShader(fragmentShader);
  
  return program;
}

export const createRendererImpl = gl => () => {
  const renderer = {
    gl,
    programs: {},
    buffers: {},
    vaos: {},
  };
  
  try {
    // Create shader programs
    renderer.programs.rect = createProgram(gl, RECT_VERTEX_SHADER, RECT_FRAGMENT_SHADER);
    renderer.programs.particle = createProgram(gl, PARTICLE_VERTEX_SHADER, PARTICLE_FRAGMENT_SHADER);
    
    // Create buffers for instanced rendering
    // Unit quad for rectangles
    const quadVerts = new Float32Array([
      0, 0,  1, 0,  0, 1,
      1, 0,  1, 1,  0, 1,
    ]);
    renderer.buffers.quad = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.quad);
    gl.bufferData(gl.ARRAY_BUFFER, quadVerts, gl.STATIC_DRAW);
    
    // Dynamic instance buffers (resized as needed)
    renderer.buffers.rectInstances = gl.createBuffer();
    renderer.buffers.particleInstances = gl.createBuffer();
    
    // Create VAOs
    renderer.vaos.rect = gl.createVertexArray();
    renderer.vaos.particle = gl.createVertexArray();
    
    // Set up rect VAO
    gl.bindVertexArray(renderer.vaos.rect);
    
    // Position attribute (from quad buffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.quad);
    const posLoc = gl.getAttribLocation(renderer.programs.rect, 'a_position');
    gl.enableVertexAttribArray(posLoc);
    gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
    
    // Instance attributes (from instance buffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.rectInstances);
    const rectLoc = gl.getAttribLocation(renderer.programs.rect, 'a_rect');
    const colorLoc = gl.getAttribLocation(renderer.programs.rect, 'a_color');
    const radiusLoc = gl.getAttribLocation(renderer.programs.rect, 'a_cornerRadius');
    
    // a_rect: x, y, w, h (4 floats)
    gl.enableVertexAttribArray(rectLoc);
    gl.vertexAttribPointer(rectLoc, 4, gl.FLOAT, false, 48, 0);
    gl.vertexAttribDivisor(rectLoc, 1);
    
    // a_color: r, g, b, a (4 floats)
    gl.enableVertexAttribArray(colorLoc);
    gl.vertexAttribPointer(colorLoc, 4, gl.FLOAT, false, 48, 16);
    gl.vertexAttribDivisor(colorLoc, 1);
    
    // a_cornerRadius: tl, tr, br, bl (4 floats)
    gl.enableVertexAttribArray(radiusLoc);
    gl.vertexAttribPointer(radiusLoc, 4, gl.FLOAT, false, 48, 32);
    gl.vertexAttribDivisor(radiusLoc, 1);
    
    gl.bindVertexArray(null);
    
    // Set up particle VAO
    gl.bindVertexArray(renderer.vaos.particle);
    gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.particleInstances);
    
    const particleLoc = gl.getAttribLocation(renderer.programs.particle, 'a_particle');
    const pColorLoc = gl.getAttribLocation(renderer.programs.particle, 'a_color');
    
    // a_particle: x, y, size, _ (4 floats)
    gl.enableVertexAttribArray(particleLoc);
    gl.vertexAttribPointer(particleLoc, 4, gl.FLOAT, false, 32, 0);
    gl.vertexAttribDivisor(particleLoc, 1);
    
    // a_color: r, g, b, a (4 floats)
    gl.enableVertexAttribArray(pColorLoc);
    gl.vertexAttribPointer(pColorLoc, 4, gl.FLOAT, false, 32, 16);
    gl.vertexAttribDivisor(pColorLoc, 1);
    
    gl.bindVertexArray(null);
    
  } catch (err) {
    console.error('Renderer creation failed:', err);
    throw err;
  }
  
  return renderer;
};

export const destroyRendererImpl = renderer => () => {
  const gl = renderer.gl;
  
  // Delete programs
  for (const program of Object.values(renderer.programs)) {
    gl.deleteProgram(program);
  }
  
  // Delete buffers
  for (const buffer of Object.values(renderer.buffers)) {
    gl.deleteBuffer(buffer);
  }
  
  // Delete VAOs
  for (const vao of Object.values(renderer.vaos)) {
    gl.deleteVertexArray(vao);
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// RENDERING
// ─────────────────────────────────────────────────────────────────────────────

export const renderImpl = renderer => commands => () => {
  const gl = renderer.gl;
  const canvas = gl._canvas;
  
  // Set viewport
  gl.viewport(0, 0, canvas.width, canvas.height);
  
  // Enable blending for transparency
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
  
  // Batch commands by type
  const rects = [];
  const particles = [];
  
  for (const cmd of commands) {
    if (cmd.tag === 'DrawRect') {
      rects.push(cmd.value0);
    } else if (cmd.tag === 'DrawParticle') {
      particles.push(cmd.value0);
    }
    // TODO: Handle other command types
  }
  
  // Render rectangles
  if (rects.length > 0) {
    renderRects(renderer, rects);
  }
  
  // Render particles
  if (particles.length > 0) {
    renderParticles(renderer, particles);
  }
};

function renderRects(renderer, rects) {
  const gl = renderer.gl;
  const program = renderer.programs.rect;
  const canvas = gl._canvas;
  
  gl.useProgram(program);
  
  // Set resolution uniform
  const resLoc = gl.getUniformLocation(program, 'u_resolution');
  gl.uniform2f(resLoc, canvas.width, canvas.height);
  
  // Build instance data
  const instanceData = new Float32Array(rects.length * 12); // 12 floats per rect
  
  for (let i = 0; i < rects.length; i++) {
    const r = rects[i];
    const offset = i * 12;
    
    // a_rect
    instanceData[offset + 0] = r.x || 0;
    instanceData[offset + 1] = r.y || 0;
    instanceData[offset + 2] = r.width || 0;
    instanceData[offset + 3] = r.height || 0;
    
    // a_color
    const fill = r.fill || {};
    instanceData[offset + 4] = fill.r || 0;
    instanceData[offset + 5] = fill.g || 0;
    instanceData[offset + 6] = fill.b || 0;
    instanceData[offset + 7] = fill.a || 1;
    
    // a_cornerRadius
    const cr = r.cornerRadius || {};
    instanceData[offset + 8] = cr.topLeft || 0;
    instanceData[offset + 9] = cr.topRight || 0;
    instanceData[offset + 10] = cr.bottomRight || 0;
    instanceData[offset + 11] = cr.bottomLeft || 0;
  }
  
  // Upload instance data
  gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.rectInstances);
  gl.bufferData(gl.ARRAY_BUFFER, instanceData, gl.DYNAMIC_DRAW);
  
  // Draw
  gl.bindVertexArray(renderer.vaos.rect);
  gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, rects.length);
  gl.bindVertexArray(null);
}

function renderParticles(renderer, particles) {
  const gl = renderer.gl;
  const program = renderer.programs.particle;
  const canvas = gl._canvas;
  
  gl.useProgram(program);
  
  // Set resolution uniform
  const resLoc = gl.getUniformLocation(program, 'u_resolution');
  gl.uniform2f(resLoc, canvas.width, canvas.height);
  
  // Build instance data
  const instanceData = new Float32Array(particles.length * 8); // 8 floats per particle
  
  for (let i = 0; i < particles.length; i++) {
    const p = particles[i];
    const offset = i * 8;
    
    // a_particle
    instanceData[offset + 0] = p.x || 0;
    instanceData[offset + 1] = p.y || 0;
    instanceData[offset + 2] = p.size || 5;
    instanceData[offset + 3] = 0; // unused
    
    // a_color
    const color = p.color || {};
    instanceData[offset + 4] = color.r || 1;
    instanceData[offset + 5] = color.g || 0;
    instanceData[offset + 6] = color.b || 0;
    instanceData[offset + 7] = color.a || 1;
  }
  
  // Upload instance data
  gl.bindBuffer(gl.ARRAY_BUFFER, renderer.buffers.particleInstances);
  gl.bufferData(gl.ARRAY_BUFFER, instanceData, gl.DYNAMIC_DRAW);
  
  // Draw
  gl.bindVertexArray(renderer.vaos.particle);
  gl.drawArraysInstanced(gl.POINTS, 0, 1, particles.length);
  gl.bindVertexArray(null);
}

export const clearImpl = gl => r => g => b => a => () => {
  gl.clearColor(r, g, b, a);
  gl.clear(gl.COLOR_BUFFER_BIT);
};

// ─────────────────────────────────────────────────────────────────────────────
// INFO
// ─────────────────────────────────────────────────────────────────────────────

export const getMaxTextureSizeImpl = gl => () => 
  gl.getParameter(gl.MAX_TEXTURE_SIZE);

export const getMaxVertexAttribsImpl = gl => () =>
  gl.getParameter(gl.MAX_VERTEX_ATTRIBS);

export const getRendererImpl = gl => () => {
  const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
  if (debugInfo) {
    return gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
  }
  return 'Unknown';
};

export const getVendorImpl = gl => () => {
  const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
  if (debugInfo) {
    return gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
  }
  return 'Unknown';
};
