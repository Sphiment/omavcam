import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "sphiment.omavcam"
  ipcTarget: "sphiment.omavcam"
  // manageIpc: false so this panel owns the single handler the target allows,
  // and can expose start/stop/toggleCapture for keybinds.
  manageIpc: false

  // The bar sizes a widget from its implicit size, and Panel is a bare Item —
  // without this the widget occupies zero width and renders nothing.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The video-camera glyph Omarchy itself uses for screen recording, so it is
  // known to render in the bar font. State is carried by color, not by glyph.
  //
  // Written as an escape on purpose: as a literal character it is invisible in
  // a diff and survives nothing — an editor, a rewrite, or a stray encoding
  // step can drop it, leaving an empty string. BarIconButton hides a button
  // with no text, so losing it removes the widget from the bar silently, with
  // no error anywhere.
  readonly property string icon: "\uf03d"

  readonly property color barIconColor: {
    if (service.active) return barForeground
    if (service.needsInstall || service.lastError !== "") return urgent
    return Qt.darker(barForeground, 1.55)
  }

  // A phone that is not plugged in is not a problem worth a bar icon, for
  // people who only occasionally use one.
  readonly property bool concealed: service.setting("hideWhenIdle", false) === true
                                    && !service.hasDevice && !service.active

  property bool cursorActive: false

  // An explicit camera id would override the facing the user just picked, so
  // choosing a facing clears it.
  function chooseFacing(facing) {
    // No camera re-listing here: the list belongs to the phone, not to the
    // facing, and sizeOptions is already derived from it. Asking for it now
    // would open the camera on the phone at the same moment scrcpy is trying
    // to claim it for the restart, and the capture loses that race.
    var change = {cameraId: "", facing: facing}

    // Carry the resolution over only if the camera being switched to actually
    // offers it. Otherwise scrcpy refuses the size and the stream drops for a
    // beat before the CLI's fallback rescues it — better to not ask.
    if (!Model.sizeSupported(service.cameras, facing, "", service.setting("size", ""))) {
      change.size = ""
    }

    persist(change)
    service.applyLive(change)
  }

  readonly property var previewSizes: ["small", "medium", "large", "original"]

  property bool originalWarningOpen: false

  // Only warn when the stream is known to be larger than the screen it would
  // open on. A measurement we could not take is not a reason to warn, and a
  // stream that fits should apply without ceremony.
  readonly property bool originalOverflows: {
    var o = service.previewOriginal
    return !!o && o.fitsScreen === false
  }

  readonly property string originalWarningText: {
    var o = service.previewOriginal
    if (!o) return ""
    return "The preview would be " + o.width + "\u00d7" + o.height
         + ", larger than this screen (" + o.screenWidth + "\u00d7" + o.screenHeight
         + "). It will extend past the edges — drag it by its top-left corner."
  }

  // Applies a preview size, asking first when "original" would overflow.
  function choosePreviewSize(size) {
    if (size === "original" && originalOverflows) {
      originalWarningOpen = true
      return
    }
    service.setPreviewSize(size)
  }

  function nextPreviewSize(step) {
    var index = previewSizes.indexOf(service.previewSize)
    if (index === -1) index = 1
    return previewSizes[Math.max(0, Math.min(previewSizes.length - 1, index + step))]
  }

  // Takes a whole set of values, because writing them one at a time would read
  // back a stale `settings` for the second key and undo the first.
  function persist(values) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = {id: root.moduleName}
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    for (var key in values) entry[key] = values[key]
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Service {
    id: service
    settings: root.settings
    // A plugin directory is not on PATH, so resolve our own CLI from this
    // file's location and strip the URL scheme Process cannot use.
    cli: String(Qt.resolvedUrl("bin/omavcam")).replace(/^file:\/\//, "")
    onCaptureFailed: function (message) {
      errorText.visible = true
    }
  }

  onOpenedChanged: {
    if (opened) {
      service.refresh()
      if (!service.camerasLoaded) service.refreshCameras()
    } else {
      cursorActive = false
    }
  }

  IpcHandler {
    target: "sphiment.omavcam"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): void { service.start() }
    function stop(): void { service.stop() }
    function toggleCapture(): void { service.toggle() }
    function togglePreview(): void { service.togglePreview() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.concealed ? "" : root.icon
    foreground: root.barIconColor
    onPressed: function (b) {
      if (b === Qt.RightButton) service.toggle()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // PanelKeyCatcher owns Keys.onPressed itself, so the dialog is driven
      // through its signals rather than by intercepting raw key events — an
      // instance-level Keys.onPressed here simply never fires.
      onMoveRequested: function (dx, dy) {
        if (root.originalWarningOpen && dx !== 0)
          originalWarning.selectedIndex = originalWarning.selectedIndex === 0 ? 1 : 0
      }
      onActivateRequested: {
        if (!root.originalWarningOpen) return
        if (originalWarning.selectedIndex === 0) originalWarning.canceled()
        else originalWarning.confirmed()
      }
      onCloseRequested: {
        if (root.originalWarningOpen) root.originalWarningOpen = false
        else root.close()
      }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        // The dialog is modal: nothing behind it should act on a keystroke.
        if (root.originalWarningOpen) return
        var key = String(t).toLowerCase()
        if (key === "s") service.toggle()
        else if (key === "r") { service.refresh(); service.refreshCameras() }
        else if (key === "f") root.chooseFacing("front")
        else if (key === "b") root.chooseFacing("back")
        else if (key === "p") service.togglePreview()
        else if (key === "+" || key === "=") root.choosePreviewSize(nextPreviewSize(1))
        else if (key === "-" || key === "_") root.choosePreviewSize(nextPreviewSize(-1))
      }

      ConfirmDialog {
        id: originalWarning
        anchors.fill: parent
        z: 10
        opened: root.originalWarningOpen
        message: root.originalWarningText
        confirmText: "Show anyway"
        cancelText: "Cancel"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.originalWarningOpen = false
        onConfirmed: {
          root.originalWarningOpen = false
          service.setPreviewSize("original")
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ---------- Hero: state, and the switch that changes it ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, captureSwitch.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            opacity: service.active ? 1.0 : 0.5
          }

          ToggleSwitch {
            id: captureSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: service.active
            busy: service.busy
            interactive: service.hasDevice && !service.needsInstall
            foreground: root.foreground
            onToggled: service.toggle()

            PanelToolTip {
              visible: captureSwitch.containsMouse
              text: service.active ? "Stop the virtual camera" : "Start the virtual camera"
              fontFamily: root.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: captureSwitch.width + Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "omavcam"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: service.statusText().toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- Dependencies missing ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: service.needsInstall

          PanelSeparator { width: parent.width }

          Text {
            width: parent.width
            text: "omavcam needs " + Model.missingPackagesText(service.missingPackages) + "."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Install dependencies"
            fontFamily: root.fontFamily
            onClicked: service.runSetup()
          }
        }

        // ---------- Something else is blocking ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !service.needsInstall && !!service.blockingIssue

          PanelSeparator { width: parent.width }

          Text {
            width: parent.width
            text: service.blockingIssue ? service.blockingIssue.message : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Phone ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !service.needsInstall

          PanelSeparator { width: parent.width }
          PanelSectionHeader { text: "PHONE"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            width: parent.width
            visible: service.devices.length === 0
            text: "Plug a phone in and enable USB debugging."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: service.devices

            Item {
              required property var modelData
              width: column.width
              implicitHeight: Style.space(22)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Model.deviceLabel(modelData)
                color: modelData.ready ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width - stateLabel.width - Style.space(10)
              }

              Text {
                id: stateLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Model.deviceStateText(modelData.state)
                color: modelData.ready ? root.dim : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---------- Camera ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !service.needsInstall && service.hasDevice

          PanelSeparator { width: parent.width }
          PanelSectionHeader { text: "CAMERA"; foreground: root.foreground; fontFamily: root.fontFamily }

          ButtonGroup {
            width: parent.width
            options: [
              {value: "front", label: "Front"},
              {value: "back", label: "Back"}
            ]
            value: String(service.setting("facing", "front"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function (value) { root.chooseFacing(value) }
          }

          Dropdown {
            width: parent.width
            label: "Resolution"
            visible: service.sizeOptions.length > 0
            fontFamily: root.fontFamily
            options: {
              var out = [{value: "", label: "Camera default"}]
              var sizes = Model.shortlistSizes(service.sizeOptions, 6)
              for (var i = 0; i < sizes.length; i++) out.push({value: sizes[i], label: sizes[i]})
              return out
            }
            value: String(service.setting("size", ""))
            onChanged: function (value) {
              root.persist({size: value})
              service.applyLive({size: value})
            }
          }

          Text {
            width: parent.width
            visible: !service.camerasLoaded
            text: "Reading the phone's cameras…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Preview ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !service.needsInstall && service.streaming

          PanelSeparator { width: parent.width }

          Item {
            width: parent.width
            implicitHeight: Math.max(previewHeader.implicitHeight, previewSwitch.implicitHeight)

            PanelSectionHeader {
              id: previewHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "PREVIEW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleSwitch {
              id: previewSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: service.previewOpen
              busy: service.busy
              foreground: root.foreground
              onToggled: service.togglePreview()

              PanelToolTip {
                visible: previewSwitch.containsMouse
                text: service.previewOpen ? "Close the preview window" : "Show what the other side sees"
                fontFamily: root.fontFamily
              }
            }
          }

          ButtonGroup {
            width: parent.width
            visible: service.previewOpen
            options: [
              {value: "small", label: "Small"},
              {value: "medium", label: "Medium"},
              {value: "large", label: "Large"},
              {value: "original", label: "Original"}
            ]
            value: service.previewSize
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function (value) { root.choosePreviewSize(value) }
          }

          ButtonGroup {
            width: parent.width
            options: [
              {value: "loopback", label: "Virtual cam"},
              {value: "scrcpy", label: "scrcpy window"}
            ]
            value: service.previewSource
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function (value) {
              root.persist({previewSource: value})
              // The two sources are different windows owned by different
              // processes, so an open preview has to be re-made, not retargeted.
              service.reopenPreview(value)
            }
          }

          Text {
            width: parent.width
            text: {
              if (service.previewSize === "original")
                return "Original is the stream's real pixel size, so it can be larger than the screen. Drag it from its top-left corner."
              return service.previewSource === "loopback"
                     ? "Shows the virtual camera itself — exactly what the other side sees."
                     : "Shows scrcpy's window, which can also control the phone. Switching it restarts the stream."
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Last failure ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: errorText.visible && service.lastError !== ""

          PanelSeparator { width: parent.width }

          Text {
            id: errorText
            visible: false
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
