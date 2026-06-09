#!/bin/bash

set -u

usage() {
  echo "Usage: $(basename "$0") <video_path> <angle>"
  echo "Example: $(basename "$0") /path/to/video.mp4 90"
}

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

input_video="$1"
angle="$2"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg is not installed or not in PATH."
  exit 1
fi

if [ ! -f "$input_video" ]; then
  echo "Error: file not found: $input_video"
  exit 1
fi

if [ ! -r "$input_video" ]; then
  echo "Error: file is not readable: $input_video"
  exit 1
fi

if ! printf '%s' "$angle" | grep -Eq '^[+-]?[0-9]+([.][0-9]+)?$'; then
  echo "Error: angle must be numeric (examples: 90, -90, 180, 22.5)."
  exit 1
fi

normalize_angle() {
  awk -v a="$1" 'BEGIN {
    n = a % 360;
    if (n < 0) n += 360;
    if (n == int(n)) printf "%d", n;
    else printf "%.6f", n;
  }'
}

normalized_angle="$(normalize_angle "$angle")"

# Use transpose for right-angle rotations and rotate for arbitrary angles.
case "$normalized_angle" in
  90)
    video_filter="transpose=1"
    ;;
  180)
    video_filter="hflip,vflip"
    ;;
  270)
    video_filter="transpose=2"
    ;;
  *)
    video_filter="rotate=${angle}*PI/180:ow=rotw(${angle}*PI/180):oh=roth(${angle}*PI/180):c=black"
    ;;
esac

input_dir="$(dirname "$input_video")"
input_file="$(basename "$input_video")"
input_name="${input_file%.*}"
input_ext="${input_file##*.}"
safe_angle="$(printf '%s' "$angle" | sed 's/+//g; s/-/neg/g; s/\./_/g')"

output_video="${input_dir}/${input_name}_rotated_${safe_angle}.${input_ext}"

if [ -e "$output_video" ]; then
  echo "Error: output file already exists: $output_video"
  exit 1
fi

echo "Rotating: $input_video"
echo "Angle: $angle"
echo "Output: $output_video"

if ffmpeg -hide_banner -loglevel error -nostdin -i "$input_video" -vf "$video_filter" -c:a copy "$output_video"; then
  echo "Done: $output_video"
  exit 0
fi

echo "Error: ffmpeg conversion failed."
exit 1
