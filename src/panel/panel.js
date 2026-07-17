const body = document.body;
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

      if (cancelled) {
        recordedChunks = [];
        setState("idle");
        window.verse.hidePanel();
        return;
      }

      const type = mediaRecorder.mimeType || mimeType || "audio/webm";
      const extension = extensionForType(type);
      const blob = new Blob(recordedChunks, { type });
      recordedChunks = [];
      const file = new File([blob], `recording-${Date.now()}.${extension}`, { type });
      await transcribe(file, durationMs);
    });

    mediaRecorder.start();
    setState("recording");
    startTimer();
    startMeter(stream);
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

window.verse.onRecorderCommand(({ action, shortcut }) => {
  if (shortcut) shortcutHint.textContent = shortcutLabel(shortcut);
  if (action === "start") startRecording();
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
