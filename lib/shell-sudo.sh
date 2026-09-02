locate_privilege_escalation() {
  sudo_command=()
  if [[ $EUID -eq 0 ]]; then
    return
  fi

  local candidate
  for candidate in /run/wrappers/bin/sudo /usr/bin/sudo /bin/sudo; do
    if [[ -x $candidate && -u $candidate ]]; then
      sudo_command=("$candidate")
      return
    fi
  done

  return 1
}
