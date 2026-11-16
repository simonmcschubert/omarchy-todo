import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks
import "list.js" as List

// The task list UI, shown in the window, the drop-down, and quick add
// (surface). The window has all tabs, the drop-down only Focus, and quick
// add is just the field for a new task: no tabs and no list. Which task a
// key acts on, and what adding a task does, are the list rules in list.js:
// this view keeps their state, sends them events, and applies the effects.
FocusScope {
  id: view

  property var store: null
  property var updater: null
  // "window", "dropdown", or "add" (quick add).
  property string surface: "window"
  readonly property bool inWindow: surface === "window"
  readonly property bool quickAdd: surface === "add"
  // The list rules' state (list.js): tab, selectedId, shortcutsShown,
  // describing, newDue, newStarred, pickerTarget.
  property var ui: List.initial("window")
  // Where the date picker may open. Unset, it is the whole window.
  property Item popupBounds: null

  property color foreground: Commons.Color.menu.text
  property color background: Commons.Color.menu.background
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property color border: Commons.Color.menu.border
  property color hoverFill: Commons.Color.menu.selectedBackground
  property string fontFamily: Style.font.family
  readonly property color dim: Util.alpha(foreground, 0.55)

  readonly property var rows: !store ? [] : (ui.tab === "focus" ? store.focusRows
                                           : ui.tab === "open" ? store.openRows : store.doneRows)
  // A task opened from the list replaces the list until Back or Esc.
  readonly property bool taskOpen: detail.task !== null

  // The update button for each state of the updater (Updater.qml); null
  // hides it. The window always shows it, as a circle that checks for
  // updates when clicked. The drop-down shows it only to offer a release.
  readonly property var updateButton: {
    if (!updater) return null
    var name = "To Do " + updater.version
    switch (updater.status) {
    case "available":
      return { icon: "", text: "Update", color: accent, tip: name + " is available. Click to download it." }
    case "downloading":
      return { icon: "", text: "Downloading", color: accent, tip: "Downloading " + name + "." }
    case "downloaded":
      return { icon: "", text: "Restart to update", color: accent,
               tip: name + " is downloaded. Click to restart the Omarchy shell with it. Your tasks stay as they are." }
    case "installing":
      return { icon: "", text: "Updating", color: accent, tip: "Installing " + name + " and restarting the shell.", busy: true }
    case "failed":
      return { icon: "", text: "Update failed", color: urgent, tip: "Can't download " + name + ". Click to try again." }
    }
    if (!inWindow) return null
    var installed = updater.installed !== "" ? "To Do " + updater.installed : "To Do"
    if (updater.checking)
      return { icon: "", text: "", color: foreground, tip: "Checking for updates…", busy: true }
    if (updater.checkError !== "")
      return { icon: "", text: "Can't check", color: urgent,
               tip: "Can't check for updates: " + updater.checkError + ". Click to try again." }
    if (updater.confirmedCurrent)
      return { icon: "", text: "Up to date", color: foreground, tip: installed + " is up to date." }
    return { icon: "", text: "", color: foreground,
             tip: (updater.installed !== "" ? installed + " is installed. " : "") + "Click to check for updates." }
  }

  signal closeRequested()
  signal added(string id)

  // The drop-down grows to fit the shortcuts box when the list or task is shorter.
  implicitHeight: Math.max(taskOpen ? detail.implicitHeight : layout.implicitHeight,
                           ui.shortcutsShown ? shortcuts.implicitHeight : 0)
  // The surface is set by now: the window opens on To do, the others on Focus.
  Component.onCompleted: ui = List.initial(surface)
  // Also when the open task is deleted elsewhere.
  onTaskOpenChanged: if (!taskOpen) send({ type: "taskClosed" })

  // Back to the list, ready to type a new task.
  function focusInput() {
    send({ type: "back" })
  }

  function submit() {
    send({ type: "submit" })
  }

  // Sends an event to the list rules and applies what they return. anchor:
  // the item the date picker hangs from, when the event opens it. Returns
  // whether the event did anything.
  function send(event, anchor) {
    if (!store) return false
    var result = List.step(ui, event, {
      surface: surface, rows: rows, typed: input.text, description: newDescription.text,
      taskOpen: taskOpen, store: store
    })
    if (!result) return false
    ui = result.state
    var effects = result.effects
    if (effects.hideTask) detail.hide()
    if (effects.focus === "new") (ui.describing ? newDescription : input).forceActiveFocus()
    else if (effects.focus === "title") input.forceActiveFocus()
    else if (effects.focus === "description") newDescription.forceActiveFocus()
    else if (effects.focus === "shortcuts") shortcuts.forceActiveFocus()
    if (effects.clearTyped) {
      input.text = ""
      newDescription.text = ""
    }
    if (effects.scrollTop) flick.contentY = 0
    if (effects.picker) openPicker(effects.picker, anchor)
    if (effects.openTask) detail.show(effects.openTask)
    if (effects.reveal) Qt.callLater(revealTask, effects.reveal)
    if (effects.close) closeRequested()
    // Last: quick add closes on it.
    if (effects.added) added(effects.added)
    return true
  }

  // A key in the title field (from "title", before the field handles it) or
  // passed on to the view. Returns whether it was a shortcut.
  function key(event, from) {
    var name = keyName(event)
    return name !== "" && send({ type: "key", name: name, from: from })
  }

  // The key as list.js names it; "" for a key that is no shortcut.
  function keyName(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
    var key = event.key
    if (key === Qt.Key_Escape) return "Escape"
    if (mods & Qt.ControlModifier) {
      if (key === Qt.Key_D) return "Ctrl+D"
      if (key === Qt.Key_F) return "Ctrl+F"
      if (key === Qt.Key_1) return "Ctrl+1"
      if (key === Qt.Key_2) return "Ctrl+2"
      if (key === Qt.Key_3) return "Ctrl+3"
      if (key === Qt.Key_Question || (key === Qt.Key_Slash && (mods & Qt.ShiftModifier))) return "Ctrl+?"
      return ""
    }
    if (mods !== 0) return ""
    if (key === Qt.Key_Up) return "Up"
    if (key === Qt.Key_Down) return "Down"
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return "Enter"
    return ""
  }

  // The list row of the task with this id, or null.
  function rowItemFor(id) {
    for (var i = 0; i < column.children.length; i++) {
      var child = column.children[i]
      if (child.item && child.item.row && child.item.row.key === id) return child
    }
    return null
  }

  // Scroll the list so the task with this id is visible, with the heading
  // above it when the task is above the visible part.
  function revealTask(id) {
    var child = rowItemFor(id)
    if (!child) return
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    if (child.y < flick.contentY)
      flick.contentY = Math.max(0, child.y - Style.space(30))
    else if (child.y + child.height > flick.contentY + flick.height)
      flick.contentY = Math.max(0, Math.min(maxY, child.y + child.height - flick.height + Style.spacing.lg))
  }

  // request: { target, current } from list.js.
  function openPicker(request, anchor) {
    picker.today = store.today
    picker.anchorItem = anchor || rowItemFor(request.target) || newDueButton
    picker.openFor(request.current)
  }

  function dueColor(state) {
    if (state === "overdue") return view.urgent
    if (state === "today") return view.accent
    return view.dim
  }

  Keys.onPressed: function(event) {
    if (view.key(event, newDescription.activeFocus ? "description" : "other")) event.accepted = true
  }

  ColumnLayout {
    id: layout
    anchors.fill: parent
    visible: !view.taskOpen
    spacing: Style.spacing.lg

    RowLayout {
      Layout.fillWidth: true
      visible: !view.quickAdd
      spacing: Style.spacing.sm

      Ui.Button {
        iconText: ""
        text: "Focus  " + (view.store ? view.store.focusCount : 0)
        bordered: true
        selected: view.ui.tab === "focus"
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: view.inWindow
          ? "Starred and due today (Ctrl+1)"
          : "Starred and due today. All tasks are in the window (Super+Shift+Alt+T)."
        onClicked: view.send({ type: "tab", tab: "focus" })
      }
      Ui.Button {
        visible: view.inWindow
        iconText: ""
        text: "To do  " + (view.store ? view.store.openCount : 0)
        bordered: true
        selected: view.ui.tab === "open"
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Ctrl+2"
        onClicked: view.send({ type: "tab", tab: "open" })
      }
      Ui.Button {
        visible: view.inWindow
        iconText: ""
        text: "Done  " + (view.store ? view.store.doneCount : 0)
        bordered: true
        selected: view.ui.tab === "done"
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Ctrl+3"
        onClicked: view.send({ type: "tab", tab: "done" })
      }
      Item { Layout.fillWidth: true }
      Ui.Button {
        visible: view.updateButton !== null
        iconText: view.updateButton ? view.updateButton.icon : ""
        iconSpinning: !!view.updateButton && view.updateButton.busy === true
        text: view.updateButton ? view.updateButton.text : ""
        foreground: view.updateButton ? view.updateButton.color : view.foreground
        fontFamily: view.fontFamily
        tooltipText: view.updateButton ? view.updateButton.tip : ""
        onClicked: view.updater.act()
      }
      Ui.Button {
        visible: view.ui.tab === "done" && view.store && view.store.doneCount > 0
        iconText: ""
        text: "Clear done"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.store.clearDone()
      }
      Ui.Button {
        iconText: ""
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Keyboard shortcuts (Ctrl+?)"
        onClicked: view.send({ type: "shortcuts" })
      }
      Ui.Button {
        visible: !view.inWindow
        iconText: ""
        text: "Esc"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.closeRequested()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.controlGap

      Ui.TextField {
        id: input
        Layout.fillWidth: true
        focus: true
        placeholderText: "Add a task, press Enter. Tab adds a description."
        foreground: view.foreground
        accent: view.accent
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        maximumLength: Tasks.MAX_TEXT_LENGTH
        onAccepted: view.submit()
        onTextEdited: view.send({ type: "typed" })
        // Before the field's own keys, so a shortcut never edits the text.
        Keys.onPressed: function(event) {
          if (view.key(event, "title")) event.accepted = true
        }
        Keys.onTabPressed: view.send({ type: "describe" })
      }
      Ui.Button {
        iconText: view.ui.newStarred ? "" : ""
        bordered: true
        selected: view.ui.newStarred
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Star (Ctrl+F)"
        onClicked: view.send({ type: "starNew" })
      }
      Ui.Button {
        id: newDueButton
        iconText: ""
        text: view.ui.newDue ? Tasks.dueInfo(view.ui.newDue, view.store.today).label : "Due"
        bordered: true
        selected: view.ui.newDue !== ""
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Due date (Ctrl+D)"
        onClicked: view.send({ type: "pickDue", id: "" }, newDueButton)
      }
      Ui.Button {
        iconText: ""
        text: "Add"
        bordered: true
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.submit()
      }
    }

    // Enter starts a new line here; Ctrl+Enter adds the task. Closes again
    // when left empty.
    ScrollView {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(Math.max(newDescription.implicitHeight, Style.space(64)), Style.space(160))
      visible: view.ui.describing

      TextBox {
        id: newDescription
        placeholderText: "Description. Ctrl+Enter adds the task."
        maximumLength: Tasks.MAX_DESCRIPTION_LENGTH
        foreground: view.foreground
        accent: view.accent
        font.family: view.fontFamily
        Keys.onReturnPressed: function(event) {
          if (event.modifiers & Qt.ControlModifier) view.submit()
          else event.accepted = false
        }
        Keys.onEnterPressed: function(event) {
          if (event.modifiers & Qt.ControlModifier) view.submit()
          else event.accepted = false
        }
        Keys.onBacktabPressed: input.forceActiveFocus()
        // Typing unselects the task, as in the title field.
        onTextChanged: if (activeFocus) view.send({ type: "typed" })
        onActiveFocusChanged: if (!activeFocus) view.send({ type: "descriptionLeft", empty: text === "" })
      }
    }

    Text {
      Layout.fillWidth: true
      visible: !!view.store && view.store.error !== ""
      textFormat: Text.PlainText
      text: view.store ? view.store.error : ""
      wrapMode: Text.Wrap
      color: view.urgent
      font.family: view.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Flickable {
      id: flick
      visible: !view.quickAdd
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: column.implicitHeight
      Layout.minimumHeight: Style.space(80)
      clip: true
      contentWidth: width
      contentHeight: column.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { id: scrollBar; policy: ScrollBar.AsNeeded }

      readonly property bool scrolls: contentHeight > height
      readonly property real scrollStrip: scrolls ? scrollBar.width + Style.spacing.xs : 0

      Column {
        id: column
        // When the list scrolls, the scroll bar gets its own strip instead of
        // covering the stars and bins. Mirrored, it is on the left.
        x: LayoutMirroring.enabled ? flick.scrollStrip : 0
        width: flick.width - flick.scrollStrip
        spacing: Style.spacing.xxs

        Repeater {
          model: view.rows
          delegate: Loader {
            required property var modelData
            width: column.width
            sourceComponent: modelData.kind === "header" ? headerRow : taskRow
            onLoaded: item.row = modelData
          }
        }
      }

      // In the list's visible area: the content is empty, so has no height.
      Text {
        parent: flick
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: view.rows.length === 0 && !!view.store && view.store.ready
        textFormat: Text.PlainText
        text: view.ui.tab === "focus" ? "Nothing starred or due today."
          : view.ui.tab === "open" ? "Nothing to do." : "Nothing done yet."
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.subtitle
      }
    }
  }

  Component {
    id: headerRow

    Item {
      id: header
      property var row: null
      readonly property bool alert: !!row && row.key === "overdue"
      height: Style.space(30)

      RowLayout {
        anchors.fill: parent
        anchors.topMargin: Style.spacing.md
        spacing: Style.spacing.sm

        Text {
          visible: !!header.row && header.row.key === "starred"
          textFormat: Text.PlainText
          text: ""
          color: view.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: header.row ? header.row.title : ""
          color: header.alert ? view.urgent : view.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: header.row ? String(header.row.count) : ""
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          height: 1
          color: Util.alpha(view.foreground, 0.15)
        }
      }
    }
  }

  Component {
    id: taskRow

    Rectangle {
      id: rowItem
      property var row: null
      readonly property var task: row ? row.task : null
      readonly property bool done: !!task && task.doneAt !== null
      readonly property var due: task ? Tasks.dueInfo(task.due, view.store.today) : ({ label: "", state: "" })
      readonly property bool isSelected: !!task && task.id === view.ui.selectedId

      height: Math.max(Style.space(38), content.implicitHeight + Style.spacing.md * 2)
      radius: Math.max(2, Style.cornerRadius / 2)
      color: isSelected ? Util.alpha(view.accent, 0.12) : (hover.hovered ? view.hoverFill : "transparent")
      border.width: isSelected ? 1 : 0
      border.color: view.accent

      HoverHandler { id: hover }

      // A click on the row, not on one of its buttons, opens the task. It
      // also selects it, so Ctrl+D and Ctrl+F act on it after Back.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: view.send({ type: "open", id: rowItem.task.id })
      }

      RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.rightMargin: Style.spacing.md
        spacing: Style.spacing.lg

        Rectangle {
          id: checkbox
          Layout.alignment: Qt.AlignVCenter
          width: Style.space(18)
          height: Style.space(18)
          radius: Math.max(2, Style.cornerRadius / 3)
          color: rowItem.done ? view.accent : (checkMouse.containsMouse ? Util.alpha(view.accent, 0.2) : "transparent")
          border.width: 1
          border.color: rowItem.done ? view.accent : (checkMouse.containsMouse ? view.accent : view.dim)

          Text {
            anchors.centerIn: parent
            visible: rowItem.done
            textFormat: Text.PlainText
            text: ""
            color: view.background
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: checkMouse
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.store.setDone(rowItem.task.id, !rowItem.done)
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.spacing.xxs

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: rowItem.task ? rowItem.task.text : ""
            wrapMode: Text.Wrap
            color: rowItem.done ? view.dim : view.foreground
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
            font.strikeout: rowItem.done
          }
          Text {
            visible: rowItem.done
            textFormat: Text.PlainText
            text: rowItem.done ? "Done at " + Tasks.timeOfDay(rowItem.task.doneAt) : ""
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Due date: click to change. Open tasks without a date show the
        // calendar icon on hover.
        Rectangle {
          id: dueChip
          Layout.alignment: Qt.AlignVCenter
          visible: rowItem.due.label !== "" || (!rowItem.done && hover.hovered)
          implicitWidth: dueText.implicitWidth + Style.spacing.md * 2
          implicitHeight: dueText.implicitHeight + Style.spacing.xs * 2
          radius: Math.max(2, Style.cornerRadius / 2)
          color: dueMouse.containsMouse ? Util.alpha(view.accent, 0.15) : "transparent"
          border.width: !rowItem.done && (rowItem.due.state === "overdue" || rowItem.due.state === "today") ? 1 : 0
          border.color: view.dueColor(rowItem.due.state)

          Text {
            id: dueText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: rowItem.due.label !== "" ? " " + rowItem.due.label : ""
            color: rowItem.done ? view.dim : view.dueColor(rowItem.due.state)
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: dueMouse
            anchors.fill: parent
            enabled: !rowItem.done
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.send({ type: "pickDue", id: rowItem.task.id }, dueChip)
          }
        }

        Text {
          id: star
          Layout.alignment: Qt.AlignVCenter
          visible: !rowItem.done || rowItem.task.starred
          textFormat: Text.PlainText
          text: rowItem.task && rowItem.task.starred ? "" : ""
          color: rowItem.task && rowItem.task.starred ? view.accent
            : (starMouse.containsMouse ? view.foreground : Util.alpha(view.foreground, hover.hovered ? 0.55 : 0.25))
          font.family: view.fontFamily
          font.pixelSize: Style.font.subtitle

          MouseArea {
            id: starMouse
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            enabled: !rowItem.done
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.store.toggleStar(rowItem.task.id)
          }
        }

        Text {
          id: trash
          Layout.alignment: Qt.AlignVCenter
          opacity: hover.hovered ? 1 : 0
          textFormat: Text.PlainText
          text: ""
          color: trashMouse.containsMouse ? view.urgent : view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.body

          MouseArea {
            id: trashMouse
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.store.remove(rowItem.task.id)
          }
        }
      }
    }
  }

  TaskDetail {
    id: detail
    anchors.fill: parent
    visible: view.taskOpen
    store: view.store
    foreground: view.foreground
    accent: view.accent
    urgent: view.urgent
    fontFamily: view.fontFamily
    onBackRequested: view.focusInput()
  }

  Shortcuts {
    id: shortcuts
    anchors.fill: parent
    z: 1
    visible: view.ui.shortcutsShown
    surface: view.surface
    foreground: view.foreground
    background: view.background
    accent: view.accent
    border: view.border
    fontFamily: view.fontFamily
    onCloseRequested: view.focusInput()
  }

  DatePicker {
    id: picker
    parent: view
    boundsItem: view.popupBounds
    foreground: view.foreground
    surface: view.background
    accent: view.accent
    border: view.border
    hoverFill: view.hoverFill
    fontFamily: view.fontFamily
    onPicked: function(due) {
      view.send({ type: "picked", due: due })
    }
    onClosed: view.focusInput()
  }
}
