// Single source of truth for the indicator icons nagualbar hosts.
//
// The order here is the order they appear in the bar, and the order they
// appear in the right-click contents menu. Ids match the file names in
// `indicators/`, which are vendored from omarchy's own bar indicators.
function list() {
  return [
    { id: "Dictation",       label: "Dictation",        description: "Voice typing status" },
    { id: "ScreenRecording", label: "Screen recording", description: "GPU screen recorder status" },
    { id: "Reminder",        label: "Reminder",         description: "Queued reminder status" },
    { id: "NightLight",      label: "Night light",      description: "Blue-light filter" },
    { id: "Dnd",             label: "Do not disturb",   description: "Notification silencing" },
    { id: "StayAwake",       label: "Stay awake",       description: "Idle lock and screensaver override" }
  ]
}

function ids() {
  var out = []
  var entries = list()
  for (var i = 0; i < entries.length; i++) out.push(entries[i].id)
  return out
}

function entryFor(id) {
  var entries = list()
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].id === String(id || "")) return entries[i]
  }
  return { id: String(id || ""), label: String(id || ""), description: "" }
}

function labelFor(id) {
  return entryFor(id).label
}

function descriptionFor(id) {
  return entryFor(id).description
}
