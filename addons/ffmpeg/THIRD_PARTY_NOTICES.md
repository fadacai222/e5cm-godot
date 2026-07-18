# Third-party notices

## EIRTeam.FFmpeg

- Version: 1.1.4 (autobuild 2025-11-12)
- Source: https://github.com/EIRTeam/EIRTeam.FFmpeg
- Release: https://github.com/EIRTeam/EIRTeam.FFmpeg/releases/tag/autobuild-2025-11-12-13-44
- License: MIT; see `LICENSE-EIRTEAM.txt`.

Only the Windows x86_64 runtime files are included in this project.

## FFmpeg shared libraries

The bundled FFmpeg libraries report `LGPL version 3 or later` at runtime and
were built as shared libraries. They identify themselves as
`N-111611-g5b11ee9429-20230724`; matching source and licensing information:

- https://ffmpeg.org/
- https://ffmpeg.org/legal.html
- https://github.com/FFmpeg/FFmpeg/tree/5b11ee9429
- `LICENSE-FFMPEG-LGPL-3.0.txt`
- `LICENSE-GPL-3.0.txt`

The enabled H.264 decoder may be subject to patent rules in some jurisdictions.
This build has network support disabled. It is intentionally used only for
trusted media bundled with this project; do not pass arbitrary untrusted video
files to this older FFmpeg build.
