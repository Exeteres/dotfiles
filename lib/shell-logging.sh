_log_color_enabled() {
  [[ -z ${NO_COLOR:-} && -t $1 ]]
}

log_info() {
  if _log_color_enabled 1; then
    printf '\033[36m[>]\033[0m %s\n' "$1"
  else
    printf '[>] %s\n' "$1"
  fi
}

log_success() {
  if _log_color_enabled 1; then
    printf '\033[32m[✓]\033[0m %s\n' "$1"
  else
    printf '[✓] %s\n' "$1"
  fi
}

log_warning() {
  if _log_color_enabled 1; then
    printf '\033[33m[~]\033[0m %s\n' "$1"
  else
    printf '[~] %s\n' "$1"
  fi
}

log_error() {
  if _log_color_enabled 2; then
    printf '\033[31m[!]\033[0m %s\n' "$1" >&2
  else
    printf '[!] %s\n' "$1" >&2
  fi
}

bold() {
  if _log_color_enabled 1; then
    printf '\033[1m%s\033[0m' "$1"
  else
    printf '%s' "$1"
  fi
}
