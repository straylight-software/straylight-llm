// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                   // hydrogen // addressinput
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Address autocomplete with geocoding support
// Works with Nominatim (OpenStreetMap) or pluggable providers

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // helper functions
// ═══════════════════════════════════════════════════════════════════════════════

export const arrayLength = (arr) => arr.length;

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // nominatim provider
// ═══════════════════════════════════════════════════════════════════════════════

const NOMINATIM_BASE = "https://nominatim.openstreetmap.org";

/**
 * Parse Nominatim response into Place format
 */
const parseNominatimResult = (result) => {
  const address = result.address || {};

  // Build structured address
  const components = [];

  if (address.house_number) {
    components.push({
      types: [{ tag: "StreetNumber" }],
      longName: address.house_number,
      shortName: address.house_number,
    });
  }

  if (address.road || address.street) {
    components.push({
      types: [{ tag: "StreetName" }],
      longName: address.road || address.street,
      shortName: address.road || address.street,
    });
  }

  if (address.neighbourhood || address.suburb) {
    components.push({
      types: [{ tag: "Neighborhood" }],
      longName: address.neighbourhood || address.suburb,
      shortName: address.neighbourhood || address.suburb,
    });
  }

  if (address.city || address.town || address.village) {
    components.push({
      types: [{ tag: "City" }],
      longName: address.city || address.town || address.village,
      shortName: address.city || address.town || address.village,
    });
  }

  if (address.county) {
    components.push({
      types: [{ tag: "County" }],
      longName: address.county,
      shortName: address.county,
    });
  }

  if (address.state) {
    components.push({
      types: [{ tag: "State" }],
      longName: address.state,
      shortName: address.state,
    });
  }

  if (address.country) {
    components.push({
      types: [{ tag: "Country" }],
      longName: address.country,
      shortName: address.country_code ? address.country_code.toUpperCase() : address.country,
    });
  }

  if (address.postcode) {
    components.push({
      types: [{ tag: "PostalCode" }],
      longName: address.postcode,
      shortName: address.postcode,
    });
  }

  // Build street string
  let street = null;
  if (address.house_number && (address.road || address.street)) {
    street = `${address.house_number} ${address.road || address.street}`;
  } else if (address.road || address.street) {
    street = address.road || address.street;
  }

  return {
    placeId: String(result.place_id),
    displayName: result.display_name,
    address: {
      formatted: result.display_name,
      components: components,
      street: street,
      city: address.city || address.town || address.village || null,
      state: address.state || null,
      country: address.country || null,
      postalCode: address.postcode || null,
    },
    coordinates: {
      lat: parseFloat(result.lat),
      lng: parseFloat(result.lon),
    },
    boundingBox: result.boundingbox
      ? {
          south: parseFloat(result.boundingbox[0]),
          north: parseFloat(result.boundingbox[1]),
          west: parseFloat(result.boundingbox[2]),
          east: parseFloat(result.boundingbox[3]),
        }
      : null,
    types: result.type ? [result.type] : [],
  };
};

/**
 * Search using Nominatim
 */
export const nominatimSearchImpl = (query) => (onError, onSuccess) => {
  const url = `${NOMINATIM_BASE}/search?format=json&addressdetails=1&limit=5&q=${encodeURIComponent(query)}`;

  fetch(url, {
    headers: {
      "User-Agent": "Hydrogen-Framework/1.0",
    },
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return response.json();
    })
    .then((results) => {
      const places = results.map(parseNominatimResult);
      onSuccess(places);
    })
    .catch((error) => {
      onError(error);
    });

  return () => {}; // Canceler
};

/**
 * Reverse geocode using Nominatim
 */
export const nominatimReverseImpl = (coords) => (onError, onSuccess) => {
  const url = `${NOMINATIM_BASE}/reverse?format=json&addressdetails=1&lat=${coords.lat}&lon=${coords.lng}`;

  fetch(url, {
    headers: {
      "User-Agent": "Hydrogen-Framework/1.0",
    },
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return response.json();
    })
    .then((result) => {
      if (result.error) {
        onSuccess(null);
        return;
      }
      const place = parseNominatimResult(result);
      onSuccess(place.address);
    })
    .catch((error) => {
      onError(error);
    });

  return () => {};
};

/**
 * Get place details from Nominatim
 */
export const nominatimDetailsImpl = (placeId) => (onError, onSuccess) => {
  const url = `${NOMINATIM_BASE}/lookup?format=json&addressdetails=1&osm_ids=N${placeId}`;

  fetch(url, {
    headers: {
      "User-Agent": "Hydrogen-Framework/1.0",
    },
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return response.json();
    })
    .then((results) => {
      if (results.length === 0) {
        onSuccess(null);
        return;
      }
      onSuccess(parseNominatimResult(results[0]));
    })
    .catch((error) => {
      onError(error);
    });

  return () => {};
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // geocoding api
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Geocode an address
 */
export const geocodeImplAff = (query) => (onError, onSuccess) => {
  nominatimSearchImpl(query)(
    (error) => {
      onSuccess({ tag: "Left", value0: error.message || "Geocoding failed" });
    },
    (places) => {
      onSuccess({ tag: "Right", value0: places });
    }
  );

  return () => {};
};

/**
 * Reverse geocode coordinates
 */
export const reverseGeocodeImplAff = (coords) => (onError, onSuccess) => {
  nominatimReverseImpl(coords)(
    (error) => {
      onSuccess({ tag: "Left", value0: error.message || "Reverse geocoding failed" });
    },
    (address) => {
      if (address) {
        onSuccess({ tag: "Right", value0: address });
      } else {
        onSuccess({ tag: "Left", value0: "No address found" });
      }
    }
  );

  return () => {};
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // recent searches
// ═══════════════════════════════════════════════════════════════════════════════

const RECENT_SEARCHES_KEY = "hydrogen_recent_addresses";
const MAX_RECENT_SEARCHES = 10;

/**
 * Get recent searches from localStorage
 */
export const getRecentSearchesImpl = () => {
  try {
    const stored = localStorage.getItem(RECENT_SEARCHES_KEY);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.warn("Failed to load recent searches:", e);
  }
  return [];
};

/**
 * Add a place to recent searches
 */
export const addRecentSearchImpl = (place) => () => {
  try {
    const recent = getRecentSearchesImpl();

    // Remove duplicate
    const filtered = recent.filter((p) => p.placeId !== place.placeId);

    // Add to front
    const updated = [place, ...filtered].slice(0, MAX_RECENT_SEARCHES);

    localStorage.setItem(RECENT_SEARCHES_KEY, JSON.stringify(updated));
  } catch (e) {
    console.warn("Failed to save recent search:", e);
  }
};

/**
 * Clear recent searches
 */
export const clearRecentSearchesImpl = () => {
  try {
    localStorage.removeItem(RECENT_SEARCHES_KEY);
  } catch (e) {
    console.warn("Failed to clear recent searches:", e);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // component initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize address input component
 */
const initAddressInput = (element, config) => {
  const input = element.querySelector("[data-address-input-field]");
  const suggestionsContainer = element.querySelector("[data-suggestions]");
  const suggestionList = element.querySelector("[data-suggestion-list]");
  const loadingIndicator = element.querySelector("[data-loading]");
  const emptyIndicator = element.querySelector("[data-empty]");
  const clearBtn = element.querySelector("[data-clear-btn]");
  const locationBtn = element.querySelector("[data-current-location-btn]");
  const mapPreview = element.querySelector("[data-map-preview]");

  let debounceTimer = null;
  let currentValue = "";
  let selectedIndex = -1;
  let suggestions = [];

  const debounceMs = parseInt(element.dataset.debounce) || 300;
  const minChars = parseInt(element.dataset.minChars) || 3;
  const maxSuggestions = parseInt(element.dataset.maxSuggestions) || 5;

  // Show/hide suggestions dropdown
  const showSuggestions = () => {
    if (suggestionsContainer) {
      suggestionsContainer.classList.remove("hidden");
      input.setAttribute("aria-expanded", "true");
    }
  };

  const hideSuggestions = () => {
    if (suggestionsContainer) {
      suggestionsContainer.classList.add("hidden");
      input.setAttribute("aria-expanded", "false");
    }
    selectedIndex = -1;
  };

  // Show/hide loading
  const showLoading = () => {
    if (loadingIndicator) loadingIndicator.classList.remove("hidden");
    if (emptyIndicator) emptyIndicator.classList.add("hidden");
    if (suggestionList) suggestionList.innerHTML = "";
  };

  const hideLoading = () => {
    if (loadingIndicator) loadingIndicator.classList.add("hidden");
  };

  // Render suggestions
  const renderSuggestions = (places) => {
    suggestions = places;
    hideLoading();

    if (!suggestionList) return;

    if (places.length === 0) {
      suggestionList.innerHTML = "";
      if (emptyIndicator) emptyIndicator.classList.remove("hidden");
      return;
    }

    if (emptyIndicator) emptyIndicator.classList.add("hidden");

    suggestionList.innerHTML = places
      .map(
        (place, index) => `
      <li
        class="px-3 py-2 cursor-pointer hover:bg-accent focus:bg-accent outline-none transition-colors"
        role="option"
        data-index="${index}"
        tabindex="-1"
      >
        <div class="flex items-start gap-2">
          <svg class="w-4 h-4 mt-0.5 flex-shrink-0 text-muted-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
          </svg>
          <div class="flex-1 min-w-0">
            <div class="font-medium text-sm truncate">${escapeHtml(getMainText(place))}</div>
            <div class="text-xs text-muted-foreground truncate">${escapeHtml(getSecondaryText(place))}</div>
          </div>
        </div>
      </li>
    `
      )
      .join("");

    // Add click handlers
    suggestionList.querySelectorAll("li").forEach((li) => {
      li.addEventListener("click", () => {
        const index = parseInt(li.dataset.index);
        selectSuggestion(index);
      });
    });
  };

  // Get main text (primary display)
  const getMainText = (place) => {
    if (place.address.street) {
      return place.address.street;
    }
    const parts = place.displayName.split(",");
    return parts[0] || place.displayName;
  };

  // Get secondary text (secondary display)
  const getSecondaryText = (place) => {
    const parts = [];
    if (place.address.city) parts.push(place.address.city);
    if (place.address.state) parts.push(place.address.state);
    if (place.address.country) parts.push(place.address.country);
    return parts.join(", ") || place.displayName;
  };

  // Select a suggestion
  const selectSuggestion = (index) => {
    if (index < 0 || index >= suggestions.length) return;

    const place = suggestions[index];
    input.value = place.displayName;
    currentValue = place.displayName;
    hideSuggestions();

    // Save to recent
    addRecentSearchImpl(place)();

    // Update map preview
    if (mapPreview) {
      updateMapPreview(place.coordinates);
    }

    // Dispatch custom event
    element.dispatchEvent(
      new CustomEvent("address-select", {
        detail: place,
        bubbles: true,
      })
    );
  };

  // Update clear button visibility
  const updateClearButton = () => {
    if (clearBtn) {
      if (input.value.length > 0) {
        clearBtn.classList.remove("hidden");
      } else {
        clearBtn.classList.add("hidden");
      }
    }
  };

  // Search for addresses
  const search = async (query) => {
    if (query.length < minChars) {
      hideSuggestions();
      return;
    }

    showSuggestions();
    showLoading();

    try {
      const results = await new Promise((resolve, reject) => {
        nominatimSearchImpl(query)(reject, resolve);
      });

      renderSuggestions(results.slice(0, maxSuggestions));
    } catch (error) {
      console.warn("Address search failed:", error);
      hideLoading();
      if (emptyIndicator) {
        emptyIndicator.textContent = "Search failed. Please try again.";
        emptyIndicator.classList.remove("hidden");
      }
    }
  };

  // Update map preview
  const updateMapPreview = (coords) => {
    if (!mapPreview) return;

    mapPreview.classList.remove("hidden");

    // Use static map image
    const zoom = 15;
    const width = mapPreview.offsetWidth || 300;
    const height = mapPreview.offsetHeight || 128;

    // Use OpenStreetMap static tile
    mapPreview.innerHTML = `
      <div class="relative w-full h-full">
        <img 
          src="https://staticmap.openstreetmap.de/staticmap.php?center=${coords.lat},${coords.lng}&zoom=${zoom}&size=${width}x${height}&markers=${coords.lat},${coords.lng},red-pushpin"
          alt="Map preview"
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
          <svg class="w-8 h-8 text-red-500 drop-shadow-lg" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>
          </svg>
        </div>
      </div>
    `;
  };

  // Input event handlers
  input.addEventListener("input", (e) => {
    const value = e.target.value;
    currentValue = value;
    updateClearButton();

    // Debounce search
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    debounceTimer = setTimeout(() => {
      search(value);
    }, debounceMs);
  });

  input.addEventListener("focus", () => {
    if (currentValue.length >= minChars) {
      showSuggestions();
    }
  });

  input.addEventListener("blur", (e) => {
    // Delay hide to allow click on suggestions
    setTimeout(() => {
      hideSuggestions();
    }, 200);
  });

  // Keyboard navigation
  input.addEventListener("keydown", (e) => {
    if (!suggestions.length) return;

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        selectedIndex = Math.min(selectedIndex + 1, suggestions.length - 1);
        updateSelectedSuggestion();
        break;

      case "ArrowUp":
        e.preventDefault();
        selectedIndex = Math.max(selectedIndex - 1, 0);
        updateSelectedSuggestion();
        break;

      case "Enter":
        e.preventDefault();
        if (selectedIndex >= 0) {
          selectSuggestion(selectedIndex);
        }
        break;

      case "Escape":
        hideSuggestions();
        break;
    }
  });

  const updateSelectedSuggestion = () => {
    if (!suggestionList) return;

    const items = suggestionList.querySelectorAll("li");
    items.forEach((item, index) => {
      if (index === selectedIndex) {
        item.classList.add("bg-accent");
        item.scrollIntoView({ block: "nearest" });
      } else {
        item.classList.remove("bg-accent");
      }
    });
  };

  // Clear button handler
  if (clearBtn) {
    clearBtn.addEventListener("click", () => {
      input.value = "";
      currentValue = "";
      updateClearButton();
      hideSuggestions();

      if (mapPreview) {
        mapPreview.classList.add("hidden");
      }

      element.dispatchEvent(new CustomEvent("address-clear", { bubbles: true }));
    });
  }

  // Current location button handler
  if (locationBtn) {
    locationBtn.addEventListener("click", async () => {
      if (!navigator.geolocation) {
        console.warn("Geolocation not supported");
        return;
      }

      locationBtn.disabled = true;

      try {
        const position = await new Promise((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(resolve, reject, {
            enableHighAccuracy: true,
            timeout: 10000,
          });
        });

        const coords = {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        };

        // Reverse geocode
        const address = await new Promise((resolve, reject) => {
          nominatimReverseImpl(coords)(reject, resolve);
        });

        if (address) {
          input.value = address.formatted;
          currentValue = address.formatted;
          updateClearButton();

          if (mapPreview) {
            updateMapPreview(coords);
          }

          element.dispatchEvent(
            new CustomEvent("address-current-location", {
              detail: { coords, address },
              bubbles: true,
            })
          );
        }
      } catch (error) {
        console.warn("Failed to get current location:", error);
      } finally {
        locationBtn.disabled = false;
      }
    });
  }

  // Initialize
  updateClearButton();

  return {
    destroy: () => {
      if (debounceTimer) {
        clearTimeout(debounceTimer);
      }
    },
  };
};

// Escape HTML
const escapeHtml = (str) => {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // auto initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Auto-initialize address inputs
 */
const autoInitAddressInputs = () => {
  const elements = document.querySelectorAll("[data-address-input]:not([data-initialized])");

  elements.forEach((element) => {
    element.setAttribute("data-initialized", "true");
    initAddressInput(element, {});
  });
};

// Auto-init on DOM ready
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", autoInitAddressInputs);
  } else {
    autoInitAddressInputs();
  }

  // Watch for dynamically added elements
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType === 1) {
          if (node.hasAttribute && node.hasAttribute("data-address-input")) {
            autoInitAddressInputs();
          } else if (node.querySelectorAll) {
            const inputs = node.querySelectorAll("[data-address-input]");
            if (inputs.length > 0) {
              autoInitAddressInputs();
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
