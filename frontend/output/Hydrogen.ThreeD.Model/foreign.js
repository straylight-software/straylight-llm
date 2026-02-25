// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                         // hydrogen // model
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// 3D Model component with GLTF/GLB loading, animations, and inspection tools.

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // model registry
// ═══════════════════════════════════════════════════════════════════════════════

// Store model references by name/id
const modelRegistry = new Map();

/**
 * Get model reference by name or container ID
 */
export const getModelRefImpl = (nameOrId) => () => {
  return modelRegistry.get(nameOrId) || null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // animation api
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Play animation by name
 */
export const playAnimationImpl = (modelRef) => (name) => (loop) => (speed) => () => {
  if (!modelRef || !modelRef.mixer || !modelRef.animations) return null;

  const clip = modelRef.animations.find((c) => c.name === name);
  if (!clip) {
    console.warn(`Animation "${name}" not found`);
    return null;
  }

  const action = modelRef.mixer.clipAction(clip);
  action.setLoop(loop ? 2200 : 2201, loop ? Infinity : 1); // THREE.LoopRepeat : THREE.LoopOnce
  action.timeScale = speed;
  action.reset();
  action.play();

  modelRef.currentAction = action;
  return action;
};

/**
 * Pause current animation
 */
export const pauseAnimationImpl = (modelRef) => () => {
  if (modelRef && modelRef.currentAction) {
    modelRef.currentAction.paused = true;
  }
};

/**
 * Stop current animation
 */
export const stopAnimationImpl = (modelRef) => () => {
  if (modelRef && modelRef.currentAction) {
    modelRef.currentAction.stop();
    modelRef.currentAction = null;
  }
};

/**
 * Set animation time (seek)
 */
export const setAnimationTimeImpl = (modelRef) => (time) => () => {
  if (modelRef && modelRef.currentAction) {
    modelRef.currentAction.time = time;
  }
};

/**
 * Set animation playback speed
 */
export const setAnimationSpeedImpl = (modelRef) => (speed) => () => {
  if (modelRef && modelRef.currentAction) {
    modelRef.currentAction.timeScale = speed;
  }
};

/**
 * Get list of animation clip names
 */
export const getAnimationClipsImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.animations) return [];
  return modelRef.animations.map((clip) => clip.name);
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // model info
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get model information (vertices, faces, etc.)
 */
export const getModelInfoImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.model) {
    return {
      vertices: 0,
      faces: 0,
      meshes: 0,
      materials: 0,
      textures: 0,
      animations: [],
      boundingBox: {
        min: { x: 0, y: 0, z: 0 },
        max: { x: 0, y: 0, z: 0 },
        size: { x: 0, y: 0, z: 0 },
        center: { x: 0, y: 0, z: 0 },
      },
      hasAnimations: false,
    };
  }

  let vertices = 0;
  let faces = 0;
  let meshes = 0;
  const materials = new Set();
  const textures = new Set();

  modelRef.model.traverse((node) => {
    if (node.isMesh) {
      meshes++;
      if (node.geometry) {
        const geo = node.geometry;
        if (geo.attributes.position) {
          vertices += geo.attributes.position.count;
        }
        if (geo.index) {
          faces += geo.index.count / 3;
        } else if (geo.attributes.position) {
          faces += geo.attributes.position.count / 3;
        }
      }
      if (node.material) {
        if (Array.isArray(node.material)) {
          node.material.forEach((m) => {
            materials.add(m);
            collectTextures(m, textures);
          });
        } else {
          materials.add(node.material);
          collectTextures(node.material, textures);
        }
      }
    }
  });

  const box = modelRef.boundingBox || {
    min: { x: 0, y: 0, z: 0 },
    max: { x: 0, y: 0, z: 0 },
  };
  const size = {
    x: box.max.x - box.min.x,
    y: box.max.y - box.min.y,
    z: box.max.z - box.min.z,
  };
  const center = {
    x: (box.min.x + box.max.x) / 2,
    y: (box.min.y + box.max.y) / 2,
    z: (box.min.z + box.max.z) / 2,
  };

  return {
    vertices,
    faces: Math.floor(faces),
    meshes,
    materials: materials.size,
    textures: textures.size,
    animations: modelRef.animations ? modelRef.animations.map((c) => c.name) : [],
    boundingBox: { min: box.min, max: box.max, size, center },
    hasAnimations: modelRef.animations && modelRef.animations.length > 0,
  };
};

/**
 * Collect textures from material
 */
const collectTextures = (material, textures) => {
  const textureProps = [
    "map",
    "normalMap",
    "roughnessMap",
    "metalnessMap",
    "aoMap",
    "emissiveMap",
    "bumpMap",
    "displacementMap",
    "alphaMap",
    "envMap",
  ];

  for (const prop of textureProps) {
    if (material[prop]) {
      textures.add(material[prop]);
    }
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // transform api
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Set model position
 */
export const setPositionImpl = (modelRef) => (position) => () => {
  if (modelRef && modelRef.model) {
    modelRef.model.position.set(position.x, position.y, position.z);
  }
};

/**
 * Set model rotation
 */
export const setRotationImpl = (modelRef) => (rotation) => () => {
  if (modelRef && modelRef.model) {
    modelRef.model.rotation.set(rotation.x, rotation.y, rotation.z);
  }
};

/**
 * Set model scale (uniform)
 */
export const setScaleImpl = (modelRef) => (scale) => () => {
  if (modelRef && modelRef.model) {
    modelRef.model.scale.set(scale, scale, scale);
  }
};

/**
 * Get model position
 */
export const getPositionImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.model) {
    return { x: 0, y: 0, z: 0 };
  }
  const pos = modelRef.model.position;
  return { x: pos.x, y: pos.y, z: pos.z };
};

/**
 * Get model rotation
 */
export const getRotationImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.model) {
    return { x: 0, y: 0, z: 0 };
  }
  const rot = modelRef.model.rotation;
  return { x: rot.x, y: rot.y, z: rot.z };
};

/**
 * Get model scale
 */
export const getScaleImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.model) {
    return 1;
  }
  return modelRef.model.scale.x;
};

/**
 * Get model bounding box
 */
export const getBoundingBoxImpl = (modelRef) => () => {
  if (!modelRef || !modelRef.boundingBox) {
    return {
      min: { x: 0, y: 0, z: 0 },
      max: { x: 0, y: 0, z: 0 },
      size: { x: 0, y: 0, z: 0 },
      center: { x: 0, y: 0, z: 0 },
    };
  }
  const box = modelRef.boundingBox;
  const size = {
    x: box.max.x - box.min.x,
    y: box.max.y - box.min.y,
    z: box.max.z - box.min.z,
  };
  const center = {
    x: (box.min.x + box.max.x) / 2,
    y: (box.min.y + box.max.y) / 2,
    z: (box.min.z + box.max.z) / 2,
  };
  return { min: box.min, max: box.max, size, center };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // model initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize model viewer from container element
 */
const initModelViewer = async (container) => {
  if (container._modelInitialized) return;
  container._modelInitialized = true;

  // Dynamically import Three.js and loaders
  const THREE = await import("three");
  const { GLTFLoader } = await import(
    "three/examples/jsm/loaders/GLTFLoader.js"
  );
  const { DRACOLoader } = await import(
    "three/examples/jsm/loaders/DRACOLoader.js"
  );

  // Get configuration from data attributes
  const url = container.dataset.modelUrl;
  if (!url) {
    console.error("No model URL provided");
    return;
  }

  const position = parseVector3(container.dataset.modelPosition);
  const rotation = parseVector3(container.dataset.modelRotation);
  const scale = parseFloat(container.dataset.modelScale) || 1;
  const autoCenter = container.dataset.autoCenter !== "false";
  const autoScale = container.dataset.autoScale === "true";
  const targetSize = parseFloat(container.dataset.targetSize) || 2;
  const castShadow = container.dataset.castShadow !== "false";
  const receiveShadow = container.dataset.receiveShadow !== "false";
  const wireframe = container.dataset.wireframe === "true";
  const showBbox = container.dataset.showBbox === "true";
  const animationLoop = container.dataset.animationLoop !== "false";
  const animationSpeed = parseFloat(container.dataset.animationSpeed) || 1;
  const modelName = container.dataset.modelName || url;

  // Set up DRACO loader for compressed models
  const dracoLoader = new DRACOLoader();
  dracoLoader.setDecoderPath(
    "https://www.gstatic.com/draco/versioned/decoders/1.5.6/"
  );

  // Set up GLTF loader
  const loader = new GLTFLoader();
  loader.setDRACOLoader(dracoLoader);

  // Find parent scene (if model is inside a Scene component)
  const parentScene = container.closest("[data-threejs-scene]");
  let sceneRef = null;

  if (parentScene && parentScene._sceneRef) {
    sceneRef = parentScene._sceneRef;
  }

  // Load the model
  loader.load(
    url,
    (gltf) => {
      const model = gltf.scene;

      // Calculate bounding box
      const box = new THREE.Box3().setFromObject(model);
      const boundingBox = {
        min: { x: box.min.x, y: box.min.y, z: box.min.z },
        max: { x: box.max.x, y: box.max.y, z: box.max.z },
      };

      // Auto-center
      if (autoCenter) {
        const center = box.getCenter(new THREE.Vector3());
        model.position.sub(center);
        // Recalculate after centering
        box.setFromObject(model);
      }

      // Auto-scale to target size
      if (autoScale) {
        const size = box.getSize(new THREE.Vector3());
        const maxDim = Math.max(size.x, size.y, size.z);
        if (maxDim > 0) {
          const scaleFactor = targetSize / maxDim;
          model.scale.multiplyScalar(scaleFactor);
        }
      }

      // Apply transforms
      model.position.add(new THREE.Vector3(position.x, position.y, position.z));
      model.rotation.set(rotation.x, rotation.y, rotation.z);
      model.scale.multiplyScalar(scale);

      // Set up shadows
      model.traverse((node) => {
        if (node.isMesh) {
          node.castShadow = castShadow;
          node.receiveShadow = receiveShadow;

          // Wireframe mode
          if (wireframe && node.material) {
            if (Array.isArray(node.material)) {
              node.material.forEach((m) => {
                m.wireframe = true;
              });
            } else {
              node.material.wireframe = true;
            }
          }
        }
      });

      // Apply material override if specified
      const materialOverrideEl = container.querySelector(
        "[data-material-override]"
      );
      if (materialOverrideEl) {
        const overrideStr = materialOverrideEl.dataset.materialOverride;
        const override = parseMaterialOverride(overrideStr);
        applyMaterialOverride(model, override);
      }

      // Set up animation mixer
      let mixer = null;
      if (gltf.animations && gltf.animations.length > 0) {
        mixer = new THREE.AnimationMixer(model);

        // Auto-play animation if specified
        const playAnimEl = container.querySelector("[data-play-animation]");
        if (playAnimEl) {
          const animName = playAnimEl.dataset.playAnimation;
          const clip = gltf.animations.find((c) => c.name === animName);
          if (clip) {
            const action = mixer.clipAction(clip);
            action.setLoop(animationLoop ? 2200 : 2201);
            action.timeScale = animationSpeed;
            action.play();
          }
        }
      }

      // Create model reference
      const modelRef = {
        model,
        mixer,
        animations: gltf.animations || [],
        boundingBox,
        currentAction: null,
        THREE,
      };

      // Register the model
      modelRegistry.set(modelName, modelRef);
      container._modelRef = modelRef;

      // Add to scene if parent scene exists
      if (sceneRef && sceneRef.scene) {
        sceneRef.scene.add(model);
        sceneRef.objects.set(modelName, model);

        // Add to animation loop
        if (mixer) {
          const clock = new THREE.Clock();
          sceneRef.animationCallbacks.push(() => {
            mixer.update(clock.getDelta());
          });
        }
      }

      // Show bounding box if enabled
      if (showBbox) {
        const boxHelper = new THREE.BoxHelper(model, 0x00ff00);
        if (sceneRef && sceneRef.scene) {
          sceneRef.scene.add(boxHelper);
        }
      }

      // Dispatch load event
      container.dispatchEvent(
        new CustomEvent("model:loaded", {
          detail: { modelRef, url },
        })
      );

      // Dispatch model info event
      container.dispatchEvent(
        new CustomEvent("model:info", {
          detail: getModelInfoImpl(modelRef)(),
        })
      );
    },
    (progress) => {
      const percent =
        progress.total > 0 ? (progress.loaded / progress.total) * 100 : 0;
      container.dispatchEvent(
        new CustomEvent("model:progress", {
          detail: {
            loaded: progress.loaded,
            total: progress.total,
            percent,
          },
        })
      );
    },
    (error) => {
      console.error("Error loading model:", error);
      container.dispatchEvent(
        new CustomEvent("model:error", {
          detail: {
            message: error.message || "Failed to load model",
            url,
          },
        })
      );
    }
  );
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

/**
 * Parse material override from "key=value;key=value" string
 */
const parseMaterialOverride = (str) => {
  if (!str) return {};
  const override = {};
  const pairs = str.split(";").filter((s) => s.length > 0);
  for (const pair of pairs) {
    const [key, value] = pair.split("=");
    if (key && value) {
      // Parse value type
      if (value === "true") {
        override[key] = true;
      } else if (value === "false") {
        override[key] = false;
      } else if (!isNaN(parseFloat(value))) {
        override[key] = parseFloat(value);
      } else {
        override[key] = value;
      }
    }
  }
  return override;
};

/**
 * Apply material override to model
 */
const applyMaterialOverride = (model, override) => {
  model.traverse((node) => {
    if (node.isMesh && node.material) {
      const applyToMaterial = (material) => {
        if (override.color !== undefined) {
          material.color.set(override.color);
        }
        if (override.metalness !== undefined) {
          material.metalness = override.metalness;
        }
        if (override.roughness !== undefined) {
          material.roughness = override.roughness;
        }
        if (override.emissive !== undefined) {
          material.emissive.set(override.emissive);
        }
        if (override.emissiveIntensity !== undefined) {
          material.emissiveIntensity = override.emissiveIntensity;
        }
        if (override.opacity !== undefined) {
          material.opacity = override.opacity;
        }
        if (override.transparent !== undefined) {
          material.transparent = override.transparent;
        }
        if (override.envMapIntensity !== undefined) {
          material.envMapIntensity = override.envMapIntensity;
        }
        material.needsUpdate = true;
      };

      if (Array.isArray(node.material)) {
        node.material.forEach(applyToMaterial);
      } else {
        applyToMaterial(node.material);
      }
    }
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Auto-initialize model viewers when DOM is ready
 */
const initAllModelViewers = () => {
  const containers = document.querySelectorAll("[data-model-viewer]");
  for (const container of containers) {
    initModelViewer(container);
  }
};

// Initialize on DOM ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAllModelViewers);
  } else {
    initAllModelViewers();
  }

  // Watch for dynamically added model viewers
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === 1) {
          if (node.hasAttribute?.("data-model-viewer")) {
            initModelViewer(node);
          }
          const nested = node.querySelectorAll?.("[data-model-viewer]");
          if (nested) {
            for (const nestedContainer of nested) {
              initModelViewer(nestedContainer);
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
