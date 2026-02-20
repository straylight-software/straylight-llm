// FFI for Hydrogen.HTML.Renderer

// Props are passed as an Array of Prop values, which we can inspect at runtime
export const unsafeToProps = (props) => {
  // If props is undefined or null, return empty array
  if (props == null) return [];
  // If it's already an array, return it
  if (Array.isArray(props)) return props;
  // Otherwise return empty
  return [];
};

// Convert a PropValue to a string representation
// PropValue is an opaque type that can be string, boolean, number, etc.
export const propValueToString = (value) => {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "number") {
    return String(value);
  }
  if (typeof value === "string") {
    return value;
  }
  // For objects, try toString
  return String(value);
};
