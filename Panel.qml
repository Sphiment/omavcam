import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Scaffold: the bar button and an empty popup, so the plugin loads and can be
// placed on the bar before any of the scrcpy machinery exists. Device
// detection, capture controls, and the preview arrive in later phases.
Panel {
  id: root
  moduleName: "sphiment.omavcam"
  ipcTarget: "sphiment.omavcam"

  // Same video-camera glyph Omarchy uses for screen recording, so it is known
  // to render in the bar font. State is carried by color, not by glyph.
  readonly property string icon: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)

  // The bar sizes a widget from its implicit size, and Panel is a bare Item —
  // without this the widget occupies zero width and renders nothing.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function (b) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(6)

        Text {
          text: "omavcam"
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: "Not wired up yet."
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
