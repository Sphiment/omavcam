#!/usr/bin/env bash

# OMAVCAM_VIDEO_NR is interpolated into /etc/modprobe.d/omavcam.conf, which is
# written as root and parsed by modprobe with privileges. A value carrying a
# newline could append directives of its own across that boundary, so the script
# refuses anything but a bare decimal before the file is ever written.
#
# --help is used as the probe: the check runs at load, before any subcommand, so
# no phone, module, or privilege is needed to exercise it.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
readonly OMAVCAM=bin/omavcam

fails=0

check() {
  local label="$1" want="$2" value="${3-}"
  local got

  if [[ $# -ge 3 ]]; then
    if OMAVCAM_VIDEO_NR="$value" "$OMAVCAM" --help >/dev/null 2>&1; then
      got=accepted
    else
      got=rejected
    fi
  elif "$OMAVCAM" --help >/dev/null 2>&1; then
    got=accepted
  else
    got=rejected
  fi

  if [[ $got == "$want" ]]; then
    printf '  pass  %s\n' "$label"
  else
    fails=$((fails + 1))
    printf '  FAIL  %s  got=%s want=%s\n' "$label" "$got" "$want"
  fi
}

check "unset falls back to 42"      accepted
check "empty falls back to 42"      accepted ""
check "lowest node"                 accepted 0
check "default"                     accepted 42
check "highest node"                accepted 255

check "past the last video minor"   rejected 256
check "leading zero is not octal"   rejected 042
check "negative"                    rejected -1
check "not a number"                rejected abc
check "trailing junk"               rejected "42 foo"
check "quote"                       rejected '42"'
check "command substitution"        rejected '$(id -u)'
check "newline injects a directive" rejected "$(printf '42\noptions v4l2loopback evil=1')"

if ((fails > 0)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
