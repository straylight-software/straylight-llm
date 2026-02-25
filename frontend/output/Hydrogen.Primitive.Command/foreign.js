// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // hydrogen // command
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Command Palette JavaScript FFI
//
// Provides:
// - Global keyboard shortcut registration (⌘K / Ctrl+K)
// - Fuzzy search scoring algorithm

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // keyboard handler
// ═══════════════════════════════════════════════════════════════════════════════

// Store registered handlers for cleanup
let globalShortcutHandler = null;

/**
 * Register global keyboard shortcut (⌘K / Ctrl+K)
 *
 * @param {Function} callback - Effect to run when shortcut is pressed
 * @returns {Function} Cleanup function to unregister the shortcut
 */
export const registerGlobalShortcut = (callback) => () => {
  // Remove any existing handler
  if (globalShortcutHandler) {
    document.removeEventListener("keydown", globalShortcutHandler);
  }

  globalShortcutHandler = (event) => {
    // Check for Cmd+K (Mac) or Ctrl+K (Windows/Linux)
    const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0;
    const modifierKey = isMac ? event.metaKey : event.ctrlKey;

    if (modifierKey && event.key === "k") {
      event.preventDefault();
      event.stopPropagation();
      callback();
    }
  };

  document.addEventListener("keydown", globalShortcutHandler);

  // Return cleanup function
  return () => {
    if (globalShortcutHandler) {
      document.removeEventListener("keydown", globalShortcutHandler);
      globalShortcutHandler = null;
    }
  };
};

/**
 * Unregister global keyboard shortcut
 *
 * @param {Function} cleanup - Cleanup function from registerGlobalShortcut
 */
export const unregisterGlobalShortcut = (cleanup) => () => {
  if (typeof cleanup === "function") {
    cleanup();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // fuzzy search
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Calculate fuzzy match score (higher is better)
 *
 * Scoring factors:
 * - Sequential character matches (+3 points)
 * - Word boundary matches (+2 points)
 * - Start of string match (+4 points)
 * - Character match at any position (+1 point)
 * - Penalty for gaps (-1 point per gap)
 *
 * @param {string} query - Search query
 * @param {string} target - Target string to match against
 * @returns {number} Match score (0 if no match)
 */
export const fuzzyScore = (query) => (target) => {
  if (!query || !target) return 0;

  const q = query.toLowerCase();
  const t = target.toLowerCase();

  if (q === t) return 1000; // Exact match

  let score = 0;
  let queryIndex = 0;
  let lastMatchIndex = -1;
  let consecutiveMatches = 0;

  for (let i = 0; i < t.length && queryIndex < q.length; i++) {
    if (t[i] === q[queryIndex]) {
      // Base match score
      score += 1;

      // Bonus for sequential matches
      if (lastMatchIndex === i - 1) {
        consecutiveMatches++;
        score += consecutiveMatches * 3;
      } else {
        consecutiveMatches = 0;
        // Penalty for gaps
        if (lastMatchIndex >= 0) {
          score -= Math.min(i - lastMatchIndex - 1, 3);
        }
      }

      // Bonus for word boundary match
      if (i === 0 || isWordBoundary(t[i - 1])) {
        score += 2;
      }

      // Bonus for start of string
      if (i === 0) {
        score += 4;
      }

      // Bonus for camelCase match
      if (i > 0 && isUpperCase(target[i]) && isLowerCase(target[i - 1])) {
        score += 2;
      }

      lastMatchIndex = i;
      queryIndex++;
    }
  }

  // Return 0 if not all query characters matched
  if (queryIndex < q.length) {
    return 0;
  }

  // Bonus for shorter targets (more relevant match)
  score += Math.max(0, 10 - t.length);

  return score;
};

/**
 * Check if character is a word boundary
 */
function isWordBoundary(char) {
  return /[\s\-_./\\]/.test(char);
}

/**
 * Check if character is uppercase
 */
function isUpperCase(char) {
  return char === char.toUpperCase() && char !== char.toLowerCase();
}

/**
 * Check if character is lowercase
 */
function isLowerCase(char) {
  return char === char.toLowerCase() && char !== char.toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // keyboard navigation
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup keyboard navigation within command palette
 *
 * Handles:
 * - ArrowUp/ArrowDown - Navigate items
 * - Enter - Select current item
 * - Escape - Close palette
 * - Home/End - Jump to first/last item
 *
 * @param {HTMLElement} listElement - The command list element
 * @param {Object} callbacks - Event callbacks
 * @returns {Function} Cleanup function
 */
export const setupKeyboardNavigation =
  (listElement) => (callbacks) => () => {
    let currentIndex = -1;

    const getItems = () => {
      return listElement.querySelectorAll('[role="option"]:not([data-disabled="true"])');
    };

    const updateSelection = (index) => {
      const items = getItems();
      if (items.length === 0) return;

      // Remove previous selection
      items.forEach((item) => {
        item.setAttribute("aria-selected", "false");
        item.classList.remove("bg-accent", "text-accent-foreground");
      });

      // Clamp index
      currentIndex = Math.max(0, Math.min(index, items.length - 1));

      // Apply new selection
      const selectedItem = items[currentIndex];
      if (selectedItem) {
        selectedItem.setAttribute("aria-selected", "true");
        selectedItem.classList.add("bg-accent", "text-accent-foreground");
        selectedItem.scrollIntoView({ block: "nearest" });

        // Notify callback
        if (callbacks.onHighlight) {
          callbacks.onHighlight(currentIndex)();
        }
      }
    };

    const handleKeyDown = (event) => {
      const items = getItems();

      switch (event.key) {
        case "ArrowDown":
          event.preventDefault();
          updateSelection(currentIndex + 1);
          break;

        case "ArrowUp":
          event.preventDefault();
          updateSelection(currentIndex - 1);
          break;

        case "Home":
          event.preventDefault();
          updateSelection(0);
          break;

        case "End":
          event.preventDefault();
          updateSelection(items.length - 1);
          break;

        case "Enter":
          event.preventDefault();
          if (currentIndex >= 0 && currentIndex < items.length) {
            const selectedItem = items[currentIndex];
            if (selectedItem && callbacks.onSelect) {
              callbacks.onSelect(currentIndex)();
            }
          }
          break;

        case "Escape":
          event.preventDefault();
          if (callbacks.onClose) {
            callbacks.onClose();
          }
          break;
      }
    };

    // Attach handler
    document.addEventListener("keydown", handleKeyDown);

    // Initialize with first item
    updateSelection(0);

    // Return cleanup function
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
    };
  };

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // focus management
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Focus the command input when palette opens
 */
export const focusCommandInput = (element) => () => {
  const input = element.querySelector('input[role="combobox"]');
  if (input) {
    // Small delay to ensure DOM is ready
    requestAnimationFrame(() => {
      input.focus();
    });
  }
};

/**
 * Store and restore focus when palette opens/closes
 */
let previouslyFocusedElement = null;

export const saveFocus = () => {
  previouslyFocusedElement = document.activeElement;
};

export const restoreFocus = () => {
  if (
    previouslyFocusedElement &&
    typeof previouslyFocusedElement.focus === "function"
  ) {
    previouslyFocusedElement.focus();
    previouslyFocusedElement = null;
  }
};
