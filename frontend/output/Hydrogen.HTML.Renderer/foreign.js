// FFI for Hydrogen.HTML.Renderer
//
// PropValue is a foreign data type in Halogen (see Halogen.VDom.DOM.Prop).
// It holds JavaScript primitives (string, boolean, number) at runtime.
// This FFI inspects the runtime type to convert to a string representation.

// Convert a PropValue to a string representation.
// PropValue is an opaque foreign type that can be string, boolean, number, etc.
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
