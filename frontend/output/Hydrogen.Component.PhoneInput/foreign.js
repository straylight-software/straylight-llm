// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                     // hydrogen // phoneinput
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Phone input formatting and validation

// Country format patterns (simplified)
const countryFormats = {
  US: { pattern: "(###) ###-####", regex: /^\d{10}$/ },
  GB: { pattern: "#### ### ####", regex: /^\d{10,11}$/ },
  CA: { pattern: "(###) ###-####", regex: /^\d{10}$/ },
  AU: { pattern: "#### ### ###", regex: /^\d{9,10}$/ },
  DE: { pattern: "### #######", regex: /^\d{10,11}$/ },
  FR: { pattern: "## ## ## ## ##", regex: /^\d{9,10}$/ },
  // Add more as needed
};

/**
 * Initialize phone input formatting
 */
export const initPhoneInputImpl = (element, onChange) => {
  const input = element.querySelector('input[type="tel"]');
  if (!input) return { element, cleanup: () => {} };

  const handleInput = (e) => {
    const countryCode = element.dataset.country || "US";
    const rawValue = e.target.value.replace(/\D/g, "");
    const formatted = formatPhoneNumber(rawValue, countryCode);
    const isValid = validatePhoneNumber(rawValue, countryCode);

    e.target.value = formatted;

    const format = countryFormats[countryCode] || countryFormats.US;
    const dialCode = getDialCode(countryCode);

    onChange({
      country: countryCode,
      number: rawValue,
      formatted: formatted,
      isValid: isValid,
      e164: isValid ? dialCode + rawValue : "",
    })();
  };

  input.addEventListener("input", handleInput);

  return {
    element,
    cleanup: () => {
      input.removeEventListener("input", handleInput);
    },
  };
};

/**
 * Get dial code for country
 */
const getDialCode = (countryCode) => {
  const dialCodes = {
    US: "+1",
    CA: "+1",
    GB: "+44",
    AU: "+61",
    DE: "+49",
    FR: "+33",
    IT: "+39",
    ES: "+34",
    JP: "+81",
    CN: "+86",
    IN: "+91",
    BR: "+55",
    MX: "+52",
    RU: "+7",
  };
  return dialCodes[countryCode] || "+1";
};

/**
 * Format phone number for display
 */
export const formatPhoneNumberImpl = (number) => (countryCode) => {
  const digits = number.replace(/\D/g, "");
  return formatPhoneNumber(digits, countryCode);
};

const formatPhoneNumber = (digits, countryCode) => {
  const format = countryFormats[countryCode] || countryFormats.US;
  const pattern = format.pattern;

  let result = "";
  let digitIndex = 0;

  for (let i = 0; i < pattern.length && digitIndex < digits.length; i++) {
    if (pattern[i] === "#") {
      result += digits[digitIndex];
      digitIndex++;
    } else {
      result += pattern[i];
    }
  }

  // If more digits than pattern, append them
  if (digitIndex < digits.length) {
    result += digits.slice(digitIndex);
  }

  return result;
};

/**
 * Validate phone number
 */
export const validatePhoneNumberImpl = (number) => (countryCode) => {
  return validatePhoneNumber(number, countryCode);
};

const validatePhoneNumber = (number, countryCode) => {
  const digits = number.replace(/\D/g, "");
  const format = countryFormats[countryCode] || countryFormats.US;

  // Basic validation - check digit count
  const minLength = format.pattern.split("#").length - 1;
  const maxLength = minLength + 2; // Allow some flexibility

  return digits.length >= minLength - 2 && digits.length <= maxLength;
};

/**
 * Auto-detect country from IP
 */
export const detectCountryImpl = (onCountry) => {
  // Use free IP geolocation service
  fetch("https://ipapi.co/json/")
    .then((response) => response.json())
    .then((data) => {
      if (data.country_code) {
        onCountry(data.country_code)();
      }
    })
    .catch((err) => {
      console.log("Could not detect country:", err);
      // Default to US
      onCountry("US")();
    });
};

/**
 * Cleanup phone input
 */
export const destroyPhoneInputImpl = (phoneObj) => {
  if (phoneObj && phoneObj.cleanup) {
    phoneObj.cleanup();
  }
};


