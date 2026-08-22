#!/usr/bin/env bash

# The snapping preference: where it is read from, in what order, and what it
# does when the environment and the saved file disagree. The panel passes its
# setting through the environment and the CLI writes a file, so the precedence
# between the two is the part that decides whether a toggle appears to do
# nothing — worth pinning down.
#
# XDG_STATE_HOME is redirected at a temporary directory, so this never reads or
# writes the preference of whoever is running it.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
readonly OMAVCAM=bin/omavcam

state=$(mktemp -d) || exit 1
trap 'rm -rf "$state"' EXIT
export XDG_STATE_HOME="$state"

fails=0

check() {
  local label="$1" want="$2" got="$3"

  if [[ $got == "$want" ]]; then
    printf '  pass  %s\n' "$label"
  else
    fails=$((fails + 1))
    printf '  FAIL  %s\n        got  %s\n        want %s\n' "$label" "$got" "$want"
  fi
}

snap() {
  "$OMAVCAM" preview snap "$@" 2>/dev/null
}

printf 'Snapping is on until it is turned off\n'

check "a fresh install snaps" on "$(snap status)"

snap status >/dev/null 2>&1
check "status succeeds while it is on" 0 "$?"

printf '\nThe preference is saved and read back\n'

check "turning it off reports off" off "$(snap off)"
check "and it stays off" off "$(snap status)"

snap status >/dev/null 2>&1
check "status fails while it is off" 1 "$?"

check "toggle turns it back on" on "$(snap toggle)"
check "toggle turns it off again" off "$(snap toggle)"
check "the file is what makes it stick" off "$(snap status)"

# The directory holds a preference and nothing else, but it is created the same
# way as the runtime state: ours, and only ours.
check "the state directory is private" 700 "$(stat -c '%a' "$state/omavcam")"

printf '\nThe environment wins, and says so\n'

# The panel passes its setting this way, so a value in the environment has to
# beat the file — otherwise the toggle in the panel would lose to whatever the
# terminal last wrote.
check "the environment overrides a saved off" on \
  "$(OMAVCAM_PREVIEW_SNAP=on snap status)"
check "the environment overrides a saved on" off \
  "$(snap on >/dev/null; OMAVCAM_PREVIEW_SNAP=off snap status)"

# Saving the opposite of what the environment says is allowed — it is the next
# run's preference — but silently doing nothing for this one would look broken.
warning=$(OMAVCAM_PREVIEW_SNAP=off "$OMAVCAM" preview snap on 2>&1 >/dev/null)
mentioned=no
[[ $warning == *OMAVCAM_PREVIEW_SNAP* ]] && mentioned=yes
check "a conflicting environment value is called out" yes "$mentioned"

printf '\nBad input is refused\n'

"$OMAVCAM" preview snap sideways >/dev/null 2>&1
check "an unknown state is rejected" 1 "$?"

printf '\n'
if ((fails == 0)); then
  printf 'All snapping preference checks passed.\n'
else
  printf '%s check(s) failed.\n' "$fails"
fi
exit $((fails > 0))
