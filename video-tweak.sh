#!/bin/bash

set -u

usage() {
  echo "Usage: $(basename "$0") <action> [action arguments]"
  echo "Actions:"
  echo "  rotate     -> delegates to rotate-video.sh"
  echo "  reverse    -> delegates to reverse-video.sh"
  echo "  trim-black -> delegates to trim-black-video.sh"
  echo "Examples:"
  echo "  $(basename "$0") rotate /path/to/video.mp4 90"
  echo "  $(basename "$0") reverse /path/to/video.mp4"
  echo "  $(basename "$0") trim-black /path/to/video.mp4"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
esac

action="$1"
shift

supported_actions=("rotate" "reverse" "trim-black")

# Resolve actions by exact match first, then by unique prefix.
resolved_action=""
for candidate in "${supported_actions[@]}"; do
  if [ "$action" = "$candidate" ]; then
    resolved_action="$candidate"
    break
  fi
done

if [ -z "$resolved_action" ]; then
  matches=()
  for candidate in "${supported_actions[@]}"; do
    case "$candidate" in
      "$action"*) matches+=("$candidate") ;;
    esac
  done

  if [ "${#matches[@]}" -eq 1 ]; then
    resolved_action="${matches[0]}"
  elif [ "${#matches[@]}" -gt 1 ]; then
    echo "Error: ambiguous action '$action' (matches: ${matches[*]})."
    echo "Hint: provide more letters."
    usage
    exit 1
  else
    echo "Error: unknown action: $action"
    usage
    exit 1
  fi
fi

# Resolve the real script location to support invocation through symlinks.
source_path="${BASH_SOURCE[0]}"
while [ -L "$source_path" ]; do
  source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
  source_path="$(readlink "$source_path")"
  case "$source_path" in
    /*) ;;
    *) source_path="${source_dir}/${source_path}" ;;
  esac
done
script_dir="$(cd -P "$(dirname "$source_path")" && pwd)"

target_script=""
case "$resolved_action" in
  rotate)
    target_script="${script_dir}/video/rotate-video.sh"
    ;;
  reverse)
    target_script="${script_dir}/video/reverse-video.sh"
    ;;
  trim-black)
    target_script="${script_dir}/video/trim-black-video.sh"
    ;;
  *)
    echo "Error: unknown action: $resolved_action"
    usage
    exit 1
    ;;
esac

if [ ! -f "$target_script" ]; then
  echo "Error: target script not found: $target_script"
  exit 1
fi

# Run with bash to avoid hard dependency on executable permission bits.
exec bash "$target_script" "$@"
