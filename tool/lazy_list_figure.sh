#!/bin/sh
# Regenerates doc/lazy-list.png.
#
# Three steps. The Dart file measures and emits SVG, rsvg-convert rasterises
# it, and the last step quantises: the chart is flat colour, and a 64-entry
# palette measured 134,219 -> 43,186 bytes at the same resolution with no
# visible change.
set -eu
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null 2>&1 || {
  echo 'lazy_list_figure.sh needs librsvg (rsvg-convert) on PATH' >&2
  exit 1
}
command -v magick >/dev/null 2>&1 || {
  echo 'lazy_list_figure.sh needs ImageMagick 7 (magick) on PATH' >&2
  exit 1
}

flutter test tool/lazy_list_figure.dart
rsvg-convert -w 1600 doc/lazy-list.svg -o doc/lazy-list.png
magick doc/lazy-list.png -colors 64 -strip \
  -define png:compression-level=9 doc/lazy-list.png

ls -l doc/lazy-list.svg doc/lazy-list.png
