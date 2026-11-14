import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks

// The task list UI, shown in both the drop-down and the window.
FocusScope {
  id: view

  property var store: null
  property bool compact: false
  property string tab: "open"
  property string newDue: ""
  property string pickerTarget: ""

  property color foreground: Commons.Color.menu.text
  property color background: Commons.Color.menu.background
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property color border: Commons.Color.menu.border
  property color hoverFill: Commons.Color.menu.selectedBackground
  property string fontFamily: Style.font.family
  readonly property color dim: Util.alpha(foreground, 0.55)

  readonly property var rows: !store ? [] : (tab === "open" ? store.openRows : store.doneRows)

  signal closeRequested()

  implicitHeight: layout.implicitHeight
  onTabChanged: flick.contentY = 0

  function focusInput() {
    input.forceActiveFocus()
  }

  function submit() {
    if (!store || input.text.trim() === "") return
    var id = store.add(input.text, newDue)
    if (id === "") return
    input.text = ""
    newDue = ""
    tab = "open"
    Qt.callLater(revealTask, id)
  }

  // Scroll the list so the task with this id is visible.
  function revealTask(id) {
    for (var i = 0; i < column.children.length; i++) {
      var child = column.children[i]
      if (!child.item || !child.item.row || child.item.row.key !== id) continue
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (child.y < flick.contentY || child.y + child.height > flick.contentY + flick.height)
        flick.contentY = Math.max(0, Math.min(maxY, child.y + child.height - flick.height + Style.spacing.lg))
      return
    }
  }

  function openPicker(target, current, anchor) {
    pickerTarget = target
    picker.today = store.today
    var p = anchor.mapToItem(view, 0, 0)
    var w = picker.implicitWidth
    var h = picker.implicitHeight
    picker.x = Math.max(0, Math.min(p.x + anchor.width - w, view.width - w))
    var below = p.y + anchor.height + Style.spacing.sm
    picker.y = below + h <= view.height ? below : Math.max(0, p.y - h - Style.spacing.sm)
    picker.openFor(current)
  }

  function dueColor(state) {
    if (state === "overdue") return view.urgent
    if (state === "today") return view.accent
    return view.dim
  }

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape) {
      view.closeRequested()
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_1) {
      view.tab = "open"
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_2) {
      view.tab = "done"
      event.accepted = true
    }
  }

  ColumnLayout {
    id: layout
    anchors.fill: parent
    spacing: Style.spacing.lg

    RowLayout {
      Layout.fillWidth: true
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
        visible: view.tab === "done" && view.store && view.store.doneCount > 0
        iconText: ""
        text: "Clear done"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: view.store.clearDone()
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
        placeholderText: "Add a task, press Enter"
        foreground: view.foreground
        accent: view.accent
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        maximumLength: Tasks.MAX_TEXT_LENGTH
        onAccepted: view.submit()
      }
      Ui.Button {
        id: newDueButton
        iconText: ""
        text: view.newDue ? Tasks.dueInfo(view.newDue, view.store.today).label : "Due"
        bordered: true
        selected: view.newDue !== ""
        foreground: view.foreground
        fontFamily: view.fontFamily
        tooltipText: "Due date"
        onClicked: view.openPicker("", view.newDue, newDueButton)
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
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: column.implicitHeight
      Layout.minimumHeight: Style.space(80)
      clip: true
      contentWidth: width
      contentHeight: column.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
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

      Text {
        anchors.centerIn: parent
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

      height: Math.max(Style.space(38), content.implicitHeight + Style.spacing.md * 2)
      radius: Math.max(2, Style.cornerRadius / 2)
      color: hover.hovered ? view.hoverFill : "transparent"

      HoverHandler { id: hover }

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

  DatePicker {
    id: picker
    parent: view
    foreground: view.foreground
    surface: view.background
    accent: view.accent
    border: view.border
    hoverFill: view.hoverFill
    fontFamily: view.fontFamily
    onPicked: function(due) {
      if (view.pickerTarget === "") view.newDue = due
      else view.store.setDue(view.pickerTarget, due)
    }
    onClosed: view.focusInput()
  }
}
