#!/bin/bash

set -u

usage() {
  echo "Usage: $(basename "$0") [-f|--force] [-o output_path] <video_path> <angle>"
  echo "Examples:"
  echo "  $(basename "$0") /path/to/video.mp4 90"
  echo "  $(basename "$0") -o /tmp/output.mp4 /path/to/video.mp4 -90"
  echo "  $(basename "$0") --force -o /tmp/output.mp4 /path/to/video.mp4 180"
}

output_video=""
force_overwrite=0
positionals=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "Error: missing value for $1"
        usage
        exit 1
      fi
      output_video="$2"
      shift 2
      ;;
    -f|--force)
      force_overwrite=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        positionals+=("$1")
        shift
      done
      ;;
    -*)
      echo "Error: unknown option: $1"
      usage
      exit 1
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [ "${#positionals[@]}" -ne 2 ]; then
  usage
  exit 1
fi

input_video="${positionals[0]}"
angle="${positionals[1]}"

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
    video_filter="rotate=${angle}*PI/180:ow=rotw(${angle}*PI/180):oh=roth(${angle}*PI/180):c=black,pad=ceil(iw/2)*2:ceil(ih/2)*2"
    ;;
esac

input_dir="$(dirname "$input_video")"
input_file="$(basename "$input_video")"
input_name="${input_file%.*}"
input_ext="${input_file##*.}"
safe_angle="$(printf '%s' "$angle" | sed 's/+//g; s/-/neg/g; s/\./_/g')"


if [ -z "$output_video" ]; then
  output_video="${input_dir}/${input_name}_rotated_${safe_angle}.${input_ext}"
fi

output_dir="$(dirname "$output_video")"

if [ ! -d "$output_dir" ]; then
  echo "Error: output directory does not exist: $output_dir"
  exit 1
fi

if [ ! -w "$output_dir" ]; then
  echo "Error: output directory is not writable: $output_dir"
  exit 1
fi

if [ "$input_video" = "$output_video" ]; then
  echo "Error: input and output paths must be different."
  exit 1
fi

if [ -e "$output_video" ] && [ "$force_overwrite" -ne 1 ]; then
  echo "Error: output file already exists: $output_video"
  echo "Hint: use --force to overwrite it."
  exit 1
fi

ffmpeg_overwrite_flag="-n"
if [ "$force_overwrite" -eq 1 ]; then
  ffmpeg_overwrite_flag="-y"
fi

echo "Rotating: $input_video"
echo "Angle: $angle"
echo "Output: $output_video"

if ffmpeg -hide_banner -loglevel error -nostdin "$ffmpeg_overwrite_flag" -i "$input_video" -vf "$video_filter" -c:a copy "$output_video"; then
  echo "Done: $output_video"
  exit 0
fi

echo "Error: ffmpeg conversion failed."
exit 1
