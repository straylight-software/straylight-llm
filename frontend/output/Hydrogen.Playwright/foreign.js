// Playwright FFI bindings for PureScript
// Requires: npm install playwright

import { createRequire } from "module";
const require = createRequire(import.meta.url);
const pw = require("playwright");

// =============================================================================
//                                                                       LAUNCH
// =============================================================================

export const launchImpl = (browserType) => (options) => (onError, onSuccess) => {
  pw[browserType]
    .launch({
      headless: options.headless,
      slowMo: options.slowMo,
      timeout: options.timeout,
      devtools: options.devtools,
    })
    .then(onSuccess)
    .catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const launchPersistentContextImpl =
  (browserType) => (userDataDir) => (options) => (onError, onSuccess) => {
    pw[browserType]
      .launchPersistentContext(userDataDir, {
        headless: options.headless,
        slowMo: options.slowMo,
        timeout: options.timeout,
        devtools: options.devtools,
      })
      .then(onSuccess)
      .catch(onError);
    return (cancelError, onCancelerError, onCancelerSuccess) => {
      onCancelerSuccess();
    };
  };

export const closeImpl = (browser) => (onError, onSuccess) => {
  browser.close().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const newContextImpl = (browser) => (onError, onSuccess) => {
  browser.newContext().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const newPageImpl = (browser) => (onError, onSuccess) => {
  browser.newPage().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                   NAVIGATION
// =============================================================================

export const gotoImpl = (page) => (url) => (onError, onSuccess) => {
  page.goto(url).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const goBackImpl = (page) => (onError, onSuccess) => {
  page.goBack().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const goForwardImpl = (page) => (onError, onSuccess) => {
  page.goForward().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const reloadImpl = (page) => (onError, onSuccess) => {
  page.reload().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const waitForLoadStateImpl = (page) => (state) => (onError, onSuccess) => {
  page.waitForLoadState(state).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                    SELECTORS
// =============================================================================

export const locatorImpl = (page) => (selector) => () => {
  return page.locator(selector);
};

export const getByRoleImpl = (page) => (role) => () => {
  return page.getByRole(role);
};

export const getByTextImpl = (page) => (text) => () => {
  return page.getByText(text);
};

export const getByTestIdImpl = (page) => (testId) => () => {
  return page.getByTestId(testId);
};

export const getByLabelImpl = (page) => (label) => () => {
  return page.getByLabel(label);
};

export const getByPlaceholderImpl = (page) => (placeholder) => () => {
  return page.getByPlaceholder(placeholder);
};

export const firstImpl = (locator) => () => {
  return locator.first();
};

export const lastImpl = (locator) => () => {
  return locator.last();
};

export const nthImpl = (locator) => (n) => () => {
  return locator.nth(n);
};

export const countImpl = (locator) => (onError, onSuccess) => {
  locator.count().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                 INTERACTIONS
// =============================================================================

export const clickImpl = (locator) => (onError, onSuccess) => {
  locator.click().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const dblclickImpl = (locator) => (onError, onSuccess) => {
  locator.dblclick().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const fillImpl = (locator) => (text) => (onError, onSuccess) => {
  locator.fill(text).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const typeImpl = (locator) => (text) => (onError, onSuccess) => {
  locator.type(text).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const pressImpl = (locator) => (key) => (onError, onSuccess) => {
  locator.press(key).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const checkImpl = (locator) => (onError, onSuccess) => {
  locator.check().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const uncheckImpl = (locator) => (onError, onSuccess) => {
  locator.uncheck().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const selectOptionImpl = (locator) => (value) => (onError, onSuccess) => {
  locator.selectOption(value).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const hoverImpl = (locator) => (onError, onSuccess) => {
  locator.hover().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const focusImpl = (locator) => (onError, onSuccess) => {
  locator.focus().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const blurImpl = (locator) => (onError, onSuccess) => {
  locator.blur().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                ELEMENT STATE
// =============================================================================

export const isVisibleImpl = (locator) => (onError, onSuccess) => {
  locator.isVisible().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const isHiddenImpl = (locator) => (onError, onSuccess) => {
  locator.isHidden().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const isEnabledImpl = (locator) => (onError, onSuccess) => {
  locator.isEnabled().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const isDisabledImpl = (locator) => (onError, onSuccess) => {
  locator.isDisabled().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const isCheckedImpl = (locator) => (onError, onSuccess) => {
  locator.isChecked().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const textContentImpl = (locator) => (onError, onSuccess) => {
  locator.textContent().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const innerTextImpl = (locator) => (onError, onSuccess) => {
  locator.innerText().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const innerHTMLImpl = (locator) => (onError, onSuccess) => {
  locator.innerHTML().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const getAttributeImpl = (locator) => (attr) => (onError, onSuccess) => {
  locator.getAttribute(attr).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const inputValueImpl = (locator) => (onError, onSuccess) => {
  locator.inputValue().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                      WAITING
// =============================================================================

export const waitForSelectorImpl = (page) => (selector) => (onError, onSuccess) => {
  page.waitForSelector(selector).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const waitForTimeoutImpl = (page) => (ms) => (onError, onSuccess) => {
  page.waitForTimeout(ms).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const waitForURLImpl = (page) => (url) => (onError, onSuccess) => {
  page.waitForURL(url).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const waitForFunctionImpl = (page) => (fn) => (onError, onSuccess) => {
  page.waitForFunction(fn).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                              SCREENSHOTS/PDF
// =============================================================================

export const screenshotImpl = (page) => (options) => (onError, onSuccess) => {
  const opts = {};
  if (options.path) opts.path = options.path;
  if (options.fullPage) opts.fullPage = options.fullPage;
  if (options.type) opts.type = options.type;
  if (options.quality && options.type === "jpeg") opts.quality = options.quality;

  page.screenshot(opts).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const screenshotElementImpl = (locator) => (options) => (onError, onSuccess) => {
  const opts = {};
  if (options.path) opts.path = options.path;
  if (options.type) opts.type = options.type;
  if (options.quality && options.type === "jpeg") opts.quality = options.quality;

  locator.screenshot(opts).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const pdfImpl = (page) => (options) => (onError, onSuccess) => {
  page
    .pdf({
      path: options.path || undefined,
      format: options.format,
      printBackground: options.printBackground,
      margin: options.margin,
    })
    .then(onSuccess)
    .catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                   EVALUATION
// =============================================================================

export const evaluateImpl = (page) => (script) => (onError, onSuccess) => {
  page
    .evaluate(script)
    .then((result) => onSuccess(JSON.stringify(result)))
    .catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const evaluateHandleImpl = (page) => (script) => (onError, onSuccess) => {
  page.evaluateHandle(script).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

// =============================================================================
//                                                                    PAGE INFO
// =============================================================================

export const urlImpl = (page) => () => {
  return page.url();
};

export const titleImpl = (page) => (onError, onSuccess) => {
  page.title().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const contentImpl = (page) => (onError, onSuccess) => {
  page.content().then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};

export const setContentImpl = (page) => (html) => (onError, onSuccess) => {
  page.setContent(html).then(onSuccess).catch(onError);
  return (cancelError, onCancelerError, onCancelerSuccess) => {
    onCancelerSuccess();
  };
};
