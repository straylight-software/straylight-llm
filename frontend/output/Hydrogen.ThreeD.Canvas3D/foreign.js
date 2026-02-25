// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                       // hydrogen // canvas3d
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Simple 3D Canvas component for easy 3D rendering.
// Ideal for product viewers, logos, and interactive demos.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // canvas registry
// ═══════════════════════════════════════════════════════════════════════════════

// Store canvas instances by container ID
const canvasRegistry = new Map();

/**
 * Get canvas reference by container ID
 */
export const getCanvasRefImpl = (containerId) => () => {
  return canvasRegistry.get(containerId) || null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // canvas api
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Add primitive to canvas
 */
export const addPrimitiveImpl = (canvasRef) => (type) => (config) => () => {
  if (!canvasRef || !canvasRef.scene || !canvasRef.THREE) return;

  const THREE = canvasRef.THREE;
  const mesh = createPrimitive(THREE, type, config);
  if (mesh) {
    canvasRef.scene.add(mesh);
    canvasRef.objects.set(config.id || mesh.uuid, mesh);
  }
};

/**
 * Remove primitive from canvas
 */
export const removePrimitiveImpl = (canvasRef) => (id) => () => {
  if (!canvasRef || !canvasRef.scene) return;

  const mesh = canvasRef.objects.get(id);
  if (mesh) {
    canvasRef.scene.remove(mesh);
    if (mesh.geometry) mesh.geometry.dispose();
    if (mesh.material) mesh.material.dispose();
    canvasRef.objects.delete(id);
  }
};

/**
 * Reset camera to default position
 */
export const resetCameraImpl = (canvasRef) => () => {
  if (!canvasRef || !canvasRef.camera || !canvasRef.controls) return;

  const distance = canvasRef.defaultCameraDistance || 4;
  canvasRef.camera.position.set(0, distance * 0.5, distance);
  canvasRef.camera.lookAt(0, 0, 0);
  canvasRef.controls.reset();
};

/**
 * Set auto-rotate
 */
export const setAutoRotateImpl = (canvasRef) => (enabled) => () => {
  if (canvasRef && canvasRef.controls) {
    canvasRef.controls.autoRotate = enabled;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // canvas initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize 3D canvas from container element
 */
const initCanvas3D = async (container) => {
  if (container._canvasInitialized) return;
  container._canvasInitialized = true;

  // Dynamically import Three.js
  const THREE = await import("three");
  const { OrbitControls } = await import(
    "three/examples/jsm/controls/OrbitControls.js"
  );
  const { GLTFLoader } = await import(
    "three/examples/jsm/loaders/GLTFLoader.js"
  );

  // Get configuration from data attributes
  const width = parseInt(container.dataset.canvasWidth) || 400;
  const height = parseInt(container.dataset.canvasHeight) || 300;
  const background = container.dataset.background || "#f8fafc";
  const transparent = container.dataset.transparent === "true";
  const environment = container.dataset.environment || "studio";
  const cameraDistance = parseFloat(container.dataset.cameraDistance) || 4;
  const cameraFov = parseFloat(container.dataset.cameraFov) || 45;
  const autoRotate = container.dataset.autoRotate === "true";
  const autoRotateSpeed = parseFloat(container.dataset.autoRotateSpeed) || 1;
  const enableZoom = container.dataset.enableZoom !== "false";
  const enablePan = container.dataset.enablePan === "true";
  const enableRotate = container.dataset.enableRotate !== "false";
  const minDistance = parseFloat(container.dataset.minDistance) || 1;
  const maxDistance = parseFloat(container.dataset.maxDistance) || 20;
  const showFloor = container.dataset.showFloor === "true";
  const floorColor = container.dataset.floorColor || "#e5e7eb";
  const floorSize = parseFloat(container.dataset.floorSize) || 10;
  const shadows = container.dataset.shadows !== "false";
  const responsive = container.dataset.responsive !== "false";

  // Get canvas element
  const canvas = container.querySelector("[data-canvas3d-element]");
  if (!canvas) return;

  // Create scene
  const scene = new THREE.Scene();

  // Set background
  if (!transparent) {
    scene.background = new THREE.Color(background);
  }

  // Create renderer
  const renderer = new THREE.WebGLRenderer({
    canvas: canvas,
    antialias: true,
    alpha: transparent,
  });
  renderer.setSize(width, height);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // Shadows
  if (shadows) {
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  }

  // Tone mapping
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1;

  // Create camera
  const camera = new THREE.PerspectiveCamera(cameraFov, width / height, 0.1, 100);
  camera.position.set(0, cameraDistance * 0.5, cameraDistance);

  // Create controls
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.05;
  controls.enableZoom = enableZoom;
  controls.enablePan = enablePan;
  controls.enableRotate = enableRotate;
  controls.minDistance = minDistance;
  controls.maxDistance = maxDistance;
  controls.autoRotate = autoRotate;
  controls.autoRotateSpeed = autoRotateSpeed;

  // Set up environment lighting
  setupEnvironment(THREE, scene, environment);

  // Add floor if enabled
  if (showFloor) {
    const floorGeometry = new THREE.PlaneGeometry(floorSize, floorSize);
    const floorMaterial = new THREE.MeshStandardMaterial({
      color: floorColor,
      roughness: 0.8,
      metalness: 0.2,
    });
    const floor = new THREE.Mesh(floorGeometry, floorMaterial);
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.5;
    floor.receiveShadow = true;
    scene.add(floor);
  }

  // Canvas reference
  const canvasRef = {
    THREE,
    scene,
    camera,
    renderer,
    controls,
    objects: new Map(),
    autoRotateObjects: [],
    defaultCameraDistance: cameraDistance,
    loaders: { gltf: new GLTFLoader() },
  };

  // Generate unique ID for registry
  const canvasId =
    container.id || `canvas3d-${Math.random().toString(36).substr(2, 9)}`;
  container.id = canvasId;
  canvasRegistry.set(canvasId, canvasRef);

  // Parse children (primitives, models, lights)
  const childrenContainer = container.querySelector("[data-canvas3d-children]");
  if (childrenContainer) {
    parseChildren(canvasRef, childrenContainer);
  }

  // Raycasting for interaction
  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();

  const onMouseClick = (event) => {
    const rect = canvas.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObjects(Array.from(canvasRef.objects.values()), true);

    if (intersects.length > 0) {
      const hit = intersects[0];
      container.dispatchEvent(
        new CustomEvent("canvas3d:click", {
          detail: {
            objectId: hit.object.name || hit.object.uuid,
            point: { x: hit.point.x, y: hit.point.y, z: hit.point.z },
          },
        })
      );
    }
  };

  canvas.addEventListener("click", onMouseClick);

  // Responsive resize
  if (responsive) {
    const resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        if (width > 0 && height > 0) {
          renderer.setSize(width, height);
          camera.aspect = width / height;
          camera.updateProjectionMatrix();
        }
      }
    });
    resizeObserver.observe(container);
  }

  // Animation loop
  let animationId;
  const clock = new THREE.Clock();

  const animate = () => {
    animationId = requestAnimationFrame(animate);
    const delta = clock.getDelta();

    // Update controls
    controls.update();

    // Update auto-rotating objects
    for (const { mesh, speed } of canvasRef.autoRotateObjects) {
      mesh.rotation.y += speed * delta;
    }

    // Render
    renderer.render(scene, camera);
  };

  animate();

  // Cleanup on removal
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.removedNodes) {
        if (node === container || node.contains?.(container)) {
          cancelAnimationFrame(animationId);
          renderer.dispose();
          canvasRegistry.delete(canvasId);
          observer.disconnect();
          return;
        }
      }
    }
  });

  if (container.parentElement) {
    observer.observe(container.parentElement, { childList: true, subtree: true });
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // environment setup
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Set up environment lighting based on preset
 */
const setupEnvironment = (THREE, scene, environment) => {
  // Default lights for all environments
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
  scene.add(ambientLight);

  switch (environment) {
    case "studio": {
      // Key light
      const keyLight = new THREE.DirectionalLight(0xffffff, 1);
      keyLight.position.set(5, 10, 5);
      keyLight.castShadow = true;
      keyLight.shadow.mapSize.width = 1024;
      keyLight.shadow.mapSize.height = 1024;
      scene.add(keyLight);

      // Fill light
      const fillLight = new THREE.DirectionalLight(0xffffff, 0.3);
      fillLight.position.set(-5, 5, -5);
      scene.add(fillLight);

      // Rim light
      const rimLight = new THREE.DirectionalLight(0xffffff, 0.2);
      rimLight.position.set(0, 5, -10);
      scene.add(rimLight);
      break;
    }
    case "sunset": {
      scene.background = new THREE.Color(0xffd4a3);
      const sunLight = new THREE.DirectionalLight(0xffa500, 1.5);
      sunLight.position.set(-10, 3, 5);
      sunLight.castShadow = true;
      scene.add(sunLight);
      break;
    }
    case "dawn": {
      scene.background = new THREE.Color(0xb8c6db);
      const dawnLight = new THREE.DirectionalLight(0x87ceeb, 1);
      dawnLight.position.set(10, 5, 10);
      dawnLight.castShadow = true;
      scene.add(dawnLight);
      break;
    }
    case "night": {
      scene.background = new THREE.Color(0x0a0a1a);
      ambientLight.intensity = 0.1;
      const moonLight = new THREE.DirectionalLight(0x8888ff, 0.5);
      moonLight.position.set(-5, 10, 5);
      scene.add(moonLight);
      break;
    }
    case "forest": {
      scene.background = new THREE.Color(0x228b22);
      const forestLight = new THREE.DirectionalLight(0xffff88, 0.8);
      forestLight.position.set(5, 15, 5);
      forestLight.castShadow = true;
      scene.add(forestLight);
      break;
    }
    case "city": {
      scene.background = new THREE.Color(0x2c3e50);
      const cityLight = new THREE.DirectionalLight(0xffffff, 0.8);
      cityLight.position.set(0, 20, 10);
      cityLight.castShadow = true;
      scene.add(cityLight);
      break;
    }
    case "warehouse": {
      scene.background = new THREE.Color(0x3a3a3a);
      const warehouseLight1 = new THREE.PointLight(0xffffcc, 1, 20);
      warehouseLight1.position.set(5, 8, 5);
      warehouseLight1.castShadow = true;
      scene.add(warehouseLight1);

      const warehouseLight2 = new THREE.PointLight(0xffffcc, 1, 20);
      warehouseLight2.position.set(-5, 8, -5);
      scene.add(warehouseLight2);
      break;
    }
    case "none":
    default:
      // Just ambient light
      break;
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // parse children
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse canvas children from DOM elements
 */
const parseChildren = (canvasRef, container) => {
  const { THREE, scene } = canvasRef;

  for (const child of container.children) {
    // Primitives
    if (child.dataset.primitive) {
      const type = child.dataset.primitive;
      const config = {
        id: child.dataset.id || "",
        color: child.dataset.color || "#3b82f6",
        position: parseVector3(child.dataset.position),
        rotation: parseVector3(child.dataset.rotation),
        metalness: parseFloat(child.dataset.metalness) || 0.3,
        roughness: parseFloat(child.dataset.roughness) || 0.5,
        size: parseFloat(child.dataset.size),
        radius: parseFloat(child.dataset.radius),
        height: parseFloat(child.dataset.height),
        tube: parseFloat(child.dataset.tube),
        innerRadius: parseFloat(child.dataset.innerRadius),
        outerRadius: parseFloat(child.dataset.outerRadius),
        autoRotate: child.dataset.autoRotate === "true",
        autoRotateSpeed: parseFloat(child.dataset.autoRotateSpeed) || 1,
      };

      const mesh = createPrimitive(THREE, type, config);
      if (mesh) {
        scene.add(mesh);
        canvasRef.objects.set(config.id || mesh.uuid, mesh);

        // Track auto-rotating objects
        if (config.autoRotate) {
          canvasRef.autoRotateObjects.push({
            mesh,
            speed: config.autoRotateSpeed,
          });
        }
      }
    }

    // Model URLs
    if (child.dataset.modelUrl) {
      const url = child.dataset.modelUrl;
      const position = parseVector3(child.dataset.position);
      const rotation = parseVector3(child.dataset.rotation);
      const scale = parseFloat(child.dataset.scale) || 1;
      const autoRotate = child.dataset.autoRotate === "true";
      const id = child.dataset.id || url;

      canvasRef.loaders.gltf.load(url, (gltf) => {
        const model = gltf.scene;
        model.position.set(position.x, position.y, position.z);
        model.rotation.set(rotation.x, rotation.y, rotation.z);
        model.scale.set(scale, scale, scale);
        model.name = id;

        // Auto-center
        const box = new THREE.Box3().setFromObject(model);
        const center = box.getCenter(new THREE.Vector3());
        model.position.sub(center);

        // Shadows
        model.traverse((node) => {
          if (node.isMesh) {
            node.castShadow = true;
            node.receiveShadow = true;
          }
        });

        scene.add(model);
        canvasRef.objects.set(id, model);

        // Auto-rotate
        if (autoRotate) {
          canvasRef.autoRotateObjects.push({ mesh: model, speed: 1 });
        }
      });
    }

    // Custom lights
    if (child.dataset.light) {
      const type = child.dataset.light;
      const color = child.dataset.color || "#ffffff";
      const intensity = parseFloat(child.dataset.intensity) || 1;
      const position = parseVector3(child.dataset.position);

      if (type === "ambient") {
        const light = new THREE.AmbientLight(color, intensity);
        scene.add(light);
      } else if (type === "spot") {
        const light = new THREE.SpotLight(color, intensity);
        light.position.set(position.x, position.y, position.z);
        if (child.dataset.castShadow === "true") {
          light.castShadow = true;
        }
        scene.add(light);
      }
    }
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // create primitive
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Create primitive mesh
 */
const createPrimitive = (THREE, type, config) => {
  let geometry;

  switch (type) {
    case "cube": {
      const size = config.size || 1;
      geometry = new THREE.BoxGeometry(size, size, size);
      break;
    }
    case "sphere": {
      geometry = new THREE.SphereGeometry(config.radius || 1, 32, 16);
      break;
    }
    case "cylinder": {
      geometry = new THREE.CylinderGeometry(
        config.radius || 0.5,
        config.radius || 0.5,
        config.height || 1,
        32
      );
      break;
    }
    case "cone": {
      geometry = new THREE.ConeGeometry(config.radius || 0.5, config.height || 1, 32);
      break;
    }
    case "torus": {
      geometry = new THREE.TorusGeometry(config.radius || 1, config.tube || 0.4, 16, 100);
      break;
    }
    case "ring": {
      geometry = new THREE.RingGeometry(
        config.innerRadius || 0.5,
        config.outerRadius || 1,
        32
      );
      break;
    }
    default:
      return null;
  }

  const material = new THREE.MeshStandardMaterial({
    color: config.color || "#3b82f6",
    metalness: config.metalness || 0.3,
    roughness: config.roughness || 0.5,
  });

  const mesh = new THREE.Mesh(geometry, material);
  mesh.position.set(
    config.position?.x || 0,
    config.position?.y || 0,
    config.position?.z || 0
  );
  mesh.rotation.set(
    config.rotation?.x || 0,
    config.rotation?.y || 0,
    config.rotation?.z || 0
  );
  mesh.name = config.id || "";
  mesh.castShadow = true;
  mesh.receiveShadow = true;

  return mesh;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // parse helpers
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse Vector3 from "x,y,z" string
 */
const parseVector3 = (str) => {
  if (!str) return { x: 0, y: 0, z: 0 };
  const [x, y, z] = str.split(",").map(Number);
  return { x: x || 0, y: y || 0, z: z || 0 };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Auto-initialize canvas3d elements when DOM is ready
 */
const initAllCanvas3D = () => {
  const containers = document.querySelectorAll("[data-canvas3d]");
  for (const container of containers) {
    initCanvas3D(container);
  }
};

// Initialize on DOM ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAllCanvas3D);
  } else {
    initAllCanvas3D();
  }

  // Watch for dynamically added canvas3d elements
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === 1) {
          if (node.hasAttribute?.("data-canvas3d")) {
            initCanvas3D(node);
          }
          const nested = node.querySelectorAll?.("[data-canvas3d]");
          if (nested) {
            for (const nestedContainer of nested) {
              initCanvas3D(nestedContainer);
            }
          }
        }
      }
    }
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
  }
}
