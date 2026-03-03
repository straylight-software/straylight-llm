// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                     // hydrogen // analytics
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Timing APIs
// Date.now() is the only source of real-time in the browser
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Current timestamp in milliseconds
// | This is the browser's wall-clock time - cannot be pure
export const now = () => Date.now();

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Session/Random ID Generation
// Math.random() provides entropy from the browser's RNG
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Generate unique session identifier
// | Uses Math.random() for entropy + Date.now() for uniqueness
export const generateSessionId = () => {
  return "sess_" + Math.random().toString(36).substring(2, 15) + Date.now().toString(36);
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Timer APIs
// setInterval/clearInterval manage browser event loop timing
// ═══════════════════════════════════════════════════════════════════════════════

let flushIntervalId = null;

// | BROWSER BOUNDARY: Set up periodic flush using setInterval
// | Manages browser timer state
export const setupFlushInterval = (tracker) => (interval) => () => {
  if (flushIntervalId) {
    clearInterval(flushIntervalId);
  }
  flushIntervalId = setInterval(() => {
    // Call flush - this is a simplified version
    const queue = tracker.queue.value;
    if (queue.length > 0) {
      tracker.queue.value = [];
      for (const provider of tracker.providers) {
        for (const event of queue) {
          provider.track(event.eventType)(event.data)();
        }
        provider.flush();
      }
    }
  }, interval);
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Privacy/Navigator APIs
// navigator.doNotTrack is a browser-only privacy signal
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Check browser Do Not Track setting
// | Accesses navigator global
export const getDoNotTrack = () => {
  if (typeof navigator === "undefined") return false;
  return navigator.doNotTrack === "1" || navigator.doNotTrack === "yes" || window.doNotTrack === "1";
};

// | BROWSER BOUNDARY: Persist opt-out preference to localStorage
export const persistOptOut = (optedOut) => () => {
  try {
    if (typeof localStorage === "undefined") return;
    if (optedOut) {
      localStorage.setItem("hydrogen:analytics:opted-out", "true");
    } else {
      localStorage.removeItem("hydrogen:analytics:opted-out");
    }
  } catch (e) {
    // localStorage may not be available
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Console APIs
// console.log is browser I/O
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Log analytics event to console
export const logAnalytics = (eventType) => (data) => () => {
  console.log(`[Analytics] ${eventType}:`, Object.fromEntries(Object.entries(data)));
};

// | BROWSER BOUNDARY: Log identify event to console
export const logIdentify = (userId) => () => {
  console.log(`[Analytics] Identify: ${userId}`);
};

// | BROWSER BOUNDARY: Log user properties to console
export const logUserProps = (props) => () => {
  console.log(`[Analytics] User Properties:`, Object.fromEntries(Object.entries(props)));
};

// | BROWSER BOUNDARY: Log reset event to console
export const logReset = () => {
  console.log(`[Analytics] Reset user identity`);
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Google Analytics 4
// Loads external script, accesses DOM, uses global gtag
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Initialize Google Analytics 4 provider
// | Injects script tag, accesses DOM, creates global gtag
export const initGoogleAnalytics = (measurementId) => () => {
  // Load GA4 script if not already loaded
  if (typeof gtag === "undefined") {
    const script = document.createElement("script");
    script.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
    script.async = true;
    document.head.appendChild(script);

    window.dataLayer = window.dataLayer || [];
    window.gtag = function () {
      dataLayer.push(arguments);
    };
    gtag("js", new Date());
    gtag("config", measurementId);
  }

  return {
    name: "google-analytics",
    track: (eventType) => (data) => () => {
      if (typeof gtag !== "undefined") {
        const params = {};
        for (const [key, value] of Object.entries(data)) {
          params[key] = value;
        }
        gtag("event", eventType, params);
      }
    },
    identify: (userId) => () => {
      if (typeof gtag !== "undefined") {
        gtag("config", measurementId, { user_id: userId });
      }
    },
    setUserProperties: (props) => () => {
      if (typeof gtag !== "undefined") {
        gtag("set", "user_properties", props);
      }
    },
    reset: () => {
      // GA4 doesn't have a built-in reset
    },
    flush: () => {
      // GA4 sends automatically
    },
  };
};

// ══════════════════════════════════════════════════════════════════��════════════
// BROWSER BOUNDARY: Plausible Analytics
// Loads external script, accesses DOM
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Initialize Plausible Analytics provider
// | Injects script tag, accesses DOM
export const initPlausible = (domain) => () => {
  // Load Plausible script if not already loaded
  if (!document.querySelector('script[data-domain="' + domain + '"]')) {
    const script = document.createElement("script");
    script.src = "https://plausible.io/js/script.js";
    script.defer = true;
    script.dataset.domain = domain;
    document.head.appendChild(script);
  }

  return {
    name: "plausible",
    track: (eventType) => (data) => () => {
      if (typeof plausible !== "undefined") {
        plausible(eventType, { props: data });
      }
    },
    identify: (_userId) => () => {
      // Plausible is privacy-focused, no user identification
    },
    setUserProperties: (_props) => () => {
      // Not supported
    },
    reset: () => {},
    flush: () => {},
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Mixpanel
// Loads external script, accesses DOM, uses global mixpanel
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Initialize Mixpanel provider
// | Injects script tag, accesses DOM, creates global mixpanel
export const initMixpanel = (token) => () => {
  // Load Mixpanel script if not already loaded
  if (typeof window.mixpanel === "undefined") {
    // Create a stub for queuing calls before library loads
    window.mixpanel = {
      _queue: [],
      track: function (event, props) {
        this._queue.push(["track", event, props]);
      },
      identify: function (id) {
        this._queue.push(["identify", id]);
      },
      reset: function () {
        this._queue.push(["reset"]);
      },
      people: {
        set: function (props) {
          window.mixpanel._queue.push(["people.set", props]);
        },
      },
    };

    // Load the actual Mixpanel script
    const script = document.createElement("script");
    script.type = "text/javascript";
    script.async = true;
    script.src = "https://cdn.mxpnl.com/libs/mixpanel-2-latest.min.js";
    script.onload = function () {
      // Initialize and replay queued calls
      if (window.mixpanel && window.mixpanel.init) {
        const queue = window.mixpanel._queue || [];
        window.mixpanel.init(token, { batch_requests: true });
        for (const call of queue) {
          const method = call[0];
          const args = call.slice(1);
          if (method === "people.set") {
            window.mixpanel.people.set(...args);
          } else if (typeof window.mixpanel[method] === "function") {
            window.mixpanel[method](...args);
          }
        }
      }
    };
    const firstScript = document.getElementsByTagName("script")[0];
    if (firstScript && firstScript.parentNode) {
      firstScript.parentNode.insertBefore(script, firstScript);
    } else {
      document.head.appendChild(script);
    }
  }

  return {
    name: "mixpanel",
    track: (eventType) => (data) => () => {
      if (typeof mixpanel !== "undefined") {
        mixpanel.track(eventType, data);
      }
    },
    identify: (userId) => () => {
      if (typeof mixpanel !== "undefined") {
        mixpanel.identify(userId);
      }
    },
    setUserProperties: (props) => () => {
      if (typeof mixpanel !== "undefined") {
        mixpanel.people.set(props);
      }
    },
    reset: () => {
      if (typeof mixpanel !== "undefined") {
        mixpanel.reset();
      }
    },
    flush: () => {
      // Mixpanel batches automatically
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
// BROWSER BOUNDARY: Performance Observer APIs
// PerformanceObserver is browser-only for Core Web Vitals
// ═══════════════════════════════════════════════════════════════════════════════

// | BROWSER BOUNDARY: Observe Core Web Vitals metrics
// | Uses PerformanceObserver API - browser-only
export const observeWebVitals = (callback) => () => {
  const observers = [];

  // Use web-vitals library pattern
  const reportMetric = (name, value) => {
    const metric = (() => {
      switch (name) {
        case "LCP":
          return { tag: "LCP", value0: value };
        case "FID":
          return { tag: "FID", value0: value };
        case "CLS":
          return { tag: "CLS", value0: value };
        case "FCP":
          return { tag: "FCP", value0: value };
        case "TTFB":
          return { tag: "TTFB", value0: value };
        case "INP":
          return { tag: "INP", value0: value };
        default:
          return null;
      }
    })();
    if (metric) callback(metric)();
  };

  // LCP - Largest Contentful Paint
  try {
    const lcpObserver = new PerformanceObserver((entryList) => {
      const entries = entryList.getEntries();
      const lastEntry = entries[entries.length - 1];
      reportMetric("LCP", lastEntry.startTime);
    });
    lcpObserver.observe({ type: "largest-contentful-paint", buffered: true });
    observers.push(lcpObserver);
  } catch (e) {}

  // FID - First Input Delay
  try {
    const fidObserver = new PerformanceObserver((entryList) => {
      const entries = entryList.getEntries();
      for (const entry of entries) {
        reportMetric("FID", entry.processingStart - entry.startTime);
      }
    });
    fidObserver.observe({ type: "first-input", buffered: true });
    observers.push(fidObserver);
  } catch (e) {}

  // CLS - Cumulative Layout Shift
  try {
    let clsValue = 0;
    const clsObserver = new PerformanceObserver((entryList) => {
      for (const entry of entryList.getEntries()) {
        if (!entry.hadRecentInput) {
          clsValue += entry.value;
        }
      }
      reportMetric("CLS", clsValue);
    });
    clsObserver.observe({ type: "layout-shift", buffered: true });
    observers.push(clsObserver);
  } catch (e) {}

  // FCP - First Contentful Paint
  try {
    const fcpObserver = new PerformanceObserver((entryList) => {
      for (const entry of entryList.getEntries()) {
        if (entry.name === "first-contentful-paint") {
          reportMetric("FCP", entry.startTime);
        }
      }
    });
    fcpObserver.observe({ type: "paint", buffered: true });
    observers.push(fcpObserver);
  } catch (e) {}

  // TTFB - Time to First Byte
  try {
    const navEntries = performance.getEntriesByType("navigation");
    if (navEntries.length > 0) {
      reportMetric("TTFB", navEntries[0].responseStart);
    }
  } catch (e) {}

  // Return cleanup function
  return () => {
    for (const observer of observers) {
      observer.disconnect();
    }
  };
};
