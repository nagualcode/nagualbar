import QtQuick
import Quickshell
import Quickshell.Io

// Persisted nagualbar state: which bar icons are hidden, and whether windows
// are allowed to sit under the bar.
//
// The state lives in its own file instead of `shell.json` on purpose. A
// shell.json write reassigns the bar's `layout` property, and the bar can only
// rebuild a section's widgets by handing the module Repeaters a brand new
// array — so every toggle routed through shell.json would tear down and
// re-instantiate every widget on the bar. Keeping the state here means
// flipping a toggle only moves a slot's size, and the widget underneath stays
// loaded, running, and reachable.
//
// Hiding is a presentation concern, not an enable/disable concern: nothing
// here removes a layout entry, calls `omarchy plugin disable`, or stops a
// service. The widget keeps ticking; only its icon stops painting.
QtObject {
  id: store

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/nagualbar.json"

  // Array of hidden keys. Reassigned (never mutated in place) so QML bindings
  // that read it through isHidden() re-evaluate.
  property var hidden: []
  // When true the bar stops reserving screen space, so tiled and fullscreen
  // windows line up with the top of the screen and the bar draws over them.
  property bool overlap: false
  property bool loaded: false

  signal changed()

  function isHidden(key) {
    var id = String(key || "")
    if (id === "") return false
    return hidden.indexOf(id) !== -1
  }

  function keys() {
    return hidden.slice()
  }

  function setHidden(key, value) {
    var id = String(key || "")
    if (id === "") return
    var current = isHidden(id)
    if (current === (value === true)) return
    setHiddenList(value === true ? hidden.concat([id]) : hidden.filter(function(item) { return item !== id }))
  }

  function toggle(key) {
    setHidden(key, !isHidden(key))
  }

  function showAll() {
    setHiddenList([])
  }

  function hideAll(keys) {
    var list = []
    var source = Array.isArray(keys) ? keys : []
    for (var i = 0; i < source.length; i++) {
      var id = String(source[i] || "")
      if (id !== "" && list.indexOf(id) === -1) list.push(id)
    }
    list.sort()
    setHiddenList(list)
  }

  function setHiddenList(list) {
    var next = list.slice()
    next.sort()
    if (JSON.stringify(next) === JSON.stringify(hidden)) return
    hidden = next
    persist()
  }

  // Set on the property rather than derived from `hidden`, so it is a plain
  // bool the PanelWindow binding can read without a function call per frame.
  function setOverlap(value) {
    var next = (value === true)
    if (next === overlap) return
    overlap = next
    persist()
  }

  function toggleOverlap() {
    setOverlap(!overlap)
  }

  // Re-read from disk. A malformed or missing file is treated as "nothing
  // hidden, no overlap" rather than an error: a typo in a hand-edited config
  // should cost the user their icon layout, not their bar. A version 1 file
  // predates the overlap flag and reads back as off, which is what it meant.
  function apply(raw) {
    var parsed = {}
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (e) {
      parsed = {}
    }
    var list = Array.isArray(parsed && parsed.hidden) ? parsed.hidden : []
    var clean = []
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i] || "")
      if (id !== "" && clean.indexOf(id) === -1) clean.push(id)
    }
    clean.sort()
    var overlapNext = (parsed && parsed.overlap === true)

    // Both fields are compared, so a change to either one re-evaluates the
    // bindings that read it.
    if (JSON.stringify(clean) === JSON.stringify(hidden) && overlapNext === overlap) return
    hidden = clean
    overlap = overlapNext
    changed()
  }

  function persist() {
    stateFile.setText(JSON.stringify({ version: 2, hidden: hidden, overlap: overlap }, null, 2) + "\n")
    changed()
  }

  // A typed property rather than a plain child: QtObject has no default
  // property, so a bare `FileView { }` here would not compile.
  property FileView stateFile: FileView {
    id: stateFile
    path: store.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      store.apply(text())
      store.loaded = true
    }
    onLoadFailed: {
      store.apply("{}")
      store.loaded = true
    }
    // Re-read on change, including our own atomic write. apply() is a no-op
    // when the content already matches, so the echo costs nothing.
    onFileChanged: reload()
  }
}
