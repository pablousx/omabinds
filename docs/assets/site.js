(() => {
  "use strict";

  const root = document.documentElement;
  const button = document.querySelector("[data-theme-toggle]");
  const themeMeta = document.querySelector('meta[name="theme-color"]');
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)");

  function effectiveTheme(theme) {
    return theme === "auto" ? (prefersDark.matches ? "dark" : "light") : theme;
  }

  function applyTheme(theme) {
    root.dataset.theme = theme;
    const effective = effectiveTheme(theme);
    themeMeta.content = effective === "dark" ? "#101318" : "#f4f0e8";
    if (button) {
      button.querySelector("[data-theme-icon]").textContent = effective === "dark" ? "☀" : "☾";
      button.querySelector("[data-theme-label]").textContent = effective === "dark" ? "Usar tema claro" : "Usar tema oscuro";
      button.setAttribute("aria-pressed", String(effective === "dark"));
    }
  }

  let savedTheme = "auto";
  try {
    savedTheme = localStorage.getItem("omabinds-theme") || "auto";
  } catch {
    // The preference is optional.
  }
  applyTheme(savedTheme);

  if (button) {
    button.hidden = false;
    button.addEventListener("click", () => {
      const next = effectiveTheme(root.dataset.theme) === "dark" ? "light" : "dark";
      applyTheme(next);
      try {
        localStorage.setItem("omabinds-theme", next);
      } catch {
        // The page still works when storage is unavailable.
      }
    });
  }

  prefersDark.addEventListener?.("change", () => {
    if (root.dataset.theme === "auto") applyTheme("auto");
  });

  const copyButton = document.querySelector("[data-copy]");
  if (copyButton && navigator.clipboard && window.isSecureContext) {
    copyButton.hidden = false;
    copyButton.addEventListener("click", async () => {
      const status = document.querySelector("[data-copy-status]");
      try {
        await navigator.clipboard.writeText(document.querySelector("#install-command").textContent);
        status.textContent = "Comando copiado.";
      } catch {
        status.textContent = "No se pudo copiar. Selecciona el comando manualmente.";
      }
    });
  }
})();
