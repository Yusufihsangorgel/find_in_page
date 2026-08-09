#!/bin/sh
# Regenerates doc/searchable-grid.png.
#
# Two steps, because Flutter writes 32-bit RGBA and the figure is flat colour.
# Quantising to a 64-entry palette measured 134,782 -> 38,647 bytes at the same
# resolution, with no visible change. Resampling smaller was worse: it
# interpolates new colours and the file grows again.
set -eu
cd "$(dirname "$0")/.."

command -v magick >/dev/null 2>&1 || {
  echo 'searchable_grid.sh needs ImageMagick 7 (magick) on PATH' >&2
  exit 1
}

flutter test tool/searchable_grid.dart
magick doc/searchable-grid.png -colors 64 -strip \
  -define png:compression-level=9 doc/searchable-grid.png

ls -l doc/searchable-grid.png
