import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// To Do: a drop-down panel and an app window over one task list.
//
//   omarchy-shell shell toggle simonmcschubert.todo          drop-down on/off
//   omarchy-shell shell summon simonmcschubert.todo window   open the window
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "simonmcschubert.todo"

  property bool dropdownShown: false
  // The shell's toggle asks this; the window is a normal app window outside it.
  readonly property bool opened: dropdownShown

  // Payload: "window", or JSON {"view": "window"}; anything else is the drop-down.
  function viewFor(payload) {
    var text = String(payload || "").trim()
    if (text === "window") return "window"
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.view === "window") return "window"
    } catch (e) {}
    return "dropdown"
  }

  function open(payload) {
    store.refreshToday()
    if (viewFor(payload) === "window") {
      dropdownShown = false
      appWindow.visible = true
      Qt.callLater(appView.focusInput)
    } else {
      dropdownShown = true
      Qt.callLater(dropView.focusInput)
    }
  }

  // Host-initiated close (`shell hide`, toggle). The window stays open.
  function close() {
    dropdownShown = false
  }

  function dismissDropdown() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    dropdownShown = false
  }

  ErrorReports {
    id: reports
    release: "omarchy-todo@" + (root.manifest && root.manifest.version ? root.manifest.version : "unknown")
    pluginUrl: Qt.resolvedUrl(".")
  }

  TaskStore {
    id: store
    reports: reports
  }

  Ui.OverlayWindow {
    id: dropdown
    shown: root.dropdownShown
    WlrLayershell.namespace: "omarchy-todo"

    // Click outside the card to close.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismissDropdown()
    }

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    Rectangle {
      id: card
      anchors.top: parent.top
      anchors.topMargin: Style.gapsOut + Style.bar.sizeHorizontal
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(Style.space(680), parent.width - Style.space(40))
      // Grows with the list up to most of the screen, then scrolls.
      height: Math.min(dropView.implicitHeight + Style.spacing.panelPadding * 2,
                       Math.round(parent.height * 0.75))
      color: Commons.Color.menu.background
      border.color: Commons.Color.menu.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius

      // Keep clicks inside the card from closing it.
      MouseArea { anchors.fill: parent }

      TaskView {
        id: dropView
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        store: store
        compact: true
        focus: true
        onCloseRequested: root.dismissDropdown()
      }
    }
  }

  FloatingWindow {
    id: appWindow
    visible: false
    title: "To Do"
    color: Commons.Color.menu.background
    implicitWidth: 620
    implicitHeight: 720
    minimumSize: Qt.size(420, 420)

    TaskView {
      id: appView
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      store: store
      compact: false
      focus: true
      // Esc does not close the window; Super+W does, like any window.
      onCloseRequested: appView.focusInput()
    }
  }
}
