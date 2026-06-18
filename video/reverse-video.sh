#!/bin/bash

set -u

usage() {
  echo "Usage: $(basename "$0") [-f|--force] [-o output_path] <video_path>"
  echo "Examples:"
  echo "  $(basename "$0") /path/to/video.mp4"
  echo "  $(basename "$0") -o /tmp/output.mp4 /path/to/video.mp4"
  echo "  $(basename "$0") --force -o /tmp/output.mp4 /path/to/video.mp4"
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

if [ "${#positionals[@]}" -ne 1 ]; then
  usage
  exit 1
fi

input_video="${positionals[0]}"

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

input_dir="$(dirname "$input_video")"
input_file="$(basename "$input_video")"
input_name="${input_file%.*}"
input_ext="${input_file##*.}"

if [ -z "$output_video" ]; then
  output_video="${input_dir}/${input_name}_reversed.${input_ext}"
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

has_audio=0
if command -v ffprobe >/dev/null 2>&1; then
  if ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$input_video" >/dev/null 2>&1; then
    has_audio=1
  fi
fi

echo "Reversing: $input_video"
echo "Output: $output_video"

if [ "$has_audio" -eq 1 ]; then
  if ffmpeg -hide_banner -loglevel error -nostdin "$ffmpeg_overwrite_flag" -i "$input_video" -vf reverse -af areverse "$output_video"; then
    echo "Done: $output_video"
    exit 0
  fi
else
  if ffmpeg -hide_banner -loglevel error -nostdin "$ffmpeg_overwrite_flag" -i "$input_video" -vf reverse -c:a copy "$output_video"; then
    echo "Done: $output_video"
    exit 0
  fi
fi

echo "Error: ffmpeg conversion failed."
exit 1

