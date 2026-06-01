// Mockup chrome only — drives the state/theme preview, not product logic.
const panel = document.getElementById("panel");

function setPressed(group, attr, value, key) {
  group.querySelectorAll(".seg").forEach((b) => {
    b.setAttribute("aria-pressed", String(b.dataset[key] === value));
  });
}

// State switcher
const stateGroup = document.getElementById("states");
stateGroup.addEventListener("click", (e) => {
  const btn = e.target.closest(".seg");
  if (!btn) return;
  panel.dataset.state = btn.dataset.state;
  setPressed(stateGroup, "data-state", btn.dataset.state, "state");
});

// Truncated toggle
const truncBtn = document.getElementById("truncBtn");
truncBtn.addEventListener("click", () => {
  const on = panel.dataset.truncated !== "true";
  panel.dataset.truncated = String(on);
  truncBtn.setAttribute("aria-pressed", String(on));
});

// Theme switcher
const themeGroup = document.getElementById("themes");
themeGroup.addEventListener("click", (e) => {
  const btn = e.target.closest(".seg");
  if (!btn) return;
  document.documentElement.dataset.theme = btn.dataset.theme;
  setPressed(themeGroup, "data-theme", btn.dataset.theme, "theme");
});

// Copy button success morph (product behavior preview)
const copyBtn = document.getElementById("copyBtn");
let copyTimer;
copyBtn.addEventListener("click", () => {
  navigator.clipboard?.writeText(document.getElementById("targetText").textContent || "").catch(() => {});
  copyBtn.classList.add("is-done");
  copyBtn.setAttribute("aria-label", "Skopiowano");
  clearTimeout(copyTimer);
  copyTimer = setTimeout(() => {
    copyBtn.classList.remove("is-done");
    copyBtn.setAttribute("aria-label", "Kopiuj tłumaczenie");
  }, 1400);
});
