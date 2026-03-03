// I18n formatting FFI for Hydrogen

export const formatNumberImpl = (locale) => (number) => {
  try {
    return new Intl.NumberFormat(locale).format(number);
  } catch (e) {
    return String(number);
  }
};

export const formatCurrencyImpl = (locale) => (amount) => (currency) => {
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency: currency
    }).format(amount);
  } catch (e) {
    return `${currency} ${amount}`;
  }
};

export const formatDateImpl = (locale) => (dateStr) => (format) => {
  try {
    const date = new Date(dateStr);
    const options = {};
    
    if (format === 'short') {
      options.dateStyle = 'short';
    } else if (format === 'medium') {
      options.dateStyle = 'medium';
    } else if (format === 'long') {
      options.dateStyle = 'long';
    } else if (format === 'full') {
      options.dateStyle = 'full';
    }
    
    return new Intl.DateTimeFormat(locale, options).format(date);
  } catch (e) {
    return dateStr;
  }
};

export const formatRelativeTimeImpl = (locale) => (value) => (unit) => {
  try {
    const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });
    return rtf.format(value, unit);
  } catch (e) {
    return `${value} ${unit}`;
  }
};
