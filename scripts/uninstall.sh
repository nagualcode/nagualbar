#!/usr/bin/env bash
# omarchy:summary=Uninstall nagualbar and put the previous bar back
# omarchy:group=plugin
# omarchy:args=[--yes]
# omarchy:examples=./scripts/uninstall.sh

# Removes nagualbar, restores omarchy's indicator widget to the exact spot it
# came from, and hands the bar back.
#
# The bar itself is switched back by `omarchy plugin remove`, which sees the
# manifest's `omarchy.clonedFrom` and restores omarchy.bar. This script's job is
# everything that lives outside the plugin folder: the layout entry it took, and
# the `bar.nagualbar` key it added.

set -euo pipefail

# See install.sh: a piped-in script has no checkout beside it, so fetch one.
script_dir="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [[ -f "$script_dir/common.sh" ]]; then
  source "$script_dir/common.sh"
elif [[ -f "$script_dir/../scripts/common.sh" ]]; then
  source "$script_dir/../scripts/common.sh"
else
  bootstrap_url="https://github.com/nagualcode/nagualbar.git"
  command -v git >/dev/null 2>&1 || {
    echo "uninstall.sh needs git, or a nagualbar checkout to run from" >&2
    exit 1
  }
  bootstrap_dir="$(mktemp -d)"
  trap 'rm -rf "$bootstrap_dir"' EXIT
  git clone --depth 1 --quiet "$bootstrap_url" "$bootstrap_dir" \
    || { echo "could not clone $bootstrap_url" >&2; exit 1; }
  source "$bootstrap_dir/scripts/common.sh"
fi

ASSUME_YES=0
REMOVE_STATE=1

usage() {
  cat <<USAGE
Usage: uninstall.sh [--yes] [--keep-state]

  --yes         do not ask before removing
  --keep-state  leave $STATE_FILE in place
USAGE
}

while (( $# > 0 )); do
  case "$1" in
  --yes | -y) ASSUME_YES=1; shift ;;
  --keep-state) REMOVE_STATE=0; shift ;;
  -h | --help) usage; exit 0 ;;
  -*) fail "unknown option: $1" ;;
  *) fail "unexpected argument: $1" ;;
  esac
done

need jq "uninstall.sh needs jq"

PLUGIN_INSTALLED=0
[[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]] && PLUGIN_INSTALLED=1

if (( ! PLUGIN_INSTALLED )) && [[ ! -f "$INSTALL_STATE" ]]; then
  # Nothing to undo. Restoring the layout entry here would put
  # omarchy.indicators back into a layout that the user is running on their
  # own, and would duplicate it if they already had one.
  echo "$NAGUALBAR_ID does not appear to be installed; nothing to do."
  exit 0
fi

if (( PLUGIN_INSTALLED )); then
  if (( ASSUME_YES )); then
    omarchy plugin remove "$NAGUALBAR_ID" --yes
  else
    omarchy plugin remove "$NAGUALBAR_ID"
  fi
fi

# The bar is the built-in one again by this point, whether or not the plugin
# folder existed, so the layout surgery below is always safe to finish.

if [[ -f "$INSTALL_STATE" ]]; then
  RECORD="$(jq -c '.indicators // null' "$INSTALL_STATE")"
  SECTION="$(jq -r '.indicatorsSection // "center"' "$INSTALL_STATE")"
else
  # Installed by hand, or the state file was deleted. There is no recorded
  # position to restore, so put the widget back where omarchy ships it and say
  # so, rather than silently doing nothing.
  RECORD="null"
  SECTION="center"
  echo "note: no $INSTALL_STATE, restoring $NAGUALBAR_INDICATORS_ID to the $SECTION section"
fi

if [[ "$RECORD" == "null" ]]; then
  RESTORE_SECTION="$SECTION"
  RESTORE_INDEX=0
  RESTORE_ENTRY="$(jq -cn --arg id "$NAGUALBAR_INDICATORS_ID" '{ id: $id }')"
else
  RESTORE_SECTION="$(jq -r '.section // empty' <<<"$RECORD")"
  RESTORE_INDEX="$(jq -r '.index // 0' <<<"$RECORD")"
  RESTORE_ENTRY="$(jq -c '.entry' <<<"$RECORD")"
fi

restore_layout_entry "$NAGUALBAR_INDICATORS_ID" "$RESTORE_SECTION" "$RESTORE_INDEX" "$RESTORE_ENTRY"

rewrite_shell_config 'if (.bar | type) == "object" then del(.bar.nagualbar) else . end'

# `omarchy plugin remove` puts bar.id back to "omarchy.bar" explicitly, because
# the manifest says where this bar came from. That is the same bar the user had
# before, but it was reached through a *different* bar id — restore the exact
# one they had, including its absence, so an uninstall really is an undo.
PREVIOUS_BAR_ID=""
[[ -f "$INSTALL_STATE" ]] && PREVIOUS_BAR_ID="$(jq -r '.previousBarId // ""' "$INSTALL_STATE")"

rewrite_shell_config --arg previousBarId "$PREVIOUS_BAR_ID" '
  if (.bar | type) != "object" then .
  elif $previousBarId == "" or $previousBarId == "nagualbar" then del(.bar.id)
  elif ($previousBarId | test(".*")) then .bar.id = $previousBarId
  else del(.bar.id)
  end
'


rm -f "$INSTALL_STATE"

if (( REMOVE_STATE )) && [[ -f "$STATE_FILE" ]]; then
  # Not deleted outright: the hidden set is a list of ids the user assembled by
  # hand, and reinstalling should not throw it away without a way back.
  mv -f "$STATE_FILE" "$STATE_FILE.bak"
  echo "Kept your hidden-icon list at $STATE_FILE.bak"
fi

echo
echo "Done. The bar is omarchy's again."
echo "A copy of the shell.json from before the install is at $SHELL_CONFIG_BACKUP"
