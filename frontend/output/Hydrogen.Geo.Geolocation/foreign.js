// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                    // hydrogen // geolocation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Geolocation services with position tracking, distance calculations,
// and geofencing support

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // support check
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Check if geolocation is supported
 */
export const isSupportedImpl = () => {
  return "geolocation" in navigator;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // error handling
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Convert GeolocationPositionError to PureScript error type
 */
const convertError = (error) => {
  switch (error.code) {
    case 1: // PERMISSION_DENIED
      return { tag: "PermissionDenied" };
    case 2: // POSITION_UNAVAILABLE
      return { tag: "PositionUnavailable" };
    case 3: // TIMEOUT
      return { tag: "Timeout" };
    default:
      return { tag: "UnknownError", value0: error.message || "Unknown error" };
  }
};

/**
 * Convert GeolocationPosition to PureScript Position type
 */
const convertPosition = (position) => {
  return {
    coords: {
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
      altitude: position.coords.altitude,
      accuracy: position.coords.accuracy,
      altitudeAccuracy: position.coords.altitudeAccuracy,
      heading: position.coords.heading,
      speed: position.coords.speed,
    },
    timestamp: position.timestamp,
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // position getting
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get current position (returns EffectFnAff)
 */
export const getCurrentPositionImpl = (options) => (onError, onSuccess) => {
  if (!navigator.geolocation) {
    onError({ tag: "PositionUnavailable" });
    return () => {};
  }

  navigator.geolocation.getCurrentPosition(
    (position) => {
      onSuccess({ tag: "Right", value0: convertPosition(position) });
    },
    (error) => {
      onSuccess({ tag: "Left", value0: convertError(error) });
    },
    {
      enableHighAccuracy: options.enableHighAccuracy,
      timeout: options.timeout,
      maximumAge: options.maximumAge,
    }
  );

  return () => {}; // Canceler (not really cancellable)
};

/**
 * Watch position with continuous updates
 */
export const watchPositionImpl = (options) => (callback) => () => {
  if (!navigator.geolocation) {
    callback({ tag: "Left", value0: { tag: "PositionUnavailable" } })();
    return { value0: -1 }; // Invalid watch ID
  }

  const watchId = navigator.geolocation.watchPosition(
    (position) => {
      callback({ tag: "Right", value0: convertPosition(position) })();
    },
    (error) => {
      callback({ tag: "Left", value0: convertError(error) })();
    },
    {
      enableHighAccuracy: options.enableHighAccuracy,
      timeout: options.timeout,
      maximumAge: options.maximumAge,
    }
  );

  return { value0: watchId };
};

/**
 * Clear position watch
 */
export const clearWatchImpl = (watchId) => () => {
  if (navigator.geolocation && watchId.value0 >= 0) {
    navigator.geolocation.clearWatch(watchId.value0);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // geofencing
// ═══════════════════════════════════════════════════════════════════════════════

// Track geofence state
const geofenceStates = new Map();

/**
 * Watch geofence for enter/exit events
 */
export const watchGeofenceImpl = (fence) => (callback) => () => {
  const fenceId = fence.id;
  let wasInside = null;
  let watchId = null;

  // Calculate distance using Haversine
  const haversineDistance = (lat1, lon1, lat2, lon2) => {
    const R = 6371000; // Earth's radius in meters
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  };

  const checkGeofence = (position) => {
    const distance = haversineDistance(
      position.coords.latitude,
      position.coords.longitude,
      fence.center.latitude,
      fence.center.longitude
    );

    const isInside = distance <= fence.radius;

    if (wasInside === null) {
      // First check - just set state
      wasInside = isInside;
      geofenceStates.set(fenceId, { isInside, entryTime: isInside ? Date.now() : null });
    } else if (wasInside !== isInside) {
      // State changed
      wasInside = isInside;

      if (isInside) {
        geofenceStates.set(fenceId, { isInside: true, entryTime: Date.now() });
        callback({ tag: "Enter" })();
      } else {
        geofenceStates.set(fenceId, { isInside: false, entryTime: null });
        callback({ tag: "Exit" })();
      }
    } else if (isInside) {
      // Still inside - check for dwell (more than 30 seconds)
      const state = geofenceStates.get(fenceId);
      if (state && state.entryTime && Date.now() - state.entryTime > 30000) {
        if (!state.dwellNotified) {
          state.dwellNotified = true;
          geofenceStates.set(fenceId, state);
          callback({ tag: "Dwell" })();
        }
      }
    }
  };

  // Start watching position
  if (navigator.geolocation) {
    watchId = navigator.geolocation.watchPosition(
      checkGeofence,
      (error) => {
        console.warn("Geofence position error:", error);
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 5000,
      }
    );
  }

  // Return cleanup function
  return () => {
    if (watchId !== null && navigator.geolocation) {
      navigator.geolocation.clearWatch(watchId);
    }
    geofenceStates.delete(fenceId);
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // math helpers
// ═══════════════════════════════════════════════════════════════════════════════

export const floorImpl = (n) => Math.floor(n);

export const ceilImpl = (n) => Math.ceil(n);

export const roundImpl = (n) => Math.round(n);

export const powImpl = (base) => (exp) => Math.pow(base, exp);

export const toNumberImpl = (n) => n;
