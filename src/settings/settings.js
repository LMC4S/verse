const shortcutButton = document.querySelector("#shortcutButton");
const autoPasteToggle = document.querySelector("#autoPasteToggle");
const engineSelect = document.querySelector("#engineSelect");
const mlxModelRow = document.querySelector("#mlxModelRow");
const mlxModelInput = document.querySelector("#mlxModelInput");
const saveEngineButton = document.querySelector("#saveEngineButton");
const apiKeyInput = document.querySelector("#apiKeyInput");
const saveApiKeyButton = document.querySelector("#saveApiKeyButton");
const apiKeyStatus = document.querySelector("#apiKeyStatus");
const localEngineText = document.querySelector("#localEngineText");
const installLocalEngineButton = document.querySelector("#installLocalEngineButton");
const removeLocalEngineButton = document.querySelector("#removeLocalEngineButton");
const openLocalEngineButton = document.querySelector("#openLocalEngineButton");
const statusText = document.querySelector("#statusText");

let localEngineInstalled = false;

function setStatus(message) {
  statusText.textContent = message || "";
}

function setBusy(isBusy) {
  for (const button of [
    saveEngineButton,
    saveApiKeyButton,
    installLocalEngineButton,
    openLocalEngineButton,
  ]) {
    button.disabled = isBusy;
  }
  removeLocalEngineButton.disabled = isBusy || !localEngineInstalled;
}

function shortcutLabel(accelerator) {
  return String(accelerator || "")
    .replace("Control", "⌃")
    .replace("Alt", "⌥")
    .replace("Shift", "⇧")
    .replace("Command", "⌘")
    .replaceAll("+", "");
}

function applySettings(settings) {
  engineSelect.value = settings.engine || "openai";
  mlxModelInput.value = settings.mlxModel || "";
  mlxModelRow.style.display = engineSelect.value === "mlx" ? "" : "none";
  apiKeyStatus.textContent = settings.hasApiKey
    ? "A key is saved. Enter a new one to replace it."
    : "No key saved yet.";
  if (settings.shortcut) shortcutButton.textContent = shortcutLabel(settings.shortcut);
  autoPasteToggle.checked = Boolean(settings.autoPaste);
}

function renderLocalEngineStatus(status) {
  localEngineInstalled = Boolean(status.installed);
  localEngineText.textContent = `${status.installed ? "Installed" : "Not installed"} — ${status.path}`;
  removeLocalEngineButton.disabled = !status.installed;
}

async function refreshLocalEngineStatus() {
  try {
    renderLocalEngineStatus(await window.verse.getLocalEngineStatus());
  } catch (error) {
    localEngineText.textContent = error.message;
  }
}

async function load() {
  try {
    applySettings(await window.verse.getSettings());
    await refreshLocalEngineStatus();
    setStatus("");
  } catch (error) {
    setStatus(error.message);
  }
}

engineSelect.addEventListener("change", () => {
  mlxModelRow.style.display = engineSelect.value === "mlx" ? "" : "none";
});

// --- Shortcut recorder ---

const KEY_CODE_MAP = {
  Space: "Space",
  Backquote: "`",
  Minus: "-",
  Equal: "=",
  BracketLeft: "[",
  BracketRight: "]",
  Backslash: "\\",
  Semicolon: ";",
  Quote: "'",
  Comma: ",",
  Period: ".",
  Slash: "/",
  Enter: "Return",
  Tab: "Tab",
  Backspace: "Backspace",
  Delete: "Delete",
  ArrowUp: "Up",
  ArrowDown: "Down",
  ArrowLeft: "Left",
  ArrowRight: "Right",
  Home: "Home",
  End: "End",
  PageUp: "PageUp",
  PageDown: "PageDown",
};

function acceleratorKeyFromEvent(event) {
  const code = event.code;
  if (/^Key[A-Z]$/u.test(code)) return code.slice(3);
  if (/^Digit[0-9]$/u.test(code)) return code.slice(5);
  if (/^F([1-9]|1[0-9]|2[0-4])$/u.test(code)) return code;
  if (/^Numpad[0-9]$/u.test(code)) return `num${code.slice(6)}`;
  return KEY_CODE_MAP[code] || null;
}

function acceleratorFromEvent(event) {
  const key = acceleratorKeyFromEvent(event);
  if (!key) return null;
  const modifiers = [];
  if (event.ctrlKey) modifiers.push("Control");
  if (event.altKey) modifiers.push("Alt");
  if (event.shiftKey) modifiers.push("Shift");
  if (event.metaKey) modifiers.push("Command");
  // Bare keys would swallow normal typing system-wide; only F-keys may stand alone.
  if (!modifiers.length && !/^F\d+$/u.test(key)) return null;
  return [...modifiers, key].join("+");
}

let capturingShortcut = false;

function stopCapturing(labelText) {
  capturingShortcut = false;
  shortcutButton.classList.remove("capturing");
  if (labelText) shortcutButton.textContent = labelText;
}

shortcutButton.addEventListener("click", () => {
  if (capturingShortcut) return;
  capturingShortcut = true;
  shortcutButton.dataset.previous = shortcutButton.textContent;
  shortcutButton.textContent = "Press keys…";
  shortcutButton.classList.add("capturing");
  setStatus("Recording shortcut — press Esc to cancel.");
});

window.addEventListener(
  "keydown",
  async (event) => {
    if (!capturingShortcut) return;
    event.preventDefault();
    event.stopPropagation();

    if (event.key === "Escape") {
      stopCapturing(shortcutButton.dataset.previous);
      setStatus("");
      return;
    }
    if (["Shift", "Control", "Alt", "Meta", "CapsLock"].includes(event.key)) return;

    const accelerator = acceleratorFromEvent(event);
    if (!accelerator) {
      setStatus("Use a function key alone, or add ⌘, ⌥, ⌃, or ⇧ to that key.");
      return;
    }
    try {
      const settings = await window.verse.saveShortcut(accelerator);
      stopCapturing();
      applySettings(settings);
      setStatus(`Shortcut set to ${shortcutLabel(settings.shortcut)}.`);
    } catch (error) {
      stopCapturing(shortcutButton.dataset.previous);
      setStatus(error.message.replace(/^Error invoking remote method '[^']+': (Error: )?/u, ""));
    }
  },
  true
);

autoPasteToggle.addEventListener("change", async () => {
  try {
    const settings = await window.verse.saveAutoPaste(autoPasteToggle.checked);
    applySettings(settings);
    setStatus(settings.autoPaste ? "Auto-paste on." : "Auto-paste off — clipboard only.");
  } catch (error) {
    setStatus(error.message);
  }
});

saveEngineButton.addEventListener("click", async () => {
  setBusy(true);
  try {
    const settings = await window.verse.saveTranscriptionSettings({
      engine: engineSelect.value,
      mlxModel: mlxModelInput.value,
    });
    applySettings(settings);
    setStatus(settings.engine === "mlx" ? "Local MLX enabled." : "OpenAI API enabled.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
  }
});

saveApiKeyButton.addEventListener("click", async () => {
  const apiKey = apiKeyInput.value.trim();
  if (!apiKey) {
    setStatus("Enter an API key first.");
    return;
  }
  setBusy(true);
  try {
    const settings = await window.verse.saveApiKey(apiKey);
    apiKeyInput.value = "";
    applySettings(settings);
    setStatus("API key saved.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
  }
});

installLocalEngineButton.addEventListener("click", async () => {
  setBusy(true);
  setStatus("Installing Local MLX… this can take a few minutes.");
  try {
    renderLocalEngineStatus(await window.verse.installLocalEngine());
    setStatus("Local MLX installed.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
  }
});

removeLocalEngineButton.addEventListener("click", async () => {
  setBusy(true);
  try {
    renderLocalEngineStatus(await window.verse.removeLocalEngine());
    setStatus("Local MLX removed.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
  }
});

openLocalEngineButton.addEventListener("click", async () => {
  try {
    await window.verse.openLocalEngineFolder();
  } catch (error) {
    setStatus(error.message);
  }
});

load();
