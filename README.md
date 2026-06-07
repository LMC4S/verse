# Whisper Desktop

A macOS app for recording voice and transcribing it with Whisper, either through the OpenAI API or a local model. Both the audio and the transcript are saved to a folder you choose, so the recording stays available after you've used the text somewhere else.

## Download

A prebuilt `.dmg` for Apple Silicon is on the [Releases page](https://github.com/LMC4S/macOS-whisper/releases).

The app is not signed or notarized, so on first launch right-click the app and choose Open, or allow it under System Settings > Privacy & Security.

## Transcription engines

**OpenAI API** — requires an API key and internet. Files are sent to OpenAI's servers.

**Local MLX** — runs on your Mac, offline, no API key needed. Apple Silicon only. The app manages its own Python environment and pulls models from Hugging Face on first use.

Default model: `mlx-community/whisper-large-v3-turbo`. Any compatible model from [mlx-community](https://huggingface.co/mlx-community) works — swap it in Settings.

## Requirements

- macOS (Apple Silicon required for the local engine)
- Node.js 18+
- Python 3, Homebrew or system (local engine only)

## Run from source

```sh
npm install
npm start
```

## Build

```sh
npm run dist
```

## Setup

**OpenAI:** open Settings, paste your API key, select OpenAI as the engine.

**Local MLX:** open Settings, select Local MLX, click Install. The first transcription also downloads the model weights (1–3 GB depending on the model).

## Saved files

```
your-folder/
├── saved_audio/
└── saved_transcripts/
```

Settings are stored in Electron's user data directory.
