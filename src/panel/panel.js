const body = document.body;
const previewText = document.querySelector("#previewText");
const previewFinal = document.querySelector("#previewFinal");
const previewVolatile = document.querySelector("#previewVolatile");
const timerText = document.querySelector("#timer");
const meterCanvas = document.querySelector("#meter");
const meterContext = meterCanvas.getContext("2d");
const stopButton = document.querySelector("#stopButton");
const cancelButton = document.querySelector("#cancelButton");
const shortcutHint = document.querySelector("#shortcutHint");
const errorText = document.querySelector("#errorText");

let mediaRecorder = null;
let recordedChunks = [];
let cancelled = false;
let wantsWav = false;
let previewOn = false;
let previewContext = null;
let startedAt = 0;
let timer = null;
let audioContext = null;
let analyser = null;
let meterFrame = null;
let hideTimer = null;

function setState(state) {
  body.dataset.state = state;
  window.verse.reportRecorderState(
    state === "recording" ? "recording" : state === "transcribing" ? "transcribing" : "idle"
  );
}

function recordingType() {
  // WebM/Opus: Electron's MediaRecorder advertises audio/mp4 but records
  // zero bytes with it. Engines that cannot read WebM get a WAV conversion.
  const candidates = ["audio/webm", "audio/mp4"];
  return candidates.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

// Decode the recording with Chromium's decoder and re-encode as 16 kHz mono
// WAV, for engines that cannot read WebM (Apple's Speech framework).
async function blobToWav(blob) {
  const decodeContext = new AudioContext();
  let decoded;
  try {
    decoded = await decodeContext.decodeAudioData(await blob.arrayBuffer());
  } finally {
    decodeContext.close().catch(() => {});
  }
  const rate = 16000;
  const offline = new OfflineAudioContext(1, Math.ceil(decoded.duration * rate), rate);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination);
  source.start();
  const rendered = await offline.startRendering();
  const samples = rendered.getChannelData(0);

  const wav = new DataView(new ArrayBuffer(44 + samples.length * 2));
  const writeString = (offset, text) => {
    for (let i = 0; i < text.length; i += 1) wav.setUint8(offset + i, text.charCodeAt(i));
  };
  writeString(0, "RIFF");
  wav.setUint32(4, 36 + samples.length * 2, true);
  writeString(8, "WAVE");
  writeString(12, "fmt ");
  wav.setUint32(16, 16, true);
  wav.setUint16(20, 1, true);
  wav.setUint16(22, 1, true);
  wav.setUint32(24, rate, true);
  wav.setUint32(28, rate * 2, true);
  wav.setUint16(32, 2, true);
  wav.setUint16(34, 16, true);
  writeString(36, "data");
  wav.setUint32(40, samples.length * 2, true);
  for (let i = 0, offset = 44; i < samples.length; i += 1, offset += 2) {
    const sample = Math.max(-1, Math.min(1, samples[i]));
    wav.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
  }
  return new Blob([wav.buffer], { type: "audio/wav" });
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
  timerText.textContent = "00:00";
  timer = window.setInterval(() => {
    timerText.textContent = formatTime(Date.now() - startedAt);
  }, 250);
}

function stopTimer() {
  window.clearInterval(timer);
  timer = null;
}

function startMeter(stream) {
  audioContext = new AudioContext();
  const source = audioContext.createMediaStreamSource(stream);
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 512;
  analyser.smoothingTimeConstant = 0.75;
  source.connect(analyser);

  const bins = new Uint8Array(analyser.frequencyBinCount);
  const barCount = 28;

  const draw = () => {
    analyser.getByteFrequencyData(bins);
    const { width, height } = meterCanvas;
    meterContext.clearRect(0, 0, width, height);
    const gap = 4;
    const barWidth = (width - gap * (barCount - 1)) / barCount;
    for (let index = 0; index < barCount; index += 1) {
      const bin = Math.floor((index / barCount) * bins.length * 0.7);
      const level = bins[bin] / 255;
      const barHeight = Math.max(4, level * height);
      const x = index * (barWidth + gap);
      const y = (height - barHeight) / 2;
      meterContext.fillStyle = `rgba(255, 255, 255, ${0.35 + level * 0.55})`;
      meterContext.beginPath();
      meterContext.roundRect(x, y, barWidth, barHeight, barWidth / 2);
      meterContext.fill();
    }
    meterFrame = window.requestAnimationFrame(draw);
  };
  meterFrame = window.requestAnimationFrame(draw);
}

// --- Live transcript preview: stream 16 kHz PCM to the main process --------

function startPreviewPump(stream) {
  previewFinal.textContent = "";
  previewVolatile.textContent = "";
  previewContext = new AudioContext({ sampleRate: 16000 });
  const source = previewContext.createMediaStreamSource(stream);
  const processor = previewContext.createScriptProcessor(4096, 1, 1);
  const mute = previewContext.createGain();
  mute.gain.value = 0;
  processor.onaudioprocess = (event) => {
    const samples = event.inputBuffer.getChannelData(0);
    const pcm = new Int16Array(samples.length);
    for (let i = 0; i < samples.length; i += 1) {
      const sample = Math.max(-1, Math.min(1, samples[i]));
      pcm[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
    }
    window.verse.sendPreviewAudio(pcm.buffer);
  };
  source.connect(processor);
  processor.connect(mute);
  mute.connect(previewContext.destination);
}

function stopPreviewPump() {
  if (previewContext) {
    previewContext.close().catch(() => {});
    previewContext = null;
  }
}

function appendPreview(kind, text) {
  if (!previewOn || !text) return;
  if (kind === "final") {
    const joiner = previewFinal.textContent && !/^\s/u.test(text) ? " " : "";
    previewFinal.textContent += joiner + text;
    previewVolatile.textContent = "";
  } else {
    const joiner = previewFinal.textContent && !/^\s/u.test(text) ? " " : "";
    previewVolatile.textContent = joiner + text;
  }
  previewText.scrollTop = previewText.scrollHeight;
}

window.verse.onPreviewText(({ kind, text }) => appendPreview(kind, text));

function stopMeter() {
  window.cancelAnimationFrame(meterFrame);
  meterFrame = null;
  if (audioContext) {
    audioContext.close().catch(() => {});
    audioContext = null;
    analyser = null;
  }
  meterContext.clearRect(0, 0, meterCanvas.width, meterCanvas.height);
}

function finishLater(delayMs) {
  window.clearTimeout(hideTimer);
  hideTimer = window.setTimeout(() => {
    setState("idle");
    window.verse.hidePanel();
  }, delayMs);
}

function showError(message) {
  errorText.textContent = message || "Something went wrong.";
  body.dataset.state = "error";
  window.verse.reportRecorderState("idle");
  finishLater(2600);
}

async function transcribe(file, durationMs) {
  setState("transcribing");
  try {
    const audio = {
      bytes: new Uint8Array(await file.arrayBuffer()),
      fileName: file.name,
      mimeType: file.type,
      durationMs,
    };
    await window.verse.completeRecording(audio);
    body.dataset.state = "done";
    window.verse.reportRecorderState("idle");
    finishLater(1100);
  } catch (error) {
    const message = String(error?.message || error).replace(
      /^Error invoking remote method '[^']+': (Error: )?/u,
      ""
    );
    showError(message);
  }
}

async function startRecording() {
  if (mediaRecorder && mediaRecorder.state === "recording") return;
  window.clearTimeout(hideTimer);
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mimeType = recordingType();
    const options = mimeType ? { mimeType } : undefined;
    recordedChunks = [];
    cancelled = false;
    mediaRecorder = new MediaRecorder(stream, options);

    mediaRecorder.addEventListener("dataavailable", (event) => {
      if (event.data.size > 0) recordedChunks.push(event.data);
    });

    mediaRecorder.addEventListener("stop", async () => {
      const durationMs = Date.now() - startedAt;
      stream.getTracks().forEach((track) => track.stop());
      stopTimer();
      stopMeter();
      stopPreviewPump();

      if (cancelled) {
        recordedChunks = [];
        setState("idle");
        window.verse.hidePanel();
        return;
      }

      const type = mediaRecorder.mimeType || mimeType || "audio/webm";
      let blob = new Blob(recordedChunks, { type });
      recordedChunks = [];
      let extension = extensionForType(type);
      if (wantsWav && !type.includes("wav")) {
        try {
          blob = await blobToWav(blob);
          extension = "wav";
        } catch {
          // Fall through with the original recording; the engine reports
          // a clearer error than a silent failure here would.
        }
      }
      const file = new File([blob], `recording-${Date.now()}.${extension}`, { type: blob.type });
      await transcribe(file, durationMs);
    });

    mediaRecorder.start();
    setState("recording");
    startTimer();
    startMeter(stream);
    if (previewOn) {
      try {
        startPreviewPump(stream);
      } catch {
        // Preview is best effort; recording continues without it.
      }
    }
  } catch (error) {
    showError(error?.message || "Microphone access was blocked.");
  }
}

function stopRecording() {
  if (mediaRecorder && mediaRecorder.state === "recording") {
    mediaRecorder.stop();
  }
}

function cancelRecording() {
  if (mediaRecorder && mediaRecorder.state === "recording") {
    cancelled = true;
    mediaRecorder.stop();
  }
}

function shortcutLabel(accelerator) {
  return String(accelerator || "")
    .replace("Control", "⌃")
    .replace("Alt", "⌥")
    .replace("Shift", "⇧")
    .replace("Command", "⌘")
    .replaceAll("+", "");
}

window.verse.onRecorderCommand(({ action, shortcut, wav, preview }) => {
  if (shortcut) shortcutHint.textContent = shortcutLabel(shortcut);
  if (action === "start") {
    wantsWav = Boolean(wav);
    previewOn = Boolean(preview);
    body.classList.toggle("preview-on", previewOn);
    startRecording();
  }
  if (action === "stop") stopRecording();
  if (action === "cancel") cancelRecording();
});

stopButton.addEventListener("click", stopRecording);
cancelButton.addEventListener("click", cancelRecording);

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") cancelRecording();
  if (event.key === "Enter" || event.key === " ") stopRecording();
});

window.verse
  .getSettings()
  .then((settings) => {
    shortcutHint.textContent = shortcutLabel(settings.shortcut);
  })
  .catch(() => {});
