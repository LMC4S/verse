# Whisper Desktop

A macOS desktop app for recording or uploading audio and transcribing it with OpenAI's speech-to-text API.

## Requirements

- Node.js
- An OpenAI API key

## Run

```sh
npm install
npm start
```

## Build

```sh
npm run dist
```

## Usage

1. Open the app and enter your OpenAI API key in Settings.
2. Record audio directly or drop/upload an audio file.
3. Hit **Transcribe** — the transcript appears instantly.

Saved files go under the folder you select in Settings:

```
selected-folder/saved_audio/
selected-folder/saved_transcripts/
```

Settings are stored in Electron's app data folder (not in the project directory).
