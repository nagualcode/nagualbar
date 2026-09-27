#!/usr/bin/env bash
# omarchy:summary=Install nagualbar and make it the active bar
# omarchy:group=plugin
# omarchy:args=[source] [--force]
# omarchy:examples=./scripts/install.sh
# omarchy:examples=./scripts/install.sh https://github.com/nagualcode/nagualbar.git

# Installs nagualbar, moves omarchy's own indicator widget out of the layout,
# and switches the shell over to it.
#
# Re-running is safe. An already-installed plugin is left in place, and only the
# configuration steps are repeated, so this doubles as "repair my install".

set -euo pipefail

# Sourced from a checkout next to this script. When the script is piped in
# (`curl … | bash`) there is no such directory, so fetch the repository first and
# use that checkout for the rest of the run — which is where the plugin is
# installed from anyway.
script_dir="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [[ -f "$script_dir/common.sh" ]]; then
  source "$script_dir/common.sh"
elif [[ -f "$script_dir/../scripts/common.sh" ]]; then
  source "$script_dir/../scripts/common.sh"
else
  # Duplicated from common.sh on purpose: that file is what we are about to
  # source, so the URL has to be known before it exists.
  bootstrap_url="https://github.com/nagualcode/nagualbar.git"
  command -v git >/dev/null 2>&1 || {
    echo "install.sh needs git, or a nagualbar checkout to run from" >&2
    exit 1
  }
  bootstrap_dir="$(mktemp -d)"
  trap 'rm -rf "$bootstrap_dir"' EXIT
  echo "Fetching nagualbar into a temporary checkout"
  git clone --depth 1 --quiet "$bootstrap_url" "$bootstrap_dir" \
    || { echo "could not clone $bootstrap_url" >&2; exit 1; }
  source "$bootstrap_dir/scripts/common.sh"
fi

SOURCE="$NAGUALBAR_REPO"
SOURCE_SET=0
FORCE=0
ASSUME_SHELL=1

usage() {
  cat <<USAGE
Usage: install.sh [source] [--force]

  source   a git URL, or a path to a nagualbar checkout to install from
           (defaults to $NAGUALBAR_REPO)

  --force  overwrite an installed nagualbar when installing from a local path

Only shell.json is edited. The hidden-icon state in $STATE_FILE is
yours: install leaves it alone, and so does uninstall.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
  --force | -f) FORCE=1; shift ;;
  -h | --help) usage; exit 0 ;;
  -*) fail "unknown option: $1" ;;
  *)
    (( ! SOURCE_SET )) || fail "unexpected argument: $1"
    SOURCE_SET=1
    SOURCE="$1"
    shift
    ;;
  esac
done

need jq "install.sh needs jq"

if ! shell_is_running; then
  ASSUME_SHELL=0
  echo "note: omarchy-shell is not responding; installing files only."
  echo "      Start the shell, then run: omarchy-shell shell enablePlugin $NAGUALBAR_ID '{}'"
fi

# --- 1. put the plugin on disk ---------------------------------------------

if [[ -d "$SOURCE" ]]; then
  LOCAL_SOURCE="$(readlink -f "$SOURCE")"
  if [[ "$LOCAL_SOURCE" == "$(readlink -f "$PLUGIN_DIR" 2>/dev/null || true)" ]]; then
    echo "Already installed from $LOCAL_SOURCE"
  elif [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
    if (( FORCE )); then
      need rsync "install.sh needs rsync to overwrite an installed copy"
      echo "Updating $PLUGIN_DIR from $LOCAL_SOURCE"
      copy_plugin_tree "$LOCAL_SOURCE" "$PLUGIN_DIR"
      omarchy-plugin-validate "$PLUGIN_DIR" || fail "the copy at $PLUGIN_DIR does not validate"
    else
      # Not an error: re-running install is how you repair a broken install, and
      # the configuration steps below are the part worth repeating.
      echo "$NAGUALBAR_ID is already installed at $PLUGIN_DIR; leaving it alone (--force to overwrite)"
    fi
  else
    need rsync "install.sh needs rsync to install from a local path"
    echo "Installing from $LOCAL_SOURCE"
    copy_plugin_tree "$LOCAL_SOURCE" "$PLUGIN_DIR"
    omarchy-plugin-validate "$PLUGIN_DIR" || fail "the copy at $PLUGIN_DIR does not validate"
  fi
else
  if [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
    echo "Already installed at $PLUGIN_DIR (leaving it alone)"
  else
    need git "install.sh needs git to clone $SOURCE"
    echo "Installing from $SOURCE"
    omarchy plugin add "$SOURCE" --yes
  fi
fi

if (( ! ASSUME_SHELL )); then
  echo
  echo "Installed the files. Nothing else was changed."
  exit 0
fi

# The registry rescans asynchronously, and a freshly copied plugin folder is
# not in it yet. Enabling before the rescan lands fails with "unknown plugin",
# and nothing retries it — so wait for the plugin to actually show up.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
DISCOVERED=0
for _ in $(seq 1 60); do
  if omarchy-shell shell listPlugins 2>/dev/null \
    | jq -e --arg id "$NAGUALBAR_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
    DISCOVERED=1
    break
  fi
  sleep 0.1
done
if (( ! DISCOVERED )); then
  fail "the shell has not picked up $NAGUALBAR_ID yet; run: omarchy-shell shell rescanPlugins"
fi

# --- 2. record what we are about to change ----------------------------------

PREVIOUS_BAR_ID="$(jq -r '.bar.id // empty' "$SHELL_CONFIG")"
FOUND="$(find_layout_entry "$NAGUALBAR_INDICATORS_ID")"
SECTION="$(resolve_indicator_section)"

# Only write the undo record when there is not a good one already. A second
# install runs with `omarchy.indicators` already gone and `bar.id` already set to
# nagualbar, so writing again would record the *nagualbar* id as the previous
# bar and no indicator position at all — quietly destroying the only thing that
# knows where to put things back.
if [[ -f "$INSTALL_STATE" ]] && jq -e '.version == 1' "$INSTALL_STATE" >/dev/null 2>&1; then
  echo "Keeping the existing undo record at $INSTALL_STATE"
else
  write_json_file "$INSTALL_STATE" "$(jq -cn \
    --arg previousBarId "$PREVIOUS_BAR_ID" \
    --argjson indicators "$FOUND" \
    --arg section "$SECTION" \
    '{ version: 1, previousBarId: $previousBarId, indicators: $indicators, indicatorsSection: $section }')"
fi

# --- 3. take omarchy's indicator widget out of the layout -------------------
#
# nagualbar hosts those six icons itself, and it does it as a row that is not a
# layout entry. Leaving `omarchy.indicators` in place would show all six twice.

if [[ "$FOUND" != "null" ]]; then
  remove_layout_entry "$NAGUALBAR_INDICATORS_ID" >/dev/null
  echo "Removed $NAGUALBAR_INDICATORS_ID from the bar layout"
fi

rewrite_shell_config --arg section "$SECTION" '
  .bar = (.bar // {})
  | .bar.nagualbar = ((.bar.nagualbar // {}) + { indicators: $section })
'

# --- 4. switch the bar over --------------------------------------------------
#
# Last, and through the shell rather than by hand, so the shell owns the final
# write of its own config and the bar swaps in one step with the layout already
# in its new shape.

if ! omarchy-shell shell enablePlugin "$NAGUALBAR_ID" '{}' >/dev/null; then
  fail "the shell refused to switch bars; run: omarchy-shell shell enablePlugin $NAGUALBAR_ID '{}'"
fi

cat <<DONE

Nagualbar is now the bar.

  Right-click empty bar space   open the contents menu
  Arrow keys / Tab              move between icons
  Enter or Space                hide or show the highlighted icon
  A                             show every icon again
  Escape                        close

The indicator row is in the $SECTION section. Change it in shell.json:

  "bar": { "nagualbar": { "indicators": "left" | "center" | "right" | "off" } }

Which icons are hidden lives in:
  $STATE_FILE

Undo with: scripts/uninstall.sh
DONE
