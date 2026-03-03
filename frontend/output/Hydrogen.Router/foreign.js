// FFI for Straylight.Router
// Browser history and navigation integration

export const getPathname = () => window.location.pathname;

export const getHostname = () => window.location.hostname;

export const getOrigin = () => window.location.origin;

export const pushState = (path) => () => {
  window.history.pushState({}, "", path);
  // Dispatch a custom event so the app knows the route changed
  window.dispatchEvent(new CustomEvent("straylight:routechange", { detail: path }));
};

export const replaceState = (path) => () => {
  window.history.replaceState({}, "", path);
  // No event dispatch for replace - it's typically used for redirects
};

export const onPopState = (callback) => () => {
  // Handle browser back/forward
  window.addEventListener("popstate", () => {
    callback(window.location.pathname)();
  });
  
  // Handle programmatic navigation via pushState
  window.addEventListener("straylight:routechange", (e) => {
    callback(e.detail)();
  });
};

// Intercept all internal link clicks for SPA navigation
export const interceptLinks = (callback) => () => {
  document.addEventListener("click", (e) => {
    // Find the closest anchor element
    const anchor = e.target.closest("a");
    if (!anchor) return;
    
    const href = anchor.getAttribute("href");
    if (!href) return;
    
    // Skip if target="_blank" or has download attribute
    if (anchor.target === "_blank" || anchor.hasAttribute("download")) return;
    
    // Skip external links
    if (href.startsWith("http://") || href.startsWith("https://") || href.startsWith("//")) {
      // Check if it's actually same-origin
      try {
        const url = new URL(href, window.location.origin);
        if (url.origin !== window.location.origin) return;
        // Same origin but full URL - intercept it
        e.preventDefault();
        window.history.pushState({}, "", url.pathname + url.search + url.hash);
        callback(url.pathname)();
      } catch {
        return; // Invalid URL, let browser handle it
      }
      return;
    }
    
    // Only intercept internal links (starting with /)
    if (href.startsWith("/") && !href.startsWith("//")) {
      e.preventDefault();
      window.history.pushState({}, "", href);
      callback(href)();
    }
  });
};
