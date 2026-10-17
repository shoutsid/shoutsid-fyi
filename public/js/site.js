/* Theme toggle.
 *
 * theme-boot.js has already chosen the initial theme by the time this runs, so
 * this file only handles the click and keeps the button's accessible state in
 * step with what is actually displayed.
 *
 * The site is fully readable without JavaScript: the stylesheet honours
 * prefers-color-scheme on its own, and the toggle is an enhancement rather
 * than the only way to get a readable page.
 */
(function () {
  "use strict";

  var root = document.documentElement;
  var button = document.querySelector("[data-theme-toggle]");
  var STORAGE_KEY = "theme";

  function currentTheme() {
    return root.getAttribute("data-theme") === "dark" ? "dark" : "light";
  }

  function syncButton() {
    if (!button) return;
    var isDark = currentTheme() === "dark";
    // aria-pressed describes the button, not the page: "pressed" means the
    // dark theme is on, which is what a screen reader should hear.
    button.setAttribute("aria-pressed", isDark ? "true" : "false");
    button.setAttribute("title", isDark ? "Switch to light theme" : "Switch to dark theme");
  }

  syncButton();

  if (button) {
    button.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try {
        window.localStorage.setItem(STORAGE_KEY, next);
      } catch (error) {
        /* Not being able to remember the choice is not a reason to fail the click. */
      }
      syncButton();
    });
  }

  /* If the visitor has never made an explicit choice, follow the OS when it
   * changes mid-visit. Once they have chosen, their choice wins. */
  if (window.matchMedia) {
    var query = window.matchMedia("(prefers-color-scheme: dark)");
    var listener = function (event) {
      var explicit = null;
      try {
        explicit = window.localStorage.getItem(STORAGE_KEY);
      } catch (error) {
        explicit = null;
      }
      if (explicit === "light" || explicit === "dark") return;
      root.setAttribute("data-theme", event.matches ? "dark" : "light");
      syncButton();
    };

    if (query.addEventListener) {
      query.addEventListener("change", listener);
    } else if (query.addListener) {
      query.addListener(listener);
    }
  }

  /* The print control on the CV page. It is a button because it performs an
   * action rather than going somewhere; without JavaScript it does nothing,
   * and the CV is still readable and printable through the browser's own
   * print command. */
  var printButton = document.querySelector("[data-print]");
  if (printButton) {
    printButton.addEventListener("click", function () {
      window.print();
    });

    /* The homepage offers the download beside the online CV, and it cannot
     * print from there — the action belongs to this page. So it links here
     * with ?download=1 and the CV opens the save-as-PDF dialog once it has
     * painted. Nothing prints unless that link was followed. */
    if (/[?&]download=1(&|$)/.test(window.location.search)) {
      setTimeout(function () {
        window.print();
      }, 250);
    }
  }
})();
