#!/usr/bin/env bash
# Shared helpers for the nagualbar install and uninstall scripts.
#
# Sourced, never executed.

set -euo pipefail

NAGUALBAR_ID="nagualbar"
NAGUALBAR_REPO="https://github.com/nagualcode/nagualbar.git"
NAGUALBAR_INDICATORS_ID="omarchy.indicators"

OMARCHY_CONFIG_DIR="$HOME/.config/omarchy"
SHELL_CONFIG="$OMARCHY_CONFIG_DIR/shell.json"
SHELL_CONFIG_BACKUP="$OMARCHY_CONFIG_DIR/nagualbar-shell.json.bak"
PLUGINS_DIR="$OMARCHY_CONFIG_DIR/plugins"
PLUGIN_DIR="$PLUGINS_DIR/$NAGUALBAR_ID"
# Which icons are hidden. install.sh never writes this; the bar does, and only
# when a toggle actually changes.
STATE_FILE="$OMARCHY_CONFIG_DIR/nagualbar.json"
# How to undo the shell.json edits install.sh made.
INSTALL_STATE="$OMARCHY_CONFIG_DIR/nagualbar-install.json"

fail() {
  echo "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$2"
}

# Copy a plugin into place without ever exposing a half-written tree.
#
# The running shell watches the plugin directory and reloads a plugin the moment
# something in it changes, parsing whatever it finds at that instant. `rsync`
# straight into the live directory writes files one at a time, so the shell can
# read a truncated QML file and report a syntax error that no longer exists once
# the copy finishes — which is a miserable thing to debug. Staging the tree and
# swapping it in with a rename means the only thing the watcher can see is a
# whole plugin.
copy_plugin_tree() {
  local source="$1" target="$2"
  local staging="${target}.staging.$$" previous="${target}.old.$$"

  rm -rf "$staging" "$previous"
  mkdir -p "$staging"
  if ! rsync -a --delete --exclude '.git' "$source"/ "$staging"/; then
    rm -rf "$staging"
    return 1
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    mv "$target" "$previous" || { rm -rf "$staging"; return 1; }
  fi
  if ! mv "$staging" "$target"; then
    # Put the working copy back rather than leaving no plugin at all.
    [[ -e "$previous" ]] && mv "$previous" "$target"
    rm -rf "$staging"
    return 1
  fi
  rm -rf "$previous"
}

# Replace a file in one step, so a watcher never reads a half-written config.
# This is the same trick the shell's own FileView uses with atomicWrites.
write_json_file() {
  local target="$1" content="$2" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  printf '%s\n' "$content" >"$tmp"
  [[ -f "$target" ]] && chmod --reference="$target" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target"
}

# Run a jq program over shell.json and replace the file with the result.
#
# The new content is built and validated in full before anything is moved into
# place, so a jq error leaves the user's shell.json exactly as it was. That
# matters more than it looks: shell.json is the whole shell's configuration, and
# a helper that installs an empty file on failure would take the desktop with
# it. The rename is atomic, so the shell's file watcher never sees a partial
# write either.
rewrite_shell_config() {
  local original rewritten tmp
  [[ -f "$SHELL_CONFIG" ]] || fail "no shell.json at $SHELL_CONFIG"

  original="$(cat "$SHELL_CONFIG")" || fail "could not read $SHELL_CONFIG"
  rewritten="$(jq "$@" <<<"$original")" || fail "jq failed; $SHELL_CONFIG left untouched"
  [[ -n "$rewritten" ]] || fail "jq produced no output; $SHELL_CONFIG left untouched"
  jq -e . >/dev/null <<<"$rewritten" || fail "jq produced invalid JSON; $SHELL_CONFIG left untouched"

  # A first-touch backup, so a bad hand-edit is always recoverable. Never
  # overwritten: the point is to capture the state before nagualbar ran.
  [[ -f "$SHELL_CONFIG_BACKUP" ]] || cp -p "$SHELL_CONFIG" "$SHELL_CONFIG_BACKUP"

  tmp="$(mktemp "${SHELL_CONFIG}.XXXXXX")"
  printf '%s\n' "$rewritten" >"$tmp"
  chmod --reference="$SHELL_CONFIG" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$SHELL_CONFIG"
}

# Print where a layout entry lives, as JSON on stdout, or `null`.
find_layout_entry() {
  local id="$1"
  jq -c --arg id "$id" '
    def entry_id: if type == "object" then (.id // "") else tostring end;
    (.bar.layout // {}) as $layout
    | [ "left", "center", "right" ]
    | map(
        . as $section
        | [ ($layout[$section] // [])[] ]
        | to_entries
        | map(select(.value | entry_id == $id))
        | if length > 0
          then { section: $section, index: .[0].key, entry: .[0].value }
          else empty
          end
      )
    | first // null
  ' "$SHELL_CONFIG"
}

# Remove every layout entry with the given id. Prints where the entry was, as
# JSON on stdout, or `null` if it was not there.
#
# Read and write are separate calls on purpose: find_layout_entry reports from
# the same file that rewrite_shell_config then filters, and rewrite_shell_config
# refuses to write anything it could not fully parse. An entry that vanishes
# between the two — the user editing the layout mid-install — is reported as
# "not found" rather than half-restored later.
remove_layout_entry() {
  local id="$1" found
  found="$(find_layout_entry "$id")"
  rewrite_shell_config --arg id "$id" '
    def entry_id: if type == "object" then (.id // "") else tostring end;
    if (.bar | type) != "object" then .
    else .bar.layout = (.bar.layout // {})
    | reduce [ "left", "center", "right" ][] as $section (.;
        if [ (.bar.layout[$section] // [])[] | select(entry_id == $id) ] | length == 0
        then .
        else .bar.layout[$section] =
          [ (.bar.layout[$section] // [])[] | select(entry_id != $id) ]
        end)
    end
  '
  printf '%s' "$found"
}

# Put an entry back at the section and index it came from, creating the section
# if it is gone. A position past the end of the section appends, which is the
# right answer for a layout the user edited between install and uninstall.
restore_layout_entry() {
  local id="$1" section="$2" index="$3" entry="$4"
  [[ -n "$section" && -n "$index" && "$entry" != "null" ]] || return 0
  rewrite_shell_config --arg id "$id" --arg section "$section" \
    --argjson index "$index" --argjson entry "$entry" '
      def entry_id: if type == "object" then (.id // "") else tostring end;
      if (.bar | type) != "object" then .
      else .bar.layout = (.bar.layout // {})
      | .bar.layout[$section] = (
          [ (.bar.layout[$section] // [])[] | select(entry_id != $id) ] as $rest
          | if $index >= ($rest | length)
            then $rest + [$entry]
            else $rest[0:$index] + [$entry] + $rest[$index:]
            end
        )
      end
    '
}

# Record or read the section the indicator row should live in, defaulting to
# wherever omarchy's own indicator widget was so the bar does not silently
# rearrange itself on install.
resolve_indicator_section() {
  local configured found_section
  configured="$(jq -r '.bar.nagualbar.indicators // empty' "$SHELL_CONFIG")"
  if [[ "$configured" =~ ^(left|center|right|off)$ ]]; then
    printf '%s' "$configured"
    return 0
  fi
  found_section="$(find_layout_entry "$NAGUALBAR_INDICATORS_ID" | jq -r '.section // empty')"
  printf '%s' "${found_section:-right}"
}

shell_is_running() {
  omarchy-shell -q shell ping >/dev/null 2>&1
}
