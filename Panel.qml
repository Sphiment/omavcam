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

  // Same video-camera glyph Omarchy uses for screen recording, so it is known
  // to render in the bar font. State is carried by color, not by glyph.
  readonly property string icon: ""

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
    persist("cameraId", "")
    persist("facing", facing)
    service.refreshCameras()
  }

  function persist(key, value) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = {id: root.moduleName}
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry[key] = value
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
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "s") service.toggle()
        else if (key === "r") { service.refresh(); service.refreshCameras() }
        else if (key === "f") root.chooseFacing("front")
        else if (key === "b") root.chooseFacing("back")
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
            onChanged: function (value) { root.persist("size", value) }
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
