from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import av
from PIL import Image


def extract_frame(video_path: Path, seconds: float, frame_path: Path, metadata_path: Path) -> dict:
    with av.open(str(video_path)) as container:
        stream = next(item for item in container.streams if item.type == "video")
        if seconds > 0.0 and stream.time_base:
            container.seek(
                max(0, int(seconds / float(stream.time_base))),
                stream=stream,
                any_frame=False,
                backward=True,
            )
        selected = None
        for index, frame in enumerate(container.decode(stream)):
            selected = frame
            if float(frame.time or 0.0) >= seconds or index >= 600:
                break
        if selected is None:
            raise RuntimeError("video contains no decodable frame")
        array = selected.to_ndarray(format="rgb24")
        frame_time = float(selected.time or 0.0)

    frame_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(array, mode="RGB").save(frame_path)
    metadata = {
        "fixtureId": "parity-v1",
        "frameFile": frame_path.name,
        "godotSourcePath": "assets/video/player_select/003.mp4",
        "originalSourcePath": "backmovies/003.mp4",
        "sourceSha256": hashlib.sha256(video_path.read_bytes()).hexdigest(),
        "timeSeconds": float(seconds),
        "decodedFrameTimeSeconds": frame_time,
        "frameSize": [int(selected.width), int(selected.height)],
        "pixelFormat": "RGB24",
        "scaling": "source-frame-only",
    }
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract a deterministic shared video-frame fixture")
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--frame", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    args = parser.parse_args()
    print(
        json.dumps(
            extract_frame(args.video, args.seconds, args.frame, args.metadata),
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
