// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                         // hydrogen // scene
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Three.js Scene wrapper component
// Provides comprehensive 3D scene management with cameras, lighting,
// controls, post-processing, model loading, and WebXR support.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // utility exports
// ═══════════════════════════════════════════════════════════════════════════════

export const intercalateImpl = (sep) => (arr) => arr.join(sep);

export const unsafeToForeign = (x) => x;

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // scene registry
// ═══════════════════════════════════════════════════════════════════════════════

// Store scene instances by container ID
const sceneRegistry = new Map();

/**
 * Get scene reference by container ID
 */
export const getSceneRefImpl = (containerId) => () => {
  return sceneRegistry.get(containerId) || null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                             // scene management
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Add object to scene
 */
export const addObjectImpl = (sceneRef) => (object) => () => {
  if (sceneRef && sceneRef.scene && object) {
    sceneRef.scene.add(object);
  }
};

/**
 * Remove object from scene
 */
export const removeObjectImpl = (sceneRef) => (object) => () => {
  if (sceneRef && sceneRef.scene && object) {
    sceneRef.scene.remove(object);
    // Dispose geometry and material
    if (object.geometry) object.geometry.dispose();
    if (object.material) {
      if (Array.isArray(object.material)) {
        for (const m of object.material) {
          m.dispose();
        }
      } else {
        object.material.dispose();
      }
    }
  }
};

/**
 * Update camera position and look-at
 */
export const updateCameraImpl = (sceneRef) => (position) => (lookAt) => () => {
  if (sceneRef && sceneRef.camera) {
    sceneRef.camera.position.set(position.x, position.y, position.z);
    sceneRef.camera.lookAt(lookAt.x, lookAt.y, lookAt.z);
  }
};

/**
 * Set scene background
 */
export const setBackgroundImpl = (sceneRef) => (backgroundStr) => () => {
  if (!sceneRef || !sceneRef.scene || !sceneRef.THREE) return;

  const THREE = sceneRef.THREE;
  const [type, ...rest] = backgroundStr.split(":");
  const value = rest.join(":");

  switch (type) {
    case "color":
      sceneRef.scene.background = new THREE.Color(value);
      break;
    case "transparent":
      sceneRef.scene.background = null;
      break;
    case "skybox": {
      const urls = value.split(",");
      if (urls.length === 6) {
        const loader = new THREE.CubeTextureLoader();
        loader.load(urls, (texture) => {
          sceneRef.scene.background = texture;
          sceneRef.scene.environment = texture;
        });
      }
      break;
    }
    case "hdr":
      // Would need RGBELoader for HDR
      break;
  }
};

/**
 * Resize renderer
 */
export const resizeImpl = (sceneRef) => (width) => (height) => () => {
  if (!sceneRef) return;

  const { renderer, camera } = sceneRef;

  if (renderer) {
    renderer.setSize(width, height);
  }

  if (camera) {
    if (camera.isPerspectiveCamera) {
      camera.aspect = width / height;
    } else if (camera.isOrthographicCamera) {
      const aspectRatio = width / height;
      const camHeight = camera.top - camera.bottom;
      camera.left = (-camHeight * aspectRatio) / 2;
      camera.right = (camHeight * aspectRatio) / 2;
    }
    camera.updateProjectionMatrix();
  }

  // Update composer if using post-processing
  if (sceneRef.composer) {
    sceneRef.composer.setSize(width, height);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                 // screenshot
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Take screenshot of the scene
 */
export const takeScreenshotImpl = (sceneRef) => (config) => () => {
  if (!sceneRef || !sceneRef.renderer) return "";

  const { renderer, scene, camera } = sceneRef;
  const format = config.format || "png";
  const quality = config.quality || 0.92;

  // If custom dimensions, need to resize temporarily
  const originalSize = renderer.getSize(new sceneRef.THREE.Vector2());
  const width = config.width || originalSize.x;
  const height = config.height || originalSize.y;

  if (width !== originalSize.x || height !== originalSize.y) {
    renderer.setSize(width, height);
    if (camera.isPerspectiveCamera) {
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    }
  }

  // Render and capture
  renderer.render(scene, camera);
  const mimeType = `image/${format}`;
  const dataUrl = renderer.domElement.toDataURL(mimeType, quality);

  // Restore original size
  if (width !== originalSize.x || height !== originalSize.y) {
    renderer.setSize(originalSize.x, originalSize.y);
    if (camera.isPerspectiveCamera) {
      camera.aspect = originalSize.x / originalSize.y;
      camera.updateProjectionMatrix();
    }
  }

  return dataUrl;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // scene initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize Three.js scene from container element
 */
const initScene = async (container) => {
  if (container._sceneInitialized) return;
  container._sceneInitialized = true;

  // Dynamically import Three.js
  const THREE = await import("three");
  const { OrbitControls } = await import(
    "three/examples/jsm/controls/OrbitControls.js"
  );
  const { GLTFLoader } = await import(
    "three/examples/jsm/loaders/GLTFLoader.js"
  );

  // Get configuration from data attributes
  const width = parseInt(container.dataset.sceneWidth) || 800;
  const height = parseInt(container.dataset.sceneHeight) || 600;
  const backgroundStr = container.dataset.sceneBackground || "color:#000000";
  const shadows = container.dataset.sceneShadows === "true";
  const antialias = container.dataset.sceneAntialias !== "false";
  const toneMapping = container.dataset.sceneTonemapping || "ACESFilmic";
  const exposure = parseFloat(container.dataset.sceneExposure) || 1.0;
  const responsive = container.dataset.sceneResponsive !== "false";

  // Create scene
  const scene = new THREE.Scene();

  // Set background
  const [bgType, ...bgRest] = backgroundStr.split(":");
  const bgValue = bgRest.join(":");
  switch (bgType) {
    case "color":
      scene.background = new THREE.Color(bgValue);
      break;
    case "transparent":
      scene.background = null;
      break;
    case "skybox": {
      const urls = bgValue.split(",");
      if (urls.length === 6) {
        const loader = new THREE.CubeTextureLoader();
        loader.load(urls, (texture) => {
          scene.background = texture;
          scene.environment = texture;
        });
      }
      break;
    }
  }

  // Get canvas
  const canvas = container.querySelector("[data-threejs-canvas]");
  if (!canvas) return;

  // Create renderer
  const renderer = new THREE.WebGLRenderer({
    canvas: canvas,
    antialias: antialias,
    alpha: bgType === "transparent",
  });
  renderer.setSize(width, height);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // Shadows
  if (shadows) {
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  }

  // Tone mapping
  const toneMappingMap = {
    ACESFilmic: THREE.ACESFilmicToneMapping,
    Linear: THREE.LinearToneMapping,
    Reinhard: THREE.ReinhardToneMapping,
    Cineon: THREE.CineonToneMapping,
    NoToneMapping: THREE.NoToneMapping,
  };
  renderer.toneMapping = toneMappingMap[toneMapping] || THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = exposure;

  // Default camera (will be overridden by scene children)
  let camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
  camera.position.set(0, 5, 10);

  // Controls
  let controls = null;

  // Scene reference
  const sceneRef = {
    THREE,
    scene,
    camera,
    renderer,
    controls,
    composer: null,
    animationCallbacks: [],
    objects: new Map(),
    loaders: { gltf: new GLTFLoader() },
  };

  // Generate unique ID for registry
  const sceneId =
    container.id || `scene-${Math.random().toString(36).substr(2, 9)}`;
  container.id = sceneId;
  sceneRegistry.set(sceneId, sceneRef);

  // Parse scene children
  const childrenContainer = container.querySelector("[data-scene-children]");
  if (childrenContainer) {
    parseSceneChildren(sceneRef, childrenContainer, OrbitControls);
  }

  // Raycasting setup
  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();
  let hoveredObject = null;

  const onMouseMove = (event) => {
    const rect = canvas.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  };

  const onMouseClick = (event) => {
    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObjects(scene.children, true);
    if (intersects.length > 0) {
      const hit = intersects[0];
      container.dispatchEvent(
        new CustomEvent("scene:objectclick", {
          detail: {
            object: hit.object,
            objectName: hit.object.name || "",
            point: { x: hit.point.x, y: hit.point.y, z: hit.point.z },
            normal: hit.face
              ? { x: hit.face.normal.x, y: hit.face.normal.y, z: hit.face.normal.z }
              : { x: 0, y: 1, z: 0 },
            distance: hit.distance,
            faceIndex: hit.faceIndex || 0,
            userData: hit.object.userData || {},
          },
        })
      );
    }
  };

  canvas.addEventListener("mousemove", onMouseMove);
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
    const elapsed = clock.getElapsedTime();

    // Update controls
    if (controls && controls.update) {
      controls.update(delta);
    }

    // Run animation callbacks
    for (const cb of sceneRef.animationCallbacks) {
      cb(elapsed);
    }

    // Render
    if (sceneRef.composer) {
      sceneRef.composer.render(delta);
    } else {
      renderer.render(scene, camera);
    }
  };

  animate();

  // Cleanup on removal
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.removedNodes) {
        if (node === container || node.contains?.(container)) {
          cancelAnimationFrame(animationId);
          renderer.dispose();
          sceneRegistry.delete(sceneId);
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
//                                                       // parse scene children
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse scene children from DOM elements
 */
const parseSceneChildren = (sceneRef, container, OrbitControls) => {
  const { THREE, scene, renderer, camera } = sceneRef;

  for (const child of container.children) {
    // Camera
    if (child.dataset.camera) {
      const cameraType = child.dataset.camera;
      const position = parseVector3(child.dataset.position);
      const lookAt = parseVector3(child.dataset.lookat);

      if (cameraType === "perspective") {
        const fov = parseFloat(child.dataset.fov) || 75;
        const near = parseFloat(child.dataset.near) || 0.1;
        const far = parseFloat(child.dataset.far) || 1000;
        const aspect = renderer.domElement.width / renderer.domElement.height;

        sceneRef.camera = new THREE.PerspectiveCamera(fov, aspect, near, far);
      } else if (cameraType === "orthographic") {
        const left = parseFloat(child.dataset.left) || -10;
        const right = parseFloat(child.dataset.right) || 10;
        const top = parseFloat(child.dataset.top) || 10;
        const bottom = parseFloat(child.dataset.bottom) || -10;
        const near = parseFloat(child.dataset.near) || 0.1;
        const far = parseFloat(child.dataset.far) || 1000;
        const zoom = parseFloat(child.dataset.zoom) || 1;

        sceneRef.camera = new THREE.OrthographicCamera(
          left,
          right,
          top,
          bottom,
          near,
          far
        );
        sceneRef.camera.zoom = zoom;
      }

      sceneRef.camera.position.set(position.x, position.y, position.z);
      sceneRef.camera.lookAt(lookAt.x, lookAt.y, lookAt.z);
    }

    // Controls
    if (child.dataset.controls) {
      const controlsType = child.dataset.controls;

      if (controlsType === "orbit") {
        sceneRef.controls = new OrbitControls(
          sceneRef.camera,
          renderer.domElement
        );
        sceneRef.controls.enableDamping =
          child.dataset.enableDamping === "true";
        sceneRef.controls.dampingFactor =
          parseFloat(child.dataset.dampingFactor) || 0.05;
        sceneRef.controls.enableZoom = child.dataset.enableZoom !== "false";
        sceneRef.controls.enablePan = child.dataset.enablePan !== "false";
        sceneRef.controls.enableRotate = child.dataset.enableRotate !== "false";
        sceneRef.controls.autoRotate = child.dataset.autoRotate === "true";
        sceneRef.controls.autoRotateSpeed =
          parseFloat(child.dataset.autoRotateSpeed) || 2.0;
      }
    }

    // Lights
    if (child.dataset.light) {
      const lightType = child.dataset.light;
      const color = child.dataset.color || "#ffffff";
      const intensity = parseFloat(child.dataset.intensity) || 1;

      let light;

      switch (lightType) {
        case "ambient":
          light = new THREE.AmbientLight(color, intensity);
          break;
        case "directional": {
          light = new THREE.DirectionalLight(color, intensity);
          const dirPos = parseVector3(child.dataset.position);
          light.position.set(dirPos.x, dirPos.y, dirPos.z);
          if (child.dataset.castShadow === "true") {
            light.castShadow = true;
            light.shadow.mapSize.width =
              parseInt(child.dataset.shadowMapSize) || 1024;
            light.shadow.mapSize.height =
              parseInt(child.dataset.shadowMapSize) || 1024;
            light.shadow.camera.near = 0.5;
            light.shadow.camera.far = 500;
            light.shadow.camera.left = -50;
            light.shadow.camera.right = 50;
            light.shadow.camera.top = 50;
            light.shadow.camera.bottom = -50;
          }
          break;
        }
        case "point": {
          light = new THREE.PointLight(
            color,
            intensity,
            parseFloat(child.dataset.distance) || 0,
            parseFloat(child.dataset.decay) || 2
          );
          const pointPos = parseVector3(child.dataset.position);
          light.position.set(pointPos.x, pointPos.y, pointPos.z);
          if (child.dataset.castShadow === "true") {
            light.castShadow = true;
          }
          break;
        }
        case "spot": {
          light = new THREE.SpotLight(
            color,
            intensity,
            parseFloat(child.dataset.distance) || 0,
            parseFloat(child.dataset.angle) || Math.PI / 3,
            parseFloat(child.dataset.penumbra) || 0,
            parseFloat(child.dataset.decay) || 2
          );
          const spotPos = parseVector3(child.dataset.position);
          light.position.set(spotPos.x, spotPos.y, spotPos.z);
          if (child.dataset.castShadow === "true") {
            light.castShadow = true;
          }
          break;
        }
        case "hemisphere":
          light = new THREE.HemisphereLight(
            child.dataset.skyColor || "#ffffff",
            child.dataset.groundColor || "#444444",
            intensity
          );
          break;
      }

      if (light) {
        scene.add(light);
      }
    }

    // Primitives
    if (child.dataset.primitive) {
      const primType = child.dataset.primitive;
      const position = parseVector3(child.dataset.position);
      const rotation = parseVector3(child.dataset.rotation);
      const materialStr = child.dataset.material || "basic:#ffffff:1:false:false";
      const material = parseMaterial(THREE, materialStr);

      let geometry;

      switch (primType) {
        case "box": {
          const size = parseVector3(child.dataset.size);
          geometry = new THREE.BoxGeometry(size.x, size.y, size.z);
          break;
        }
        case "sphere":
          geometry = new THREE.SphereGeometry(
            parseFloat(child.dataset.radius) || 1,
            parseInt(child.dataset.widthSegments) || 32,
            parseInt(child.dataset.heightSegments) || 16
          );
          break;
        case "plane":
          geometry = new THREE.PlaneGeometry(
            parseFloat(child.dataset.width) || 1,
            parseFloat(child.dataset.height) || 1
          );
          break;
        case "cylinder":
          geometry = new THREE.CylinderGeometry(
            parseFloat(child.dataset.radiusTop) || 1,
            parseFloat(child.dataset.radiusBottom) || 1,
            parseFloat(child.dataset.height) || 1,
            parseInt(child.dataset.radialSegments) || 32
          );
          break;
        case "cone":
          geometry = new THREE.ConeGeometry(
            parseFloat(child.dataset.radius) || 1,
            parseFloat(child.dataset.height) || 1,
            parseInt(child.dataset.radialSegments) || 32
          );
          break;
        case "torus":
          geometry = new THREE.TorusGeometry(
            parseFloat(child.dataset.radius) || 1,
            parseFloat(child.dataset.tube) || 0.4,
            parseInt(child.dataset.radialSegments) || 16,
            parseInt(child.dataset.tubularSegments) || 100
          );
          break;
        case "torusknot":
          geometry = new THREE.TorusKnotGeometry(
            parseFloat(child.dataset.radius) || 1,
            parseFloat(child.dataset.tube) || 0.4,
            parseInt(child.dataset.tubularSegments) || 100,
            parseInt(child.dataset.radialSegments) || 16,
            parseInt(child.dataset.p) || 2,
            parseInt(child.dataset.q) || 3
          );
          break;
        case "ring":
          geometry = new THREE.RingGeometry(
            parseFloat(child.dataset.innerRadius) || 0.5,
            parseFloat(child.dataset.outerRadius) || 1,
            parseInt(child.dataset.thetaSegments) || 32
          );
          break;
        case "circle":
          geometry = new THREE.CircleGeometry(
            parseFloat(child.dataset.radius) || 1,
            parseInt(child.dataset.segments) || 32
          );
          break;
      }

      if (geometry) {
        const mesh = new THREE.Mesh(geometry, material);
        mesh.position.set(position.x, position.y, position.z);
        mesh.rotation.set(rotation.x, rotation.y, rotation.z);
        mesh.name = child.dataset.name || "";
        mesh.castShadow = child.dataset.castShadow === "true";
        mesh.receiveShadow = child.dataset.receiveShadow === "true";
        scene.add(mesh);
        sceneRef.objects.set(mesh.name || mesh.uuid, mesh);
      }
    }

    // Helpers
    if (child.dataset.helper) {
      const helperType = child.dataset.helper;

      if (helperType === "grid") {
        const size = parseFloat(child.dataset.size) || 10;
        const divisions = parseInt(child.dataset.divisions) || 10;
        const colorCenter = child.dataset.colorCenter || "#444444";
        const colorGrid = child.dataset.colorGrid || "#888888";
        const grid = new THREE.GridHelper(size, divisions, colorCenter, colorGrid);
        scene.add(grid);
      } else if (helperType === "axes") {
        const size = parseFloat(child.dataset.size) || 5;
        const axes = new THREE.AxesHelper(size);
        scene.add(axes);
      }
    }

    // Models
    if (child.dataset.model) {
      const modelType = child.dataset.model;
      const url = child.dataset.url;
      const position = parseVector3(child.dataset.position);
      const rotation = parseVector3(child.dataset.rotation);
      const scale = parseFloat(child.dataset.scale) || 1;

      if (modelType === "gltf" && url) {
        sceneRef.loaders.gltf.load(
          url,
          (gltf) => {
            const model = gltf.scene;
            model.position.set(position.x, position.y, position.z);
            model.rotation.set(rotation.x, rotation.y, rotation.z);
            model.scale.set(scale, scale, scale);
            model.name = child.dataset.name || url;

            // Auto-center
            if (child.dataset.autoCenter === "true") {
              const box = new THREE.Box3().setFromObject(model);
              const center = box.getCenter(new THREE.Vector3());
              model.position.sub(center);
            }

            // Shadows
            if (child.dataset.castShadow === "true") {
              model.traverse((node) => {
                if (node.isMesh) node.castShadow = true;
              });
            }
            if (child.dataset.receiveShadow === "true") {
              model.traverse((node) => {
                if (node.isMesh) node.receiveShadow = true;
              });
            }

            scene.add(model);
            sceneRef.objects.set(model.name, model);

            // Dispatch load event
            container.dispatchEvent(
              new CustomEvent("model:loaded", { detail: { model, url } })
            );
          },
          (progress) => {
            container.dispatchEvent(
              new CustomEvent("model:progress", {
                detail: {
                  loaded: progress.loaded,
                  total: progress.total,
                  percent:
                    progress.total > 0
                      ? (progress.loaded / progress.total) * 100
                      : 0,
                },
              })
            );
          },
          (error) => {
            console.error("Error loading model:", error);
            container.dispatchEvent(
              new CustomEvent("model:error", { detail: { error: error.message, url } })
            );
          }
        );
      }
    }

    // Stats
    if (child.dataset.stats) {
      import("three/examples/jsm/libs/stats.module.js").then(({ default: Stats }) => {
        const stats = new Stats();
        const position = child.dataset.position || "top-left";
        stats.dom.style.position = "absolute";
        
        switch (position) {
          case "top-left":
            stats.dom.style.top = "0";
            stats.dom.style.left = "0";
            break;
          case "top-right":
            stats.dom.style.top = "0";
            stats.dom.style.right = "0";
            stats.dom.style.left = "auto";
            break;
          case "bottom-left":
            stats.dom.style.bottom = "0";
            stats.dom.style.top = "auto";
            stats.dom.style.left = "0";
            break;
          case "bottom-right":
            stats.dom.style.bottom = "0";
            stats.dom.style.top = "auto";
            stats.dom.style.right = "0";
            stats.dom.style.left = "auto";
            break;
        }
        
        container.appendChild(stats.dom);
        sceneRef.animationCallbacks.push(() => stats.update());
      });
    }
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // parse helpers
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse Vector3 from "x,y,z" string
 */
const parseVector3 = (str) => {
  if (!str) return { x: 0, y: 0, z: 0 };
  const [x, y, z] = str.split(",").map(Number);
  return { x: x || 0, y: y || 0, z: z || 0 };
};

/**
 * Parse material from string "type:color:opacity:transparent:wireframe"
 */
const parseMaterial = (THREE, str) => {
  const [type, color, opacity, transparent, wireframe] = str.split(":");
  const config = {
    color: color || "#ffffff",
    opacity: parseFloat(opacity) || 1,
    transparent: transparent === "true",
    wireframe: wireframe === "true",
  };

  switch (type) {
    case "basic":
      return new THREE.MeshBasicMaterial(config);
    case "standard":
      return new THREE.MeshStandardMaterial({
        ...config,
        roughness: 0.5,
        metalness: 0.5,
      });
    case "phong":
      return new THREE.MeshPhongMaterial({ ...config, shininess: 30 });
    case "physical":
      return new THREE.MeshPhysicalMaterial({
        ...config,
        roughness: 0.5,
        metalness: 0.5,
        clearcoat: 0.3,
      });
    default:
      return new THREE.MeshStandardMaterial(config);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Auto-initialize scenes when DOM is ready
 */
const initAllScenes = () => {
  const containers = document.querySelectorAll("[data-threejs-scene]");
  containers.forEach((container) => {
    initScene(container);
  });
};

// Initialize on DOM ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAllScenes);
  } else {
    initAllScenes();
  }

  // Watch for dynamically added scenes
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === 1) {
          if (node.hasAttribute?.("data-threejs-scene")) {
            initScene(node);
          }
          const nested = node.querySelectorAll?.("[data-threejs-scene]");
          if (nested) {
            for (const nestedContainer of nested) {
              initScene(nestedContainer);
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
