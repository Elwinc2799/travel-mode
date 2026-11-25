#!/bin/bash
# Renders the README screenshots and docs/flip.gif. Needs ffmpeg for the GIF.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf docs/frames
swift run -c release RenderPreview docs
ffmpeg -loglevel error -y -framerate 30 -i docs/frames/flip-%03d.png \
  -vf "scale=iw/2:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  docs/flip.gif
rm -rf docs/frames
echo "Rendered docs/*.png and docs/flip.gif"
