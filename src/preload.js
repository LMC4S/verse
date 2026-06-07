const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("whisper", {
  getSettings: () => ipcRenderer.invoke("settings:get"),
  saveApiKey: (apiKey) => ipcRenderer.invoke("settings:saveApiKey", apiKey),
  saveTranscriptionSettings: (payload) => ipcRenderer.invoke("settings:saveTranscription", payload),
  chooseSaveRoot: () => ipcRenderer.invoke("settings:chooseSaveRoot"),
  openSaveRoot: () => ipcRenderer.invoke("open:saveRoot"),
  revealPath: (filePath) => ipcRenderer.invoke("open:revealPath", filePath),
  getLocalEngineStatus: () => ipcRenderer.invoke("localEngine:status"),
  installLocalEngine: () => ipcRenderer.invoke("localEngine:install"),
  removeLocalEngine: () => ipcRenderer.invoke("localEngine:remove"),
  openLocalEngineFolder: () => ipcRenderer.invoke("localEngine:open"),
  transcribeAudio: (audio) => ipcRenderer.invoke("audio:transcribe", audio),
  saveAudio: (payload) => ipcRenderer.invoke("audio:save", payload),
  saveTranscript: (payload) => ipcRenderer.invoke("transcript:save", payload),
  copyText: (text) => ipcRenderer.invoke("clipboard:writeText", text),
});
