const { app, BrowserWindow, clipboard, dialog, ipcMain, shell } = require("electron");
const fsSync = require("node:fs");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { spawn } = require("node:child_process");

const OPENAI_TRANSCRIPTION_URL = "https://api.openai.com/v1/audio/transcriptions";
const DEFAULT_MODEL = "whisper-1";
const DEFAULT_ENGINE = "openai";
const DEFAULT_MLX_MODEL = "mlx-community/whisper-large-v3-turbo";

const HISTORY_LIMIT = 200;

let mainWindow;

function settingsPath() {
  return path.join(app.getPath("userData"), "settings.json");
}

function historyPath() {
  return path.join(app.getPath("userData"), "history.json");
}

async function loadHistory() {
  try {
    const raw = await fs.readFile(historyPath(), "utf8");
    const entries = JSON.parse(raw);
    return Array.isArray(entries) ? entries : [];
  } catch {
    return [];
  }
}

async function saveHistory(entries) {
  await fs.mkdir(path.dirname(historyPath()), { recursive: true });
  await fs.writeFile(historyPath(), JSON.stringify(entries, null, 2) + "\n", "utf8");
}

async function addHistoryEntry({ text, source, engine }) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return null;
  const entry = {
    id: `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    text: trimmed,
    source: String(source || ""),
    engine: String(engine || ""),
    createdAt: new Date().toISOString(),
  };
  const entries = await loadHistory();
  entries.unshift(entry);
  await saveHistory(entries.slice(0, HISTORY_LIMIT));
  return entry;
}

function defaultSaveRoot() {
  return path.join(os.homedir(), "Documents", "Whisper");
}

async function loadSettings() {
  try {
    const raw = await fs.readFile(settingsPath(), "utf8");
    const settings = JSON.parse(raw);
    return {
      apiKey: settings.apiKey || "",
      saveRoot: settings.saveRoot || defaultSaveRoot(),
      engine: settings.engine || DEFAULT_ENGINE,
      mlxModel: settings.mlxModel || DEFAULT_MLX_MODEL,
    };
  } catch {
    return {
      apiKey: "",
      saveRoot: defaultSaveRoot(),
      engine: DEFAULT_ENGINE,
      mlxModel: DEFAULT_MLX_MODEL,
    };
  }
}

async function saveSettings(nextSettings) {
  const current = await loadSettings();
  const settings = { ...current, ...nextSettings };
  await fs.mkdir(path.dirname(settingsPath()), { recursive: true });
  await fs.writeFile(settingsPath(), JSON.stringify(settings, null, 2) + "\n", "utf8");
  return settings;
}

function safeStem(name, fallback) {
  const value = String(name || fallback || "recording").normalize("NFC");
  const cleaned = value.replace(/[/\\?%*:|"<>]/gu, "-");
  const parsed = path.parse(cleaned);
  const stem = (parsed.name || cleaned || fallback || "recording")
    .replace(/\s+/gu, " ")
    .replace(/^[.\s-]+|[.\s-]+$/gu, "");
  return stem || fallback || "recording";
}

function extensionForAudio(fileName, mimeType) {
  const ext = path.extname(fileName || "").toLowerCase();
  if (ext) return ext;
  if ((mimeType || "").includes("mp4")) return ".mp4";
  if ((mimeType || "").includes("mpeg")) return ".mp3";
  if ((mimeType || "").includes("wav")) return ".wav";
  if ((mimeType || "").includes("ogg")) return ".ogg";
  return ".webm";
}

async function uniquePath(directory, stem, extension) {
  await fs.mkdir(directory, { recursive: true });
  let candidate = path.join(directory, `${stem}${extension}`);
  let counter = 2;
  while (true) {
    try {
      await fs.access(candidate);
      candidate = path.join(directory, `${stem}-${counter}${extension}`);
      counter += 1;
    } catch {
      return candidate;
    }
  }
}

function audioBufferFromPayload(audio) {
  if (!audio || !audio.bytes) {
    throw new Error("No audio is ready.");
  }
  return Buffer.from(audio.bytes);
}

function tempAudioPath(fileName) {
  const extension = extensionForAudio(fileName, "");
  return path.join(
    app.getPath("temp"),
    `whisper-${Date.now()}-${Math.random().toString(16).slice(2)}${extension}`
  );
}

function appResourcePath(...parts) {
  return path.join(app.getAppPath(), ...parts);
}

function unpackedResourcePath(...parts) {
  if (!app.isPackaged) return appResourcePath(...parts);
  return path.join(process.resourcesPath, "app.asar.unpacked", ...parts);
}

function localMlxScriptPath() {
  return unpackedResourcePath("src", "local_mlx_transcribe.py");
}

function localEngineRoot() {
  return path.join(app.getPath("userData"), "local-mlx");
}

function localEngineVenvPath() {
  return path.join(localEngineRoot(), "venv");
}

function localEnginePythonPath() {
  return path.join(localEngineVenvPath(), "bin", "python3");
}

function localEngineEnv() {
  const root = localEngineRoot();
  return {
    ...process.env,
    PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || ""}`,
    HF_HOME: path.join(root, "huggingface"),
    HF_HUB_CACHE: path.join(root, "huggingface", "hub"),
    XDG_CACHE_HOME: path.join(root, "cache"),
  };
}

function pythonCandidates() {
  return [
    "/opt/homebrew/bin/python3",
    "/Library/Developer/CommandLineTools/usr/bin/python3",
    "/usr/bin/python3",
    "python3",
  ];
}

function runProcess(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      env: options.env || localEngineEnv(),
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout);
        return;
      }
      reject(new Error(stderr.trim() || `Command exited with ${code}.`));
    });
  });
}

async function findSystemPython() {
  let lastError = null;
  for (const candidate of pythonCandidates()) {
    try {
      await runProcess(candidate, ["--version"], { env: localEngineEnv() });
      return candidate;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("Could not find python3.");
}

function runPython(script, args) {
  return new Promise((resolve, reject) => {
    const pythonPath = localEnginePythonPath();
    if (!fsSync.existsSync(pythonPath)) {
      reject(new Error("Install Local MLX in Settings before using the local engine."));
      return;
    }

    const child = spawn(pythonPath, [script, ...args], {
      env: localEngineEnv(),
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout);
        return;
      }
      reject(new Error(stderr.trim() || `Python exited with ${code}.`));
    });
  });
}

async function localEngineStatus() {
  const pythonPath = localEnginePythonPath();
  const root = localEngineRoot();
  if (!fsSync.existsSync(pythonPath)) {
    return {
      installed: false,
      path: root,
      message: "Not installed",
    };
  }

  try {
    await runProcess(pythonPath, ["-c", "import mlx_whisper"], { env: localEngineEnv() });
    return {
      installed: true,
      path: root,
      message: "Installed",
    };
  } catch (error) {
    return {
      installed: false,
      path: root,
      message: error.message || "Install is incomplete",
    };
  }
}

async function installLocalEngine() {
  const root = localEngineRoot();
  const pythonPath = localEnginePythonPath();
  await fs.mkdir(root, { recursive: true });

  if (!fsSync.existsSync(pythonPath)) {
    const systemPython = await findSystemPython();
    await runProcess(systemPython, ["-m", "venv", localEngineVenvPath()], { env: localEngineEnv() });
  }

  await runProcess(pythonPath, ["-m", "pip", "install", "--upgrade", "pip"], { env: localEngineEnv() });
  await runProcess(pythonPath, ["-m", "pip", "install", "--upgrade", "mlx-whisper"], {
    env: localEngineEnv(),
  });
  return localEngineStatus();
}

async function removeLocalEngine() {
  const root = localEngineRoot();
  await fs.rm(root, { recursive: true, force: true });
  return localEngineStatus();
}

async function openLocalEngineFolder() {
  const root = localEngineRoot();
  await fs.mkdir(root, { recursive: true });
  await shell.openPath(root);
}

async function ensureLocalEngineReady() {
  const status = await localEngineStatus();
  if (!status.installed) {
    throw new Error("Install Local MLX in Settings before using the local engine.");
  }
  if (!fsSync.existsSync(localMlxScriptPath())) {
    throw new Error(`Local MLX helper is missing: ${localMlxScriptPath()}`);
  }
  return status;
}

function publicSettings(settings) {
  return {
    hasApiKey: Boolean(settings.apiKey),
    saveRoot: settings.saveRoot,
    engine: settings.engine,
    mlxModel: settings.mlxModel,
  };
}

async function transcribeWithMlx(audio, settings) {
  await ensureLocalEngineReady();
  const buffer = audioBufferFromPayload(audio);
  const audioPath = tempAudioPath(audio.fileName || "recording.webm");
  await fs.writeFile(audioPath, buffer);
  try {
    const output = await runPython(localMlxScriptPath(), [
      audioPath,
      "--model",
      settings.mlxModel || DEFAULT_MLX_MODEL,
    ]);
    const result = JSON.parse(output);
    if (result.error) throw new Error(result.error);
    if (typeof result.text !== "string") {
      throw new Error("MLX response did not include transcript text.");
    }
    return { text: result.text, usage: null };
  } finally {
    await fs.unlink(audioPath).catch(() => {});
  }
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1040,
    height: 780,
    minWidth: 760,
    minHeight: 620,
    title: "Whisper",
    backgroundColor: "#f7f7f5",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 22, y: 22 },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  await mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
}

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

ipcMain.handle("settings:get", async () => {
  const settings = await loadSettings();
  return publicSettings(settings);
});

ipcMain.handle("settings:saveApiKey", async (_event, apiKey) => {
  const key = String(apiKey || "").trim();
  if (!key) throw new Error("Enter an API key first.");
  const settings = await saveSettings({ apiKey: key });
  return publicSettings(settings);
});

ipcMain.handle("settings:saveTranscription", async (_event, payload) => {
  const engine = payload?.engine === "mlx" ? "mlx" : "openai";
  const mlxModel = String(payload?.mlxModel || DEFAULT_MLX_MODEL).trim() || DEFAULT_MLX_MODEL;
  const settings = await saveSettings({ engine, mlxModel });
  return publicSettings(settings);
});

ipcMain.handle("settings:chooseSaveRoot", async () => {
  const settings = await loadSettings();
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "Choose save folder",
    defaultPath: settings.saveRoot,
    properties: ["openDirectory", "createDirectory"],
  });
  if (result.canceled || !result.filePaths[0]) {
    return publicSettings(settings);
  }
  const next = await saveSettings({ saveRoot: result.filePaths[0] });
  return publicSettings(next);
});

ipcMain.handle("localEngine:status", async () => {
  return localEngineStatus();
});

ipcMain.handle("localEngine:install", async () => {
  return installLocalEngine();
});

ipcMain.handle("localEngine:remove", async () => {
  return removeLocalEngine();
});

ipcMain.handle("localEngine:open", async () => {
  await openLocalEngineFolder();
  return { ok: true };
});

ipcMain.handle("open:saveRoot", async () => {
  const settings = await loadSettings();
  await fs.mkdir(settings.saveRoot, { recursive: true });
  await shell.openPath(settings.saveRoot);
});

ipcMain.handle("open:revealPath", async (_event, filePath) => {
  const target = String(filePath || "");
  if (!target) throw new Error("There is no saved file to open.");
  shell.showItemInFolder(target);
  return { ok: true };
});

async function transcribeWithOpenAi(audio, settings) {
  if (!settings.apiKey) throw new Error("Save an OpenAI API key first.");

  const buffer = audioBufferFromPayload(audio);
  const blob = new Blob([buffer], {
    type: audio.mimeType || "application/octet-stream",
  });
  const form = new FormData();
  form.append("model", DEFAULT_MODEL);
  form.append("file", blob, audio.fileName || "recording.webm");

  const response = await fetch(OPENAI_TRANSCRIPTION_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${settings.apiKey}`,
    },
    body: form,
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(result.error?.message || `OpenAI returned HTTP ${response.status}.`);
  }
  if (typeof result.text !== "string") {
    throw new Error("OpenAI response did not include transcript text.");
  }
  return {
    text: result.text,
    usage: result.usage || null,
  };
}

ipcMain.handle("audio:transcribe", async (_event, audio) => {
  const settings = await loadSettings();
  const result =
    settings.engine === "mlx"
      ? await transcribeWithMlx(audio, settings)
      : await transcribeWithOpenAi(audio, settings);
  await addHistoryEntry({
    text: result.text,
    source: audio?.fileName || "recording",
    engine: settings.engine,
  }).catch(() => {});
  return result;
});

ipcMain.handle("history:list", async () => {
  return loadHistory();
});

ipcMain.handle("history:delete", async (_event, id) => {
  const entries = await loadHistory();
  const next = entries.filter((entry) => entry.id !== id);
  await saveHistory(next);
  return next;
});

ipcMain.handle("history:clear", async () => {
  await saveHistory([]);
  return [];
});

ipcMain.handle("audio:save", async (_event, { audio, name }) => {
  const settings = await loadSettings();
  const buffer = audioBufferFromPayload(audio);
  const directory = path.join(settings.saveRoot, "saved_audio");
  const extension = extensionForAudio(audio.fileName, audio.mimeType);
  const target = await uniquePath(directory, safeStem(name, "recording"), extension);
  await fs.writeFile(target, buffer);
  return { path: target };
});

ipcMain.handle("transcript:save", async (_event, { text, name }) => {
  const settings = await loadSettings();
  const transcript = String(text || "").trim();
  if (!transcript) throw new Error("There is no transcript to save.");

  const directory = path.join(settings.saveRoot, "saved_transcripts");
  const target = await uniquePath(directory, safeStem(name, "transcript"), ".txt");
  await fs.writeFile(target, transcript + "\n", "utf8");
  return { path: target };
});

ipcMain.handle("clipboard:writeText", async (_event, text) => {
  clipboard.writeText(String(text || ""));
  return { ok: true };
});
