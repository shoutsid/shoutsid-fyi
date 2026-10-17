/* Resolves the theme and sets it on <html> before the stylesheet is applied.
 *
 * This runs from <head>, synchronously, and deliberately does almost nothing:
 * read localStorage, fall back to the OS preference, set one attribute. Doing
 * it here rather than on DOMContentLoaded is what stops the page painting in
 * the wrong palette and then switching.
 *
 * Loaded as an external file rather than inline so the Content-Security-Policy
 * can stay `script-src 'self'` with no exceptions.
 */
(function () {
  "use strict";

  var STORAGE_KEY = "theme";

  function stored() {
    try {
      var value = window.localStorage.getItem(STORAGE_KEY);
      return value === "light" || value === "dark" ? value : null;
    } catch (error) {
      /* Private mode or storage disabled: the OS preference still applies. */
      return null;
    }
  }

  function systemPreference() {
    if (!window.matchMedia) return "light";
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  document.documentElement.setAttribute("data-theme", stored() || systemPreference());
})();
