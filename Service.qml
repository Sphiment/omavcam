import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// State machine over bin/omavcam. Everything here is a read of that CLI's JSON
// or a call to one of its subcommands — no system knowledge lives in QML.
Item {
  id: root

  property var settings: ({})

  // Absolute path to our own bin/omavcam. A plugin directory is not on PATH,
  // so the panel resolves it from the QML file's location and passes it in.
  property string cli: ""

  // ---- observed state -----------------------------------------------------
  property bool ready: false            // doctor reports nothing blocking
  property var issues: []
  property var missingPackages: []
  property var devices: []
  property var cameras: []
  property bool running: false          // a scrcpy process of ours is alive
  property bool streaming: false        // the node is actually advertising capture
  property var capture: ({})
  property int uptimeSec: 0
  property bool camerasLoaded: false
  property bool previewOpen: false
  // True while a setting change is being applied to a live stream.
  property bool reapplying: false
  property string previewSize: "medium"
  // What "original" would produce on the monitor the preview would land on.
  // null until a stream exists to measure.
  property var previewOriginal: null
  property string lastError: ""
  property bool checkedOnce: false

  // Optimistic state so the bar reacts the instant it is clicked rather than
  // at the next poll. -1 means "just follow what was observed".
  property int _desired: -1
  readonly property bool active: _desired === -1 ? streaming : (_desired === 1)

  readonly property bool busy: actionProcess.running || setupWatch.running || previewProcess.running
  readonly property string previewSource: String(setting("previewSource", "loopback"))
  readonly property var device: Model.selectedDevice(devices, setting("serial", ""))
  readonly property bool hasDevice: !!device
  readonly property var effectiveCamera: Model.effectiveCamera(cameras, setting("facing", "front"), setting("cameraId", ""))
  readonly property var sizeOptions: Model.sizeOptions(cameras, setting("facing", "front"), setting("cameraId", ""))
  readonly property var blockingIssue: Model.blockingIssue(issues)
  readonly property bool needsInstall: (missingPackages || []).length > 0

  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 5)), 10)
    if (!isFinite(n)) n = 5
    return Math.max(2, Math.min(120, n))
  }

  signal captureFailed(string message)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function statusText() {
    if (!checkedOnce) return "Checking…"
    if (needsInstall) return "Dependencies missing"
    if (blockingIssue && !streaming) return "Not ready"
    if (reapplying) return "Applying…"
    if (streaming) {
      var label = Model.formatUptime(uptimeSec)
      return label === "" ? "Streaming" : "Streaming · " + label
    }
    if (running) return "Starting…"
    if (!hasDevice) return "No phone"
    return "Ready"
  }

  // ---- reading state ------------------------------------------------------

  // The CLI takes the preview source from its environment, so anything that
  // reports or changes preview state has to run under it.
  function withSource(args, source) {
    return ["env", "OMAVCAM_PREVIEW_SOURCE=" + (source || previewSource)].concat(args)
  }

  // scrcpy fixes the camera, resolution and frame rate at launch, so a setting
  // cannot be changed on a live stream — it can only be re-established on a new
  // one. restart carries the settings across, and omavcam does it for the user
  // rather than making them stop and start by hand.
  //
  // Every managed value is sent explicitly, including empty ones, because empty
  // is a real choice ("camera default") and must be distinguishable from
  // "unspecified", which restart takes to mean "leave alone".
  function restartArgs(overrides) {
    var o = overrides || {}
    function pick(key, fallback) {
      return o[key] !== undefined ? String(o[key]) : String(setting(key, fallback))
    }

    var args = []
    if (device) args.push("-s", String(device.serial))

    var cameraId = pick("cameraId", "")
    if (cameraId !== "") args.push("--camera-id", cameraId)
    else args.push("--facing", pick("facing", "front"))

    args.push("--size", pick("size", ""))
    args.push("--fps", pick("fps", ""))
    return args
  }

  // Applies a setting to a running capture. Does nothing when idle — the new
  // value is already persisted and will be used by the next start.
  function applyLive(overrides) {
    if (cli === "" || actionProcess.running) return
    if (!running && !streaming) return
    reapplying = true
    _desired = 1
    lastError = ""
    actionProcess.command = withSource([cli, "restart"].concat(restartArgs(overrides)))
    actionProcess.running = true
  }

  function reopenPreview(source) {
    if (cli === "" || previewProcess.running || !previewOpen) return
    previewProcess.command = withSource([cli, "preview", "reopen"], source)
    previewProcess.running = true
  }

  function refresh() {
    if (cli === "") return
    if (!doctorProcess.running) doctorProcess.command = [cli, "doctor", "--json"], doctorProcess.running = true
    if (!statusProcess.running) statusProcess.command = withSource([cli, "status", "--json"]), statusProcess.running = true
    if (!devicesProcess.running) devicesProcess.command = [cli, "devices", "--json"], devicesProcess.running = true
  }

  // Deliberately not part of refresh(): listing cameras pushes scrcpy's server
  // to the phone, so it runs when the panel opens or the phone changes, not on
  // every poll.
  function refreshCameras() {
    if (cli === "" || !hasDevice || camerasProcess.running) return
    // Listing cameras opens the camera on the phone. Doing that while a capture
    // is being started or restarted makes the two contend for the same device,
    // and the capture is the one that matters.
    if (actionProcess.running) return
    camerasProcess.command = [cli, "cameras", "--json", "-s", String(device.serial)]
    camerasProcess.running = true
  }

  // ---- acting -------------------------------------------------------------

  function start() {
    if (cli === "" || actionProcess.running) return
    _desired = 1
    lastError = ""

    var args = [cli, "start"]
    if (device) args.push("-s", String(device.serial))

    var cameraId = String(setting("cameraId", ""))
    if (cameraId !== "") args.push("--camera-id", cameraId)
    else args.push("--facing", String(setting("facing", "front")))

    var size = String(setting("size", ""))
    if (size !== "") args.push("--size", size)

    var fps = String(setting("fps", ""))
    if (fps !== "") args.push("--fps", fps)

    actionProcess.command = args
    actionProcess.running = true
  }

  function stop() {
    if (cli === "" || actionProcess.running) return
    _desired = 0
    actionProcess.command = [cli, "stop"]
    actionProcess.running = true
  }

  function toggle() {
    if (active) stop()
    else start()
  }

  function togglePreview() {
    if (cli === "" || previewProcess.running) return
    previewProcess.command = withSource([cli, "preview", previewOpen ? "off" : "on"])
    previewProcess.running = true
  }

  function setPreviewSize(size) {
    if (cli === "" || previewProcess.running) return
    previewSize = size
    previewProcess.command = withSource([cli, "preview", "resize", size])
    previewProcess.running = true
  }

  // Package installation needs a terminal: it prompts for sudo and its output
  // is worth watching. Omarchy already owns that surface, so hand off to it
  // rather than trying to render a pacman run inside a popup.
  function runSetup() {
    if (cli === "") return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
                             cli + " setup"])
    setupWatch.restart()
  }

  Component.onCompleted: refresh()

  onCliChanged: refresh()

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.cli !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A setup run happens in another window, so poll faster for a while after
  // launching it — otherwise the panel keeps claiming dependencies are missing
  // for several seconds after they are not.
  Timer {
    id: setupWatch
    interval: 2000
    repeat: true
    triggeredOnStart: false
    property int ticks: 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks > 150 || (root.ready && !root.needsInstall)) stop()
    }
    function restart() {
      ticks = 0
      start()
    }
  }

  Process {
    id: doctorProcess
    running: false
    command: []
    stdout: StdioCollector { id: doctorOut; waitForEnd: true }
    onExited: function (exitCode) {
      var report = Model.safeParse(doctorOut.text, null)
      root.checkedOnce = true
      if (!report) {
        root.ready = false
        return
      }
      root.ready = report.ok === true
      root.issues = report.issues || []
      root.missingPackages = report.missingPackages || []
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function (exitCode) {
      var report = Model.safeParse(statusOut.text, null)
      if (!report) return
      root.running = report.running === true
      root.streaming = report.streaming === true
      root.capture = report.capture || ({})
      root.uptimeSec = parseInt(report.uptimeSec, 10) || 0
      if (report.preview) {
        root.previewOpen = report.preview.open === true
        if (report.preview.size) root.previewSize = String(report.preview.size)
        root.previewOriginal = report.preview.original || null
      }
      // Observation has caught up with the click, so stop overriding it.
      if (root._desired !== -1 && (root._desired === 1) === root.streaming) root._desired = -1
    }
  }

  Process {
    id: devicesProcess
    running: false
    command: []
    stdout: StdioCollector { id: devicesOut; waitForEnd: true }
    onExited: function (exitCode) {
      var previous = root.device ? String(root.device.serial) : ""
      root.devices = Model.safeParse(devicesOut.text, [])
      var current = root.device ? String(root.device.serial) : ""
      // Cameras belong to a phone, so a different phone invalidates them.
      if (current !== previous) {
        root.cameras = []
        root.camerasLoaded = false
      }
    }
  }

  Process {
    id: camerasProcess
    running: false
    command: []
    stdout: StdioCollector { id: camerasOut; waitForEnd: true }
    onExited: function (exitCode) {
      root.cameras = Model.safeParse(camerasOut.text, [])
      root.camerasLoaded = true
    }
  }

  Process {
    id: previewProcess
    running: false
    command: []
    stdout: StdioCollector { id: previewOut; waitForEnd: true }
    stderr: StdioCollector { id: previewErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        var text = String(previewErr.text || "").trim()
        if (text !== "") root.lastError = text.split("\n").pop()
      }
      root.refresh()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.reapplying = false
      if (exitCode !== 0) {
        // start already prints scrcpy's own words on failure; surface the last
        // meaningful line rather than inventing a message.
        var text = String(actionErr.text || actionOut.text || "").trim()
        var lines = text.split("\n").filter(function (l) { return l.trim() !== "" })
        root.lastError = lines.length > 0 ? lines[lines.length - 1] : "Capture failed"
        root._desired = -1
        root.captureFailed(root.lastError)
      }
      root.refresh()
    }
  }
}
