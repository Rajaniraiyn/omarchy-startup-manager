.pragma library

function parsePayload(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (!parsed || !(parsed.items instanceof Array)) throw new Error("Missing items")
    return { ok: true, items: parsed.items, summary: parsed.summary || {} }
  } catch (error) {
    return { ok: false, items: [], summary: {}, error: String(error) }
  }
}

function filtered(items, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return items || []
  return (items || []).filter(function(item) {
    return String(item.name || "").toLowerCase().indexOf(needle) !== -1
      || String(item.description || "").toLowerCase().indexOf(needle) !== -1
      || String(item.file_state || "").toLowerCase().indexOf(needle) !== -1
  })
}

function memory(bytes) {
  var value = Number(bytes || 0)
  if (value <= 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024
    index++
  }
  var digits = index >= 3 ? 1 : 0
  return value.toFixed(digits) + " " + units[index]
}

function status(item) {
  if (item.failed) return "FAILED"
  if (item.scope === "autostart") return item.enabled ? "STARTS AT LOGIN" : "DISABLED"
  if (item.running) return "RUNNING"
  if (item.enabled) return "ENABLED · STOPPED"
  return "DISABLED"
}

function actionLabel(action) {
  if (action === "disable") return "Disable startup"
  if (action === "enable") return "Enable startup"
  return action.charAt(0).toUpperCase() + action.slice(1)
}
