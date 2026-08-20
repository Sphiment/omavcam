.pragma library

// Pure helpers for the omavcam panel. No QML types in here, so the parsing and
// formatting can be reasoned about — and fixed — without touching the UI.

function safeParse(text, fallback) {
  var raw = String(text || "").trim()
  if (raw === "") return fallback
  try {
    var parsed = JSON.parse(raw)
    return parsed === null || parsed === undefined ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

// A phone's display name: its model when adb reports one, otherwise the serial,
// which is always present and is what the user sees in `adb devices`.
function deviceLabel(device) {
  if (!device) return ""
  var model = String(device.model || "").trim()
  return model !== "" ? model : String(device.serial || "")
}

// adb's raw states are jargon. Say what the user should do about each.
function deviceStateText(state) {
  switch (String(state || "")) {
  case "device": return "Ready"
  case "unauthorized": return "Check phone screen"
  case "offline": return "Offline"
  case "no permissions": return "No permission"
  default: return String(state || "Unknown")
  }
}

function firstReadyDevice(devices) {
  var list = devices || []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].ready) return list[i]
  return null
}

// The device the panel should act on: the configured serial when it is present
// and usable, otherwise the first ready one.
function selectedDevice(devices, serial) {
  var list = devices || []
  var wanted = String(serial || "")
  if (wanted !== "") {
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].serial) === wanted && list[i].ready) return list[i]
  }
  return firstReadyDevice(list)
}

// Cameras matching a facing, in scrcpy's own order. A phone commonly reports
// several per facing (wide, ultrawide), and scrcpy picks the first.
function camerasForFacing(cameras, facing) {
  var list = cameras || []
  var want = String(facing || "").toLowerCase()
  var out = []
  for (var i = 0; i < list.length; i++)
    if (list[i] && String(list[i].facing || "").toLowerCase() === want) out.push(list[i])
  return out
}

function cameraById(cameras, id) {
  var list = cameras || []
  var wanted = String(id || "")
  if (wanted === "") return null
  for (var i = 0; i < list.length; i++)
    if (list[i] && String(list[i].id) === wanted) return list[i]
  return null
}

// Which camera a capture would actually use, given the current settings: an
// explicit id wins, otherwise the first camera with the chosen facing.
function effectiveCamera(cameras, facing, cameraId) {
  var byId = cameraById(cameras, cameraId)
  if (byId) return byId
  var matching = camerasForFacing(cameras, facing)
  return matching.length > 0 ? matching[0] : null
}

// Resolutions to offer. Only the effective camera's own list is valid — scrcpy
// rejects a --camera-size the camera does not advertise.
function sizeOptions(cameras, facing, cameraId) {
  var camera = effectiveCamera(cameras, facing, cameraId)
  if (!camera || !camera.sizes) return []
  return camera.sizes.slice()
}

// A long list of resolutions is unhelpful in a small panel. Offer the largest,
// then the common meeting sizes, then whatever else is near the top.
function shortlistSizes(sizes, limit) {
  var all = sizes || []
  var max = limit || 6
  var preferred = ["1920x1080", "1280x720", "960x720", "640x480"]
  var out = []
  function push(size) {
    if (size && out.indexOf(size) === -1 && out.length < max) out.push(size)
  }
  if (all.length > 0) push(all[0])
  for (var i = 0; i < preferred.length; i++)
    if (all.indexOf(preferred[i]) !== -1) push(preferred[i])
  for (var j = 0; j < all.length; j++) push(all[j])
  return out
}

function facingLabel(facing) {
  switch (String(facing || "").toLowerCase()) {
  case "front": return "Front"
  case "back": return "Back"
  case "external": return "External"
  default: return String(facing || "")
  }
}

function formatUptime(seconds) {
  var total = parseInt(seconds, 10)
  if (!isFinite(total) || total < 0) return ""
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

// The first thing that actually blocks capture. Warnings are deliberately
// ignored here: "will not survive a reboot" should not read as broken.
function blockingIssue(issues) {
  var list = issues || []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].severity === "blocked") return list[i]
  return null
}

function missingPackagesText(packages) {
  var list = packages || []
  if (list.length === 0) return ""
  if (list.length === 1) return list[0]
  return list.slice(0, -1).join(", ") + " and " + list[list.length - 1]
}
