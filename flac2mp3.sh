#!/bin/bash

# Load .env file from current working directory if present
# Not from the script directory or alias location
if [ -f "$(pwd)/.env" ]; then
  set -a
  source "$(pwd)/.env"
  set +a
fi

# List of valid audio extensions
AUDIO_EXTENSIONS=(flac wav aif aiff alac ape ogg m4a wv tta aac opus)
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

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Display message with severity: 0=success, 1=warning, 2=error
# Usage: display_message <severity> <message>
display_message() {
  local severity=$1
  shift
  local msg="$*"
  case $severity in
    0)
      # Success (green)
      echo -e "${GREEN}[SUCCESS] $msg${NC}"
      ;;
    1)
      # Debug (default color)
      echo -e "[DEBUG] $msg"
      ;;
    2)
      # Warning (yellow)
      echo -e "${YELLOW}[WARNING] $msg${NC}"
      ;;
    3)
      # Error (red)
      echo -e "${RED}[ERROR] $msg${NC}"
      ;;
    *)
      echo "$msg"
      ;;
  esac
}

# Check argument
if [ -z "$input" ]; then
  display_message 3 "Usage: $0 [-e|--extension <extension>] <file or directory>"
  exit 1
fi

is_audio_file() {
  file="$1"
  ext="${file##*.}"
  # Convert extension to lowercase (compatible with bash 3)
  ext_lc=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
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
    display_message 3 "File $file does not exist."
    return
  fi

  dest="${file%.*}.mp3"
  if [ -f "$dest" ]; then
    display_message 2 "Destination file $dest already exists. Skipping."
    return
  fi

  if [ "$APP_ENV" = "DEV" ]; then
    echo -e "[DEV] Simulating conversion: touch $dest"
    touch "$dest"
    return
  fi

  # Generate unique log file name
  base_name="$(basename "$file")"
  timestamp="$(date +%Y%m%d_%H%M%S_%N)"
  log_file="$LOG_DIR/${base_name%.*}_$timestamp.log"

  # Start ffmpeg in background
  ffmpeg -nostdin -i "$file" -ab 320k -map_metadata 0 -id3v2_version 3 "$dest" > "$log_file" 2>&1 &
  ffmpeg_pid=$!

  # Loader spinner
  spinner='|/-\\'
  i=0
  # Print the message once, then animate only the spinner at the end
  printf "Converting %s to %s ... (log: %s) " "$file" "$dest" "$log_file"
  while kill -0 $ffmpeg_pid 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\b%s" "${spinner:$i:1}"
    sleep 0.2
  done
  wait $ffmpeg_pid
  printf "\b \r" # Clear spinner and return to start of line

  if [ $? -eq 0 ]; then
    display_message 0 "Conversion finished: $dest"
    rm -f "$log_file"
  else
    display_message 3 "Error converting $file. See log: $log_file"
  fi
}

# Remove log files older than 60 minutes
display_message 1 "Cleaning up old log files in $LOG_DIR ..."
find "$LOG_DIR" -type f -mmin +60 -delete

if [ -f "$input" ]; then
  # If it's a file
  if [ -n "$EXTENSION" ]; then
    # Extension provided, check match
    if [[ "$input" == *.${EXTENSION} ]]; then
      convert_flac "$input"
    else
      display_message 3 "Provided file does not match the extension .$EXTENSION."
      exit 1
    fi
  else
    # No extension provided, check if valid audio file
    if is_audio_file "$input"; then
      convert_flac "$input"
    else
      display_message 3 "Provided file does not have a valid audio extension."
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
    done < <(eval "find \"$input\" -type f \\( $find_expr \\) -print0")
  fi
  if [ ${#files[@]} -eq 0 ]; then
    display_message 3 "no music file found in the directory \"$input\""
    exit 1
  fi
  for file in "${files[@]}"; do
    convert_flac "$file"
  done
else
  display_message 3 "Argument is neither a valid file nor directory."
  exit 1
fi
