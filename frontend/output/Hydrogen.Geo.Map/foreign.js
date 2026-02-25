// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                            // hydrogen // map
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Interactive map component with Leaflet-style API
// Supports tile layers, markers, shapes, GeoJSON, and drawing tools

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // map instances
// ═══════════════════════════════════════════════════════════════════════════════

const mapInstances = new WeakMap();

/**
 * Check if Leaflet is available
 */
const hasLeaflet = () => typeof L !== "undefined";

/**
 * Load Leaflet dynamically if not available
 */
const loadLeaflet = async () => {
  if (hasLeaflet()) return;

  // Load CSS
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
  document.head.appendChild(link);

  // Load JS
  await new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // map initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize map on element
 */
export const initMapImpl = (element, config) => async () => {
  await loadLeaflet();

  // Create map container if needed
  let container = element.querySelector(".leaflet-container");
  if (!container) {
    container = document.createElement("div");
    container.style.width = "100%";
    container.style.height = "100%";
    element.innerHTML = "";
    element.appendChild(container);
  }

  // Initialize Leaflet map
  const map = L.map(container, {
    center: [config.center.lat, config.center.lng],
    zoom: config.zoom,
    minZoom: config.minZoom,
    maxZoom: config.maxZoom,
    zoomControl: false,
    attributionControl: config.attributionControl,
  });

  // Add tile layer
  L.tileLayer(config.tileLayer.url, {
    attribution: config.tileLayer.attribution,
    maxZoom: config.tileLayer.maxZoom,
  }).addTo(map);

  // Add zoom control if enabled
  if (config.zoomControl) {
    L.control
      .zoom({
        position: config.zoomControlPosition || "topright",
      })
      .addTo(map);
  }

  // Add scale control if enabled
  if (config.scaleControl) {
    L.control.scale().addTo(map);
  }

  // Apply max bounds if set
  if (config.maxBounds) {
    map.setMaxBounds([
      [config.maxBounds.southWest.lat, config.maxBounds.southWest.lng],
      [config.maxBounds.northEast.lat, config.maxBounds.northEast.lng],
    ]);
  }

  // Fit to bounds if set
  if (config.fitBounds) {
    map.fitBounds([
      [config.fitBounds.southWest.lat, config.fitBounds.southWest.lng],
      [config.fitBounds.northEast.lat, config.fitBounds.northEast.lng],
    ]);
  }

  // Add markers
  const markers = [];
  for (const markerConfig of config.markers || []) {
    const m = createMarker(map, markerConfig, config);
    markers.push(m);
  }

  // Add marker cluster if configured
  if (config.markerCluster) {
    await loadMarkerCluster();
    const cluster = L.markerClusterGroup({
      maxClusterRadius: config.markerCluster.radius,
      disableClusteringAtZoom: config.markerCluster.maxZoom,
    });

    for (const markerConfig of config.markerCluster.markers || []) {
      const m = createMarkerForCluster(markerConfig, config);
      cluster.addLayer(m);
    }

    map.addLayer(cluster);
  }

  // Add shapes
  for (const shape of config.shapes || []) {
    addShape(map, shape);
  }

  // Add GeoJSON layer
  if (config.geoJson) {
    addGeoJson(map, config.geoJson, config);
  }

  // Add drawing tools
  if (config.drawing) {
    await loadDrawingTools();
    addDrawingTools(map, config.drawing, config);
  }

  // Add fullscreen control
  if (config.fullscreenControl) {
    addFullscreenControl(map, element);
  }

  // Set up event handlers
  setupEventHandlers(map, config);

  // Store instance
  const instance = {
    map,
    markers,
    element,
    config,
  };

  mapInstances.set(element, instance);

  // Fire load event
  if (config.onLoad) {
    const bounds = map.getBounds();
    config.onLoad({
      center: { lat: map.getCenter().lat, lng: map.getCenter().lng },
      zoom: map.getZoom(),
      bounds: {
        southWest: { lat: bounds.getSouthWest().lat, lng: bounds.getSouthWest().lng },
        northEast: { lat: bounds.getNorthEast().lat, lng: bounds.getNorthEast().lng },
      },
    })();
  }

  return instance;
};

/**
 * Create a marker
 */
const createMarker = (map, markerConfig, mapConfig) => {
  const options = {
    draggable: markerConfig.draggable,
    opacity: markerConfig.opacity,
  };

  // Custom icon
  if (markerConfig.icon) {
    if (markerConfig.icon.iconUrl) {
      options.icon = L.icon({
        iconUrl: markerConfig.icon.iconUrl,
        iconSize: [markerConfig.icon.iconSize.width, markerConfig.icon.iconSize.height],
        iconAnchor: [markerConfig.icon.iconAnchor.x, markerConfig.icon.iconAnchor.y],
        popupAnchor: [markerConfig.icon.popupAnchor.x, markerConfig.icon.popupAnchor.y],
        shadowUrl: markerConfig.icon.shadowUrl || undefined,
        shadowSize: markerConfig.icon.shadowSize
          ? [markerConfig.icon.shadowSize.width, markerConfig.icon.shadowSize.height]
          : undefined,
      });
    }
  }

  const marker = L.marker([markerConfig.position.lat, markerConfig.position.lng], options);

  // Add popup
  if (markerConfig.popup) {
    marker.bindPopup(markerConfig.popup);
  }

  // Add tooltip
  if (markerConfig.tooltip) {
    marker.bindTooltip(markerConfig.tooltip);
  }

  // Click handler
  if (markerConfig.onClick) {
    marker.on("click", (e) => {
      markerConfig.onClick({ lat: e.latlng.lat, lng: e.latlng.lng })();
    });
  }

  // Drag end handler
  if (markerConfig.onDragEnd) {
    marker.on("dragend", (e) => {
      const pos = marker.getLatLng();
      markerConfig.onDragEnd({ lat: pos.lat, lng: pos.lng })();
    });
  }

  marker.addTo(map);
  return marker;
};

/**
 * Create marker for clustering (without adding to map)
 */
const createMarkerForCluster = (markerConfig, mapConfig) => {
  const options = {
    draggable: markerConfig.draggable,
    opacity: markerConfig.opacity,
  };

  if (markerConfig.icon && markerConfig.icon.iconUrl) {
    options.icon = L.icon({
      iconUrl: markerConfig.icon.iconUrl,
      iconSize: [markerConfig.icon.iconSize.width, markerConfig.icon.iconSize.height],
      iconAnchor: [markerConfig.icon.iconAnchor.x, markerConfig.icon.iconAnchor.y],
      popupAnchor: [markerConfig.icon.popupAnchor.x, markerConfig.icon.popupAnchor.y],
    });
  }

  const marker = L.marker([markerConfig.position.lat, markerConfig.position.lng], options);

  if (markerConfig.popup) {
    marker.bindPopup(markerConfig.popup);
  }

  if (markerConfig.tooltip) {
    marker.bindTooltip(markerConfig.tooltip);
  }

  return marker;
};

/**
 * Load marker cluster plugin
 */
const loadMarkerCluster = async () => {
  if (typeof L.markerClusterGroup !== "undefined") return;

  // Load CSS
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css";
  document.head.appendChild(link);

  const link2 = document.createElement("link");
  link2.rel = "stylesheet";
  link2.href = "https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css";
  document.head.appendChild(link2);

  // Load JS
  await new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js";
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
};

/**
 * Add shape to map
 */
const addShape = (map, shape) => {
  const styleToOptions = (style) => ({
    color: style.strokeColor,
    weight: style.strokeWeight,
    opacity: style.strokeOpacity,
    fillColor: style.fillColor,
    fillOpacity: style.fillOpacity,
    dashArray: style.dashArray || undefined,
  });

  // shape is a variant type, check its tag
  if (shape.tag === "PolylineShape") {
    const coords = shape.value0.map((p) => [p.lat, p.lng]);
    L.polyline(coords, styleToOptions(shape.value1)).addTo(map);
  } else if (shape.tag === "PolygonShape") {
    const coords = shape.value0.map((p) => [p.lat, p.lng]);
    L.polygon(coords, styleToOptions(shape.value1)).addTo(map);
  } else if (shape.tag === "RectangleShape") {
    const bounds = [
      [shape.value0.southWest.lat, shape.value0.southWest.lng],
      [shape.value0.northEast.lat, shape.value0.northEast.lng],
    ];
    L.rectangle(bounds, styleToOptions(shape.value1)).addTo(map);
  } else if (shape.tag === "CircleShape") {
    L.circle([shape.value0.lat, shape.value0.lng], {
      radius: shape.value1,
      ...styleToOptions(shape.value2),
    }).addTo(map);
  }
};

/**
 * Add GeoJSON layer
 */
const addGeoJson = (map, geoJsonConfig, mapConfig) => {
  const options = {};

  if (geoJsonConfig.style) {
    options.style = (feature) => {
      const style = geoJsonConfig.style(feature);
      return {
        color: style.strokeColor,
        weight: style.strokeWeight,
        opacity: style.strokeOpacity,
        fillColor: style.fillColor,
        fillOpacity: style.fillOpacity,
        dashArray: style.dashArray || undefined,
      };
    };
  }

  if (geoJsonConfig.onEachFeature) {
    options.onEachFeature = (feature, layer) => {
      geoJsonConfig.onEachFeature(feature)(layer)();
    };
  }

  if (geoJsonConfig.pointToLayer) {
    options.pointToLayer = (feature, latlng) => {
      return geoJsonConfig.pointToLayer(feature)({ lat: latlng.lat, lng: latlng.lng });
    };
  }

  const layer = L.geoJSON(geoJsonConfig.data, options);

  if (geoJsonConfig.onClick) {
    layer.on("click", (e) => {
      geoJsonConfig.onClick(e.layer.feature)();
    });
  }

  layer.addTo(map);
  return layer;
};

/**
 * Load Leaflet.draw plugin
 */
const loadDrawingTools = async () => {
  if (typeof L.Control.Draw !== "undefined") return;

  // Load CSS
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://unpkg.com/leaflet-draw@1.0.4/dist/leaflet.draw.css";
  document.head.appendChild(link);

  // Load JS
  await new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://unpkg.com/leaflet-draw@1.0.4/dist/leaflet.draw.js";
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
};

/**
 * Add drawing tools to map
 */
const addDrawingTools = (map, drawingConfig, mapConfig) => {
  const drawnItems = new L.FeatureGroup();
  map.addLayer(drawnItems);

  const drawControl = new L.Control.Draw({
    edit: {
      featureGroup: drawnItems,
    },
    draw: {
      polygon: drawingConfig.enablePolygon,
      polyline: drawingConfig.enablePolyline,
      rectangle: drawingConfig.enableRectangle,
      circle: drawingConfig.enableCircle,
      marker: drawingConfig.enableMarker,
      circlemarker: false,
    },
  });

  map.addControl(drawControl);

  // Handle draw created
  map.on(L.Draw.Event.CREATED, (e) => {
    const layer = e.layer;
    drawnItems.addLayer(layer);

    if (drawingConfig.onDrawCreated) {
      let latlngs = [];
      if (layer.getLatLngs) {
        const coords = layer.getLatLngs();
        latlngs = Array.isArray(coords[0]) ? coords[0] : coords;
        latlngs = latlngs.map((ll) => ({ lat: ll.lat, lng: ll.lng }));
      } else if (layer.getLatLng) {
        const ll = layer.getLatLng();
        latlngs = [{ lat: ll.lat, lng: ll.lng }];
      }

      drawingConfig.onDrawCreated({
        layerType: e.layerType,
        layer: layer,
        latlngs: latlngs,
      })();
    }
  });

  // Handle draw edited
  map.on(L.Draw.Event.EDITED, (e) => {
    if (drawingConfig.onDrawEdited) {
      const layers = [];
      e.layers.eachLayer((layer) => {
        layers.push(layer);
      });
      drawingConfig.onDrawEdited({ layers })();
    }
  });

  // Handle draw deleted
  map.on(L.Draw.Event.DELETED, (e) => {
    if (drawingConfig.onDrawDeleted) {
      const layers = [];
      e.layers.eachLayer((layer) => {
        layers.push(layer);
      });
      drawingConfig.onDrawDeleted({ layers })();
    }
  });
};

/**
 * Add fullscreen control
 */
const addFullscreenControl = (map, container) => {
  const FullscreenControl = L.Control.extend({
    options: {
      position: "topleft",
    },

    onAdd: function () {
      const btn = L.DomUtil.create("div", "leaflet-bar leaflet-control");
      btn.innerHTML = `
        <a href="#" title="Toggle Fullscreen" role="button" aria-label="Toggle Fullscreen"
           class="flex items-center justify-center w-[30px] h-[30px] bg-white hover:bg-gray-100 cursor-pointer">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                  d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
          </svg>
        </a>
      `;

      L.DomEvent.on(btn, "click", (e) => {
        L.DomEvent.stop(e);
        toggleFullscreen(container);
      });

      return btn;
    },
  });

  map.addControl(new FullscreenControl());
};

/**
 * Toggle fullscreen mode
 */
const toggleFullscreen = (element) => {
  if (!document.fullscreenElement) {
    element.requestFullscreen().catch((err) => {
      console.warn("Fullscreen request failed:", err);
    });
  } else {
    document.exitFullscreen();
  }
};

/**
 * Set up event handlers
 */
const setupEventHandlers = (map, config) => {
  // Click
  if (config.onClick) {
    map.on("click", (e) => {
      config.onClick({
        latlng: { lat: e.latlng.lat, lng: e.latlng.lng },
        containerPoint: { x: e.containerPoint.x, y: e.containerPoint.y },
        originalEvent: e.originalEvent,
      })();
    });
  }

  // Double click
  if (config.onDoubleClick) {
    map.on("dblclick", (e) => {
      config.onDoubleClick({
        latlng: { lat: e.latlng.lat, lng: e.latlng.lng },
        containerPoint: { x: e.containerPoint.x, y: e.containerPoint.y },
        originalEvent: e.originalEvent,
      })();
    });
  }

  // Zoom end
  if (config.onZoomEnd) {
    map.on("zoomend", () => {
      config.onZoomEnd({
        zoom: map.getZoom(),
        center: { lat: map.getCenter().lat, lng: map.getCenter().lng },
      })();
    });
  }

  // Move end
  if (config.onMoveEnd) {
    map.on("moveend", () => {
      const bounds = map.getBounds();
      config.onMoveEnd({
        center: { lat: map.getCenter().lat, lng: map.getCenter().lng },
        bounds: {
          southWest: { lat: bounds.getSouthWest().lat, lng: bounds.getSouthWest().lng },
          northEast: { lat: bounds.getNorthEast().lat, lng: bounds.getNorthEast().lng },
        },
      })();
    });
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // map instance api
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Set map view
 */
export const setViewImplEffect = (instance) => (center) => (zoom) => () => {
  instance.map.setView([center.lat, center.lng], zoom);
};

/**
 * Set zoom level
 */
export const setZoomImplEffect = (instance) => (zoom) => () => {
  instance.map.setZoom(zoom);
};

/**
 * Pan to location
 */
export const panToImplEffect = (instance) => (center) => () => {
  instance.map.panTo([center.lat, center.lng]);
};

/**
 * Fly to location with animation
 */
export const flyToImplEffect = (instance) => (center) => (zoom) => () => {
  instance.map.flyTo([center.lat, center.lng], zoom);
};

/**
 * Fit bounds
 */
export const fitBoundsImplEffect = (instance) => (bounds) => () => {
  instance.map.fitBounds([
    [bounds.southWest.lat, bounds.southWest.lng],
    [bounds.northEast.lat, bounds.northEast.lng],
  ]);
};

/**
 * Invalidate size
 */
export const invalidateSizeImplEffect = (instance) => () => {
  instance.map.invalidateSize();
};

/**
 * Get center
 */
export const getCenterImplEffect = (instance) => () => {
  const center = instance.map.getCenter();
  return { lat: center.lat, lng: center.lng };
};

/**
 * Get zoom
 */
export const getZoomImplEffect = (instance) => () => {
  return instance.map.getZoom();
};

/**
 * Get bounds
 */
export const getBoundsImplEffect = (instance) => () => {
  const bounds = instance.map.getBounds();
  return {
    southWest: { lat: bounds.getSouthWest().lat, lng: bounds.getSouthWest().lng },
    northEast: { lat: bounds.getNorthEast().lat, lng: bounds.getNorthEast().lng },
  };
};

/**
 * Locate user
 */
export const locateImplEffect = (instance) => () => {
  instance.map.locate({ setView: true, maxZoom: 16 });
};

/**
 * Destroy map instance
 */
export const destroyMapImpl = (instance) => () => {
  if (instance && instance.map) {
    instance.map.remove();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // touch gestures
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize touch gesture support for mobile
 * Leaflet handles this natively, but we add some enhancements
 */
export const initTouchGestures = (mapInstance) => () => {
  const map = mapInstance.map;
  const element = mapInstance.element;

  // Prevent default touch behaviors that interfere with map
  element.addEventListener(
    "touchstart",
    (e) => {
      if (e.touches.length === 1) {
        // Single touch - allow pan
      } else if (e.touches.length === 2) {
        // Two finger - allow pinch zoom
      }
    },
    { passive: true }
  );

  // Handle orientation change
  window.addEventListener("orientationchange", () => {
    setTimeout(() => {
      map.invalidateSize();
    }, 200);
  });

  // Handle resize
  const resizeObserver = new ResizeObserver(() => {
    map.invalidateSize();
  });

  resizeObserver.observe(element);

  return () => {
    resizeObserver.disconnect();
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // auto initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Auto-initialize maps on elements with data-map attribute
 */
export const autoInitMaps = () => {
  const elements = document.querySelectorAll("[data-map]:not([data-map-initialized])");

  elements.forEach(async (element) => {
    element.setAttribute("data-map-initialized", "true");

    const config = {
      center: {
        lat: parseFloat(element.dataset.centerLat) || 0,
        lng: parseFloat(element.dataset.centerLng) || 0,
      },
      zoom: parseInt(element.dataset.zoom) || 2,
      minZoom: parseInt(element.dataset.minZoom) || 1,
      maxZoom: parseInt(element.dataset.maxZoom) || 18,
      tileLayer: {
        url: element.dataset.tileUrl || "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution:
          element.dataset.tileAttribution ||
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxZoom: 19,
      },
      zoomControl: element.dataset.zoomControl !== "false",
      zoomControlPosition: element.dataset.zoomPosition || "topright",
      scaleControl: element.dataset.scaleControl !== "false",
      attributionControl: element.dataset.attributionControl !== "false",
      fullscreenControl: element.dataset.fullscreenControl === "true",
      markers: [],
      shapes: [],
    };

    await initMapImpl(element, config)();
  });
};

// Auto-init on DOM ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", autoInitMaps);
  } else {
    autoInitMaps();
  }

  // Watch for dynamically added maps
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === 1) {
          if (node.hasAttribute && node.hasAttribute("data-map")) {
            autoInitMaps();
          } else if (node.querySelectorAll) {
            const maps = node.querySelectorAll("[data-map]");
            if (maps.length > 0) {
              autoInitMaps();
            }
          }
        }
      }
    }
  });

  observer.observe(document.body || document.documentElement, {
    childList: true,
    subtree: true,
  });
}
