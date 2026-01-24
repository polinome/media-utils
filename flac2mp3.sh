#!/bin/bash

# Load .env file if present in the script directory
__DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$__DIR__/.env" ]; then
  set -a
  source "$__DIR__/.env"
  set +a
fi

# List of valid audio extensions
AUDIO_EXTENSIONS=(flac wav aif aiff alac ape ogg m4a wv tta)
EXTENSION=""

# Set log directory from .env or use default
LOG_DIR="${LOG_DIR:-/var/log/flac2mp3}"
mkdir -p "$LOG_DIR"

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--extension)
      EXTENSION="$2"
      shift 2
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done

# Check argument
if [ -z "$input" ]; then
  echo "Usage: $0 [-e|--extension <extension>] <file or directory>"
  exit 1
fi

is_audio_file() {
  file="$1"
  ext="${file##*.}"
  ext_lc="${ext,,}"
  for valid in "${AUDIO_EXTENSIONS[@]}"; do
    if [[ "$ext_lc" == "$valid" ]]; then
      return 0
    fi
  done
  return 1
}

convert_flac() {
  file="$1"

  # Check if file exists
  if [ ! -f "$file" ]; then
    echo "File $file does not exist."
    return
  fi

  dest="${file%.*}.mp3"
  if [ -f "$dest" ]; then
    echo "Destination file $dest already exists. Skipping."
    return
  fi

  if [ "$APP_ENV" = "DEV" ]; then
    echo "[DEV] Simulating conversion: touch $dest"
    touch "$dest"
    return
  fi

  # Generate unique log file name
  base_name="$(basename "$file")"
  timestamp="$(date +%Y%m%d_%H%M%S_%N)"
  log_file="$LOG_DIR/${base_name%.*}_$timestamp.log"

  echo "Converting $file to $dest ... (log: $log_file)"
  ffmpeg -nostdin -i "$file" -ab 320k -map_metadata 0 -id3v2_version 3 "$dest" > "$log_file" 2>&1

  if [ $? -eq 0 ]; then
    echo "Conversion finished: $dest"
    rm -f "$log_file"
  else
    echo "Error converting $file. See log: $log_file"
  fi
}

if [ -f "$input" ]; then
  # If it's a file
  if [ -n "$EXTENSION" ]; then
    # Extension provided, check match
    if [[ "$input" == *.${EXTENSION} ]]; then
      convert_flac "$input"
    else
      echo "Provided file does not match the extension .$EXTENSION."
      exit 1
    fi
  else
    # No extension provided, check if valid audio file
    if is_audio_file "$input"; then
      convert_flac "$input"
    else
      echo "Provided file does not have a valid audio extension."
      exit 1
    fi
  fi
elif [ -d "$input" ]; then
  # If it's a directory, recursive search
  files=()
  if [ -n "$EXTENSION" ]; then
    # Extension provided
    while IFS= read -r -d '' file; do
      files+=("$file")
    done < <(find "$input" -type f -name "*.${EXTENSION}" -print0)
  else
    # No extension provided, search for all valid audio files
    find_expr=$(printf -- '-iname "*.%s" -o ' "${AUDIO_EXTENSIONS[@]}")
    find_expr="${find_expr%-o }" # Remove trailing -o
    while IFS= read -r -d '' file; do
      files+=("$file")
    done < <(eval "find \"$input\" -type f ( $find_expr ) -print0")
  fi
  if [ ${#files[@]} -eq 0 ]; then
    echo "no music file found in the directory \"$input\""
    exit 1
  fi
  for file in "${files[@]}"; do
    convert_flac "$file"
  done
else
  echo "Argument is neither a valid file nor directory."
  exit 1
fi
