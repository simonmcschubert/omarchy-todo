import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks

// The task list UI, shown in both the drop-down and the window. With addOnly
// it is just the field for a new task: no tabs and no list (quick add).
FocusScope {
  id: view

  property var store: null
  property var updater: null
  property bool compact: false
  property bool addOnly: false
  property string tab: "open"
  property string newDue: ""
  property bool newStarred: false
  // The task Ctrl+D and Ctrl+F act on. Arrow keys or a click select it,
  // typing or Esc unselects it; the typed task is used while none is.
  property string selectedId: ""
  // The new task's description field is open (Tab in the input).
  property bool describing: false
  property string pickerTarget: ""
  // Where the date picker may open. Unset, it is the whole window.
  property Item popupBounds: null
  property bool shortcutsShown: false

  property color foreground: Commons.Color.menu.text
  property color background: Commons.Color.menu.background
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property color border: Commons.Color.menu.border
  property color hoverFill: Commons.Color.menu.selectedBackground
  property string fontFamily: Style.font.family
  readonly property color dim: Util.alpha(foreground, 0.55)

  readonly property var rows: !store ? [] : (tab === "open" ? store.openRows : store.doneRows)
  // The selected task while it is in the list shown, else null. Quick add
  // shows no list, so nothing is selected there.
  readonly property var selectedTask: {
    if (addOnly) return null
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "task" && rows[i].key === selectedId) return rows[i].task
    return null
  }
  // A task opened from the list replaces the list until Back or Esc.
  readonly property bool taskOpen: detail.task !== null

  // The update button for each status of the updater (Updater.qml); null
  // hides it.
  readonly property var updateButton: {
    var name = updater ? "To Do " + updater.version : ""
    switch (updater ? updater.status : "") {
    case "available":
      return { icon: "", text: "Update", tip: name + " is available. Click to download it." }
    case "downloading":
      return { icon: "", text: "Downloading", tip: "Downloading " + name + ".", busy: true }
    case "downloaded":
      return { icon: "", text: "Restart to update",
               tip: name + " is downloaded. Click to restart the Omarchy shell with it. Your tasks stay as they are." }
    case "installing":
      return { icon: "", text: "Updating", tip: "Installing " + name + " and restarting the shell.", busy: true }
    case "failed":
      return { icon: "", text: "Update failed", tip: "Can't download " + name + ". Click to try again.", failed: true }
    }
    return null
  }

  signal closeRequested()
  signal added(string id)

  // The drop-down grows to fit the shortcuts box when the list or task is shorter.
  implicitHeight: Math.max(taskOpen ? detail.implicitHeight : layout.implicitHeight,
                           shortcutsShown ? shortcuts.implicitHeight : 0)
  onTabChanged: {
    flick.contentY = 0
    selectedId = ""
  }
  // Also when the open task is deleted elsewhere.
  onTaskOpenChanged: if (!taskOpen) focusNewTask()

  // Back to the list, ready to type a new task.
  function focusInput() {
    shortcutsShown = false
    detail.hide()
    focusNewTask()
  }

  // The new task's field: its description while that is open, so Ctrl+D or
  // Ctrl+F there does not move the typing to the title.
  function focusNewTask() {
    (describing ? newDescription : input).forceActiveFocus()
  }

  function openTask(id) {
    selectedId = id
    detail.show(id)
  }

  function toggleShortcuts() {
    if (shortcutsShown) {
      focusInput()
    } else {
      shortcutsShown = true
      shortcuts.forceActiveFocus()
    }
  }

  function pickNewDue() {
    shortcutsShown = false
    openPicker("", newDue, newDueButton)
  }

  // Ctrl+D: the selected task's due date, or the typed task's. Done tasks
  // keep theirs, as with the mouse.
  function pickDue() {
    var task = selectedTask
    if (!task) pickNewDue()
    else if (task.doneAt === null) openPicker(task.id, task.due || "", rowItemFor(task.id) || newDueButton)
  }

  // Ctrl+F: star or unstar the selected task, or the typed task.
  function starTask() {
    var task = selectedTask
    if (!task) {
      newStarred = !newStarred
    } else if (task.doneAt === null) {
      store.toggleStar(task.id)
      Qt.callLater(revealTask, task.id)
    }
  }

  // Up and Down select the task above or below. Up from the first task
  // goes back to the typed task.
  function moveSelection(delta) {
    var ids = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "task") ids.push(rows[i].key)
    var index = selectedTask ? ids.indexOf(selectedId) + delta : (delta > 0 ? 0 : -1)
    if (index < 0) {
      selectedId = ""
    } else if (index < ids.length) {
      selectedId = ids[index]
      revealTask(selectedId)
    }
  }

  // Shortcuts that work anywhere in the view, also while typing a task.
  // Returns whether the key was one of them.
  function handleKey(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
    var ctrl = (mods & Qt.ControlModifier) !== 0
    var key = event.key
    if (key === Qt.Key_Escape) {
      if (shortcutsShown || taskOpen) focusInput()
      else if (selectedTask) selectedId = ""
      else closeRequested()
    } else if (ctrl && key === Qt.Key_D) {
      focusInput()
      pickDue()
    } else if (ctrl && key === Qt.Key_F) {
      focusInput()
      starTask()
    } else if (addOnly) {
      // Quick add is only the field: the rest needs the list.
      return false
    } else if (ctrl && (key === Qt.Key_Question || (key === Qt.Key_Slash && (mods & Qt.ShiftModifier)))) {
      toggleShortcuts()
    } else if (ctrl && key === Qt.Key_1) {
      focusInput()
      tab = "open"
    } else if (ctrl && key === Qt.Key_2) {
      focusInput()
      tab = "done"
    } else if (mods === 0 && !shortcutsShown && !taskOpen && !newDescription.activeFocus
               && (key === Qt.Key_Down || key === Qt.Key_Up)) {
      moveSelection(key === Qt.Key_Down ? 1 : -1)
    } else {
      return false
    }
    return true
  }

  // Enter in the field with nothing typed opens the selected task. Only
  // there: after adding a typed task, the field passes Enter on to the view.
  function openOnEnter(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
    if (mods !== 0 || (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)) return false
    if (!selectedTask || shortcutsShown || taskOpen || input.text.trim() !== "") return false
    openTask(selectedTask.id)
    return true
  }

  function submit() {
    if (!store || input.text.trim() === "") return
    var id = store.add(input.text, newDescription.text, newDue, newStarred)
    if (id === "") return
    input.forceActiveFocus()
    input.text = ""
    newDescription.text = ""
    describing = false
    newDue = ""
    newStarred = false
    if (!addOnly) {
      tab = "open"
      Qt.callLater(revealTask, id)
    }
    // Last: quick add closes on it, which turns addOnly off.
    added(id)
  }

  function describeNew() {
    describing = true
    newDescription.forceActiveFocus()
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

  function openPicker(target, current, anchor) {
    pickerTarget = target
    picker.today = store.today
    picker.anchorItem = anchor
    picker.openFor(current)
  }

  function dueColor(state) {
    if (state === "overdue") return view.urgent
    if (state === "today") return view.accent
    return view.dim
  }

  Keys.onPressed: function(event) {
    if (view.handleKey(event)) event.accepted = true
  }

  ColumnLayout {
    id: layout
    anchors.fill: parent
    visible: !view.taskOpen
    spacing: Style.spacing.lg

    RowLayout {
      Layout.fillWidth: true
      visible: !view.addOnly
      spacing: Style.spacing.sm

      Ui.Button {
        iconText: ""
        text: "To do  " + (view.store ? view.store.openCount : 0)
        bordered: true
        selected: view.tab === "open"
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Ctrl+1"
        onClicked: view.tab = "open"
      }
      Ui.Button {
        iconText: ""
        text: "Done  " + (view.store ? view.store.doneCount : 0)
        bordered: true
        selected: view.tab === "done"
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Ctrl+2"
        onClicked: view.tab = "done"
      }
      Item { Layout.fillWidth: true }
      Ui.Button {
        visible: view.updateButton !== null
        iconText: view.updateButton ? view.updateButton.icon : ""
        iconSpinning: !!view.updateButton && view.updateButton.busy === true
        text: view.updateButton ? view.updateButton.text : ""
        foreground: view.updateButton && view.updateButton.failed ? view.urgent : view.accent
        fontFamily: view.fontFamily
        tooltipText: view.updateButton ? view.updateButton.tip : ""
        onClicked: view.updater.act()
      }
      Ui.Button {
        visible: view.tab === "done" && view.store && view.store.doneCount > 0
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
        onClicked: view.toggleShortcuts()
      }
      Ui.Button {
        visible: view.compact
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
        onTextEdited: view.selectedId = ""
        // Before the field's own keys, so a shortcut never edits the text.
        Keys.onPressed: function(event) {
          if (view.handleKey(event) || view.openOnEnter(event)) event.accepted = true
        }
        Keys.onTabPressed: view.describeNew()
      }
      Ui.Button {
        iconText: view.newStarred ? "" : ""
        bordered: true
        selected: view.newStarred
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Star (Ctrl+F)"
        onClicked: view.newStarred = !view.newStarred
      }
      Ui.Button {
        id: newDueButton
        iconText: ""
        text: view.newDue ? Tasks.dueInfo(view.newDue, view.store.today).label : "Due"
        bordered: true
        selected: view.newDue !== ""
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Due date (Ctrl+D)"
        onClicked: view.pickNewDue()
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
      visible: view.describing

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
        onActiveFocusChanged: if (!activeFocus && text === "") view.describing = false
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
      visible: !view.addOnly
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
        text: view.tab === "open" ? "Nothing to do." : "Nothing done yet."
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
      readonly property bool isSelected: !!task && task.id === view.selectedId

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
        onClicked: view.openTask(rowItem.task.id)
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
            onClicked: view.openPicker(rowItem.task.id, rowItem.task.due || "", dueChip)
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
    visible: view.shortcutsShown
    compact: view.compact
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
      var target = view.pickerTarget
      if (target === "") {
        view.newDue = due
      } else {
        view.store.setDue(target, due)
        // The task may move to another section; keep the selection in view.
        if (target === view.selectedId) Qt.callLater(view.revealTask, target)
      }
    }
    onClosed: view.focusInput()
  }
}
