// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                        // hydrogen // flags
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const STORAGE_KEY = "hydrogen:feature-flags:overrides";

// Hash function for consistent assignment
export const hashString = (str) => {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash);
};

export const toNumber = (n) => n;

export const unsafeRefEq = (a) => (b) => a === b;

export const traverseImpl = (f) => (arr) => () => {
  const results = [];
  for (let i = 0; i < arr.length; i++) {
    results.push(f(arr[i])());
  }
  return results;
};

// Persistence

export const loadPersistedOverrides = (overridesRef) => () => {
  try {
    if (typeof localStorage === "undefined") return;
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      // Convert to Map format expected by PureScript
      // This is a simplified implementation
      overridesRef.value = parsed;
    }
  } catch (e) {
    console.warn("Failed to load persisted flag overrides:", e);
  }
};

export const persistOverrides = (overridesRef) => () => {
  try {
    if (typeof localStorage === "undefined") return;
    const overrides = overridesRef.value;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(overrides));
  } catch (e) {
    console.warn("Failed to persist flag overrides:", e);
  }
};

// JSON Loading

export const parseJsonFlags = (json) => () => {
  try {
    const data = JSON.parse(json);
    // Convert JSON to Map of FlagDefinitions
    // This is a simplified implementation that would need to match
    // the PureScript FlagDefinition type
    const result = new Map();

    if (data.flags && Array.isArray(data.flags)) {
      for (const flagDef of data.flags) {
        const flag = { value0: flagDef.name }; // Flag newtype
        result.set(flag.value0, {
          flag,
          defaultValue: convertValue(flagDef.defaultValue),
          rules: (flagDef.rules || []).map(convertRule),
          metadata: {
            description: flagDef.description || null,
            tags: flagDef.tags || [],
          },
        });
      }
    }

    return result;
  } catch (e) {
    console.error("Failed to parse flags JSON:", e);
    return new Map();
  }
};

function convertValue(value) {
  if (typeof value === "boolean") {
    return { tag: "BoolValue", value0: value };
  } else if (typeof value === "string") {
    return { tag: "StringValue", value0: value };
  } else if (typeof value === "number") {
    return { tag: "NumberValue", value0: value };
  } else if (typeof value === "object") {
    return { tag: "JsonValue", value0: value };
  }
  return { tag: "BoolValue", value0: false };
}

function convertRule(rule) {
  // Simplified rule conversion
  return {
    condition: convertCondition(rule.condition),
    value: convertValue(rule.value),
  };
}

function convertCondition(condition) {
  if (!condition) return { tag: "Never" };

  switch (condition.type) {
    case "percentage":
      return { tag: "Percentage", value0: condition.value };
    case "userIds":
      return { tag: "UserIds", value0: condition.value };
    case "environment":
      return { tag: "Environment", value0: condition.value };
    case "always":
      return { tag: "Always" };
    case "never":
      return { tag: "Never" };
    default:
      return { tag: "Never" };
  }
}

// Remote fetching

export const fetchJson = (url) => () => {
  return fetch(url)
    .then((response) => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.text();
    })
    .catch((error) => {
      console.error("Failed to fetch flags:", error);
      return "{}";
    });
};
