import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// To Do: a drop-down panel, quick add, and an app window over one task list.
//
//   omarchy-shell shell toggle simonmcschubert.todo          drop-down on/off
//   omarchy-shell shell toggle simonmcschubert.todo add      quick add on/off
//   omarchy-shell shell summon simonmcschubert.todo window   open the window
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "simonmcschubert.todo"

  // What the drop-down card shows: "dropdown" (the list), "add" (quick add:
  // only the field for a new task), or "" while it is hidden.
  property string dropdownView: ""
  // The shell's toggle asks this; the window is a normal app window outside it.
  readonly property bool opened: dropdownView !== ""

  // The bar, so the drop-down stays clear of it on whichever edge it is.
  readonly property var bar: shell && shell.bar ? shell.bar : null
  readonly property string barPosition: bar && bar.position ? String(bar.position) : "top"

  function barThickness(screenName) {
    var fallback = barPosition === "left" || barPosition === "right"
      ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    if (!bar) return fallback
    if (bar.barHidden) return 0
    var size = Number(typeof bar.barSizeFor === "function" ? bar.barSizeFor(screenName) : bar.barSize)
    return isFinite(size) && size > 0 ? size : fallback
  }

  // Payload: "window" or "add", or JSON {"view": "window"} / {"view": "add"};
  // anything else is the drop-down.
  function viewFor(payload) {
    var text = String(payload || "").trim()
    if (text === "window" || text === "add") return text
    try {
      var parsed = JSON.parse(text)
      if (parsed && (parsed.view === "window" || parsed.view === "add")) return parsed.view
    } catch (e) {}
    return "dropdown"
  }

  function open(payload) {
    store.refreshToday()
    var view = viewFor(payload)
    if (view === "window") {
      dropdownView = ""
      showWindow()
    } else {
      dropdownView = view
      Qt.callLater(dropView.focusInput)
    }
  }

  // Opens the window, or brings it forward when it is already open, perhaps
  // on another workspace, as the app launcher does for other apps.
  function showWindow() {
    var toplevel = appWindow.visible ? windowToplevel() : null
    if (toplevel) toplevel.activate()
    else appWindow.visible = true
    Qt.callLater(appView.focusInput)
  }

  // The window's handle in the compositor's window list; null until it shows.
  function windowToplevel() {
    var toplevels = ToplevelManager.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (toplevel.appId === "org.quickshell" && toplevel.title === appWindow.title) return toplevel
    }
    return null
  }

  // Host-initiated close (`shell hide`, toggle). The window stays open.
  function close() {
    dropdownView = ""
  }

  function dismissDropdown() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    dropdownView = ""
  }

  ErrorReports {
    id: reports
    // The installed release, from the checkout's tags; manifest.json's
    // version for a copy without them.
    release: "omarchy-todo@" + (updater.installed || (root.manifest && root.manifest.version ? root.manifest.version : "unknown"))
    // The shell sets manifest only after it has created the plugin.
    releaseKnown: updater.installedKnown && (updater.installed !== "" || root.manifest !== null)
    pluginUrl: Qt.resolvedUrl(".")
  }

  TaskStore {
    id: store
    reports: reports
  }

  Updater { id: updater }

  Ui.OverlayWindow {
    id: dropdown
    shown: root.opened
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

    // The screen less the bar and Hyprland's outer gap. The card and its date
    // picker stay inside it.
    Item {
      id: safeArea
      readonly property int barSize: root.barThickness(dropdown.targetScreen ? String(dropdown.targetScreen.name) : "")
      // Margins name physical edges, even when right-to-left mirrors the rest.
      LayoutMirroring.enabled: false
      anchors.fill: parent
      anchors.topMargin: Style.gapsOut + (root.barPosition === "top" ? barSize : 0)
      anchors.bottomMargin: Style.gapsOut + (root.barPosition === "bottom" ? barSize : 0)
      anchors.leftMargin: Style.gapsOut + (root.barPosition === "left" ? barSize : 0)
      anchors.rightMargin: Style.gapsOut + (root.barPosition === "right" ? barSize : 0)
    }

    Rectangle {
      id: card
      anchors.top: safeArea.top
      anchors.horizontalCenter: safeArea.horizontalCenter
      width: Math.min(Style.space(680), safeArea.width)
      // Grows with the list up to most of the screen, then scrolls.
      height: Math.min(dropView.implicitHeight + Style.spacing.panelPadding * 2,
                       Math.round(parent.height * 0.75), safeArea.height)
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
        updater: updater
        // The drop-down shows only Focus; quick add only the field.
        surface: root.dropdownView === "add" ? "add" : "dropdown"
        focus: true
        // The picker may hang below a short card, but not over the bar.
        popupBounds: safeArea
        onCloseRequested: root.dismissDropdown()
        // Quick add is done once the task is in.
        onAdded: if (surface === "add") root.dismissDropdown()
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

    // Closing the window (Super+W) hides it, but Quickshell 0.3 keeps the
    // `visible = true` it was opened with, so setting it again would show
    // nothing until the shell restarts. Clear it, so the next open shows it.
    onClosed: visible = false

    TaskView {
      id: appView
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      store: store
      updater: updater
      surface: "window"
      focus: true
      // Esc does not close the window; Super+W does, like any window.
      onCloseRequested: appView.focusInput()
    }
  }
}
