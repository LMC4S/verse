const root = document.documentElement;
const settingsButton = document.querySelector("#settingsButton");
const settingsPanel = document.querySelector("#settingsPanel");
const apiKeyInput = document.querySelector("#apiKeyInput");
const saveApiKeyButton = document.querySelector("#saveApiKeyButton");
const saveRootText = document.querySelector("#saveRootText");
const chooseFolderButton = document.querySelector("#chooseFolderButton");
const openFolderButton = document.querySelector("#openFolderButton");
const engineSelect = document.querySelector("#engineSelect");
const mlxModelInput = document.querySelector("#mlxModelInput");
const saveEngineButton = document.querySelector("#saveEngineButton");
const localEngineText = document.querySelector("#localEngineText");
const installLocalEngineButton = document.querySelector("#installLocalEngineButton");
const removeLocalEngineButton = document.querySelector("#removeLocalEngineButton");
const openLocalEngineButton = document.querySelector("#openLocalEngineButton");
const recordButton = document.querySelector("#recordButton");
const recordLabel = document.querySelector("#recordLabel");
const recordingTime = document.querySelector("#recordingTime");
const chooseFileButton = document.querySelector("#chooseFileButton");
const fileInput = document.querySelector("#fileInput");
const fileName = document.querySelector("#fileName");
const dropZone = document.querySelector("#dropZone");
const statusText = document.querySelector("#statusText");
const transcript = document.querySelector("#transcript");
const transcribeButton = document.querySelector("#transcribeButton");
const saveButton = document.querySelector("#saveButton");
const openSavedButton = document.querySelector("#openSavedButton");
const copyButton = document.querySelector("#copyButton");
const nameDialog = document.querySelector("#nameDialog");
const nameDialogTitle = document.querySelector("#nameDialogTitle");
const nameInput = document.querySelector("#nameInput");
const saveAudioOption = document.querySelector("#saveAudioOption");
const saveTranscriptOption = document.querySelector("#saveTranscriptOption");
const nameCancelButton = document.querySelector("#nameCancelButton");
const nameConfirmButton = document.querySelector("#nameConfirmButton");

let mediaRecorder = null;
let recordedChunks = [];
let startedAt = 0;
let timer = null;
let currentAudio = null;
let currentSourceName = "recording";
let pendingNameResolver = null;
let localEngineInstalled = false;
let lastSavedPath = "";

function setStatus(message) {
  statusText.textContent = message;
}

function compactPath(filePath) {
  if (!filePath) return "";
  return filePath.split("/").slice(-2).join("/");
}

function suggestedName(sourceName, fallback) {
  const name = (sourceName || fallback || "recording").replace(/\.[^/.]+$/, "");
  return name || fallback || "recording";
}

function askName(title, defaultName) {
  const hasAudio = Boolean(currentAudio);
  const hasTranscript = Boolean(transcript.value.trim());
  nameDialogTitle.textContent = title;
  nameInput.value = defaultName || "";
  saveAudioOption.checked = hasAudio;
  saveAudioOption.disabled = !hasAudio;
  saveTranscriptOption.checked = hasTranscript;
  saveTranscriptOption.disabled = !hasTranscript;
  nameDialog.classList.remove("hidden");
  nameInput.focus();
  nameInput.select();

  return new Promise((resolve) => {
    pendingNameResolver = resolve;
  });
}

function closeNameDialog(value) {
  nameDialog.classList.add("hidden");
  if (pendingNameResolver) {
    pendingNameResolver(value);
    pendingNameResolver = null;
  }
}

function setBusy(isBusy) {
  recordButton.disabled = isBusy;
  chooseFileButton.disabled = isBusy;
  saveApiKeyButton.disabled = isBusy;
  chooseFolderButton.disabled = isBusy;
  openFolderButton.disabled = isBusy;
  saveEngineButton.disabled = isBusy;
  installLocalEngineButton.disabled = isBusy;
  removeLocalEngineButton.disabled = isBusy || !localEngineInstalled;
  openLocalEngineButton.disabled = isBusy;
  transcribeButton.disabled = isBusy || !currentAudio;
  saveButton.disabled = isBusy || (!currentAudio && !transcript.value.trim());
  openSavedButton.disabled = isBusy || !lastSavedPath;
  copyButton.disabled = isBusy || !transcript.value;
}

function setResultActions() {
  transcribeButton.disabled = !currentAudio;
  saveButton.disabled = !currentAudio && !transcript.value.trim();
  openSavedButton.disabled = !lastSavedPath;
  copyButton.disabled = !transcript.value;
}

function recordingType() {
  const candidates = ["audio/webm", "audio/mp4"];
  return candidates.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

function extensionForType(type) {
  if (type.includes("mp4")) return "mp4";
  return "webm";
}

function formatTime(ms) {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0");
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function startTimer() {
  startedAt = Date.now();
  recordingTime.textContent = "00:00";
  timer = window.setInterval(() => {
    recordingTime.textContent = formatTime(Date.now() - startedAt);
  }, 250);
}

function stopTimer() {
  window.clearInterval(timer);
  timer = null;
}

async function audioFromFile(file) {
  return {
    bytes: new Uint8Array(await file.arrayBuffer()),
    fileName: file.name || "recording.webm",
    mimeType: file.type || "application/octet-stream",
  };
}

async function prepareAudio(file, message) {
  currentAudio = await audioFromFile(file);
  currentSourceName = file.name || "recording";
  lastSavedPath = "";
  transcript.value = "";
  setResultActions();
  setStatus(message || "Audio ready.");
}

async function loadSettings() {
  try {
    const settings = await window.whisper.getSettings();
    saveRootText.textContent = settings.saveRoot;
    engineSelect.value = settings.engine || "openai";
    mlxModelInput.value = settings.mlxModel || "mlx-community/whisper-large-v3-turbo";
    const localStatus = await refreshLocalEngineStatus();
    if (settings.engine === "mlx" && !localStatus?.installed) {
      setStatus("Install Local MLX before transcribing.");
    } else {
      setStatus(settings.engine === "mlx" || settings.hasApiKey ? "Ready" : "Save an API key before transcribing.");
    }
  } catch (error) {
    setStatus(error.message);
  }
}

function renderLocalEngineStatus(status) {
  localEngineInstalled = Boolean(status.installed);
  const state = status.installed ? "Installed" : "Not installed";
  localEngineText.textContent = `${state} - ${status.path}`;
  removeLocalEngineButton.disabled = !status.installed;
}

async function refreshLocalEngineStatus() {
  try {
    const status = await window.whisper.getLocalEngineStatus();
    renderLocalEngineStatus(status);
    return status;
  } catch (error) {
    localEngineText.textContent = error.message;
    return null;
  }
}

async function saveApiKey() {
  const apiKey = apiKeyInput.value.trim();
  if (!apiKey) {
    setStatus("Enter an API key first.");
    return;
  }
  setBusy(true);
  try {
    const settings = await window.whisper.saveApiKey(apiKey);
    apiKeyInput.value = "";
    saveRootText.textContent = settings.saveRoot;
    setStatus("API key saved.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
}

async function chooseSaveRoot() {
  setBusy(true);
  try {
    const settings = await window.whisper.chooseSaveRoot();
    saveRootText.textContent = settings.saveRoot;
    setStatus(`Save folder set to ${compactPath(settings.saveRoot)}.`);
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
}

async function saveTranscriptionSettings() {
  setBusy(true);
  try {
    const settings = await window.whisper.saveTranscriptionSettings({
      engine: engineSelect.value,
      mlxModel: mlxModelInput.value,
    });
    engineSelect.value = settings.engine || "openai";
    mlxModelInput.value = settings.mlxModel || "mlx-community/whisper-large-v3-turbo";
    setStatus(settings.engine === "mlx" ? "Local MLX enabled." : "OpenAI API enabled.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
}

async function transcribeAudio() {
  if (!currentAudio) {
    setStatus("Record or choose audio first.");
    return;
  }
  setBusy(true);
  setStatus("Transcribing...");
  transcript.value = "";
  setResultActions();
  try {
    const result = await window.whisper.transcribeAudio(currentAudio);
    transcript.value = result.text || "";
    setStatus("Done.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
}

async function startRecording() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mimeType = recordingType();
    const options = mimeType ? { mimeType } : undefined;
    recordedChunks = [];
    mediaRecorder = new MediaRecorder(stream, options);

    mediaRecorder.addEventListener("dataavailable", (event) => {
      if (event.data.size > 0) recordedChunks.push(event.data);
    });

    mediaRecorder.addEventListener("stop", async () => {
      stream.getTracks().forEach((track) => track.stop());
      root.classList.remove("recording");
      recordLabel.textContent = "Start Talking";
      stopTimer();

      const type = mediaRecorder.mimeType || mimeType || "audio/webm";
      const extension = extensionForType(type);
      const blob = new Blob(recordedChunks, { type });
      const file = new File([blob], `recording-${Date.now()}.${extension}`, {
        type,
      });
      await prepareAudio(file, "Recording ready.");
    });

    mediaRecorder.start();
    root.classList.add("recording");
    recordLabel.textContent = "Stop";
    setStatus("Recording...");
    startTimer();
  } catch (error) {
    setStatus(error.message || "Microphone access was blocked.");
  }
}

function stopRecording() {
  if (mediaRecorder && mediaRecorder.state === "recording") {
    mediaRecorder.stop();
  }
}

settingsButton.addEventListener("click", () => {
  settingsPanel.classList.toggle("hidden");
});

saveApiKeyButton.addEventListener("click", saveApiKey);
apiKeyInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") saveApiKey();
});

chooseFolderButton.addEventListener("click", chooseSaveRoot);
openFolderButton.addEventListener("click", () => window.whisper.openSaveRoot());
saveEngineButton.addEventListener("click", saveTranscriptionSettings);
mlxModelInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") saveTranscriptionSettings();
});

installLocalEngineButton.addEventListener("click", async () => {
  setBusy(true);
  localEngineText.textContent = "Installing MLX locally...";
  setStatus("Installing Local MLX. This can take a few minutes.");
  try {
    renderLocalEngineStatus(await window.whisper.installLocalEngine());
    setStatus("Local MLX installed.");
  } catch (error) {
    setStatus(error.message);
    await refreshLocalEngineStatus();
  } finally {
    setBusy(false);
    setResultActions();
  }
});

removeLocalEngineButton.addEventListener("click", async () => {
  setBusy(true);
  setStatus("Removing Local MLX files...");
  try {
    renderLocalEngineStatus(await window.whisper.removeLocalEngine());
    setStatus("Local MLX files removed.");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
});

openLocalEngineButton.addEventListener("click", () => window.whisper.openLocalEngineFolder());

recordButton.addEventListener("click", () => {
  if (mediaRecorder && mediaRecorder.state === "recording") {
    stopRecording();
  } else {
    startRecording();
  }
});

chooseFileButton.addEventListener("click", () => fileInput.click());

fileInput.addEventListener("change", async () => {
  const file = fileInput.files[0];
  if (!file) return;
  fileName.textContent = file.name;
  await prepareAudio(file, "File ready.");
});

dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  dropZone.classList.add("dragging");
});

dropZone.addEventListener("dragleave", () => {
  dropZone.classList.remove("dragging");
});

dropZone.addEventListener("drop", async (event) => {
  event.preventDefault();
  dropZone.classList.remove("dragging");
  const file = event.dataTransfer.files[0];
  if (!file) return;
  fileName.textContent = file.name;
  await prepareAudio(file, "File ready.");
});

transcribeButton.addEventListener("click", transcribeAudio);

saveButton.addEventListener("click", async () => {
  if (!currentAudio && !transcript.value.trim()) return;
  const name = await askName("Save as", suggestedName(currentSourceName, "recording"));
  if (!name?.name) return;
  if (!name.saveAudio && !name.saveTranscript) {
    setStatus("Choose Audio, Transcript, or both.");
    return;
  }
  setBusy(true);
  try {
    const saved = [];
    if (name.saveAudio) {
      const audioResult = await window.whisper.saveAudio({
        audio: currentAudio,
        name: name.name,
      });
      saved.push("audio");
      lastSavedPath = audioResult.path;
    }
    if (name.saveTranscript) {
      const textResult = await window.whisper.saveTranscript({
        text: transcript.value,
        name: name.name,
      });
      saved.push("transcript");
      lastSavedPath = textResult.path;
    }
    setStatus(`Saved ${saved.join(" + ")}.`);
  } catch (error) {
    setStatus(error.message);
  } finally {
    setBusy(false);
    setResultActions();
  }
});

openSavedButton.addEventListener("click", async () => {
  if (!lastSavedPath) return;
  try {
    await window.whisper.revealPath(lastSavedPath);
  } catch (error) {
    setStatus(error.message);
  }
});

copyButton.addEventListener("click", async () => {
  try {
    await window.whisper.copyText(transcript.value);
    setStatus("Copied.");
  } catch (error) {
    setStatus(error.message);
  }
});

nameConfirmButton.addEventListener("click", () => {
  closeNameDialog({
    name: nameInput.value.trim(),
    saveAudio: saveAudioOption.checked && !saveAudioOption.disabled,
    saveTranscript: saveTranscriptOption.checked && !saveTranscriptOption.disabled,
  });
});

nameCancelButton.addEventListener("click", () => {
  closeNameDialog(null);
});

nameInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    closeNameDialog({
      name: nameInput.value.trim(),
      saveAudio: saveAudioOption.checked && !saveAudioOption.disabled,
      saveTranscript: saveTranscriptOption.checked && !saveTranscriptOption.disabled,
    });
  }
  if (event.key === "Escape") {
    closeNameDialog(null);
  }
});

nameDialog.addEventListener("click", (event) => {
  if (event.target === nameDialog) {
    closeNameDialog(null);
  }
});

loadSettings();
