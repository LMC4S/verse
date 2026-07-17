#!/usr/bin/env python3
import argparse
import contextlib
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio")
    parser.add_argument("--model", default="mlx-community/whisper-large-v3-turbo")
    args = parser.parse_args()

    try:
        import mlx_whisper

        with contextlib.redirect_stdout(sys.stderr):
            result = mlx_whisper.transcribe(
                args.audio,
                path_or_hf_repo=args.model,
                verbose=False,
            )
        text = result.get("text", "") if isinstance(result, dict) else ""
        print(json.dumps({"text": text}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
