import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks

// One task opened from the list: its title and its plain-text description,
// both edited in place. Changes save shortly after typing stops and when a
// field loses focus. An emptied title is not saved; it comes back on leaving
// the field.
FocusScope {
  id: detail

  property var store: null
  property string taskId: ""
  readonly property var task: store && taskId !== "" ? Tasks.findTask(store.tasks, taskId) : null
  readonly property bool done: !!task && task.doneAt !== null

  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  readonly property color dim: Util.alpha(foreground, 0.55)

  // Typed in since the last save. Only these fields are saved, so a field
  // nobody typed in never overwrites a change from elsewhere.
  property bool titleEdited: false
  property bool descriptionEdited: false

  signal backRequested()

  implicitHeight: layout.implicitHeight

  // Shows the task with this id, with the cursor at the start of its description.
  function show(id) {
    save()
    forgetTyping()
    taskId = id
    titleField.text = task ? task.text : ""
    descriptionField.text = task ? task.description : ""
    descriptionField.cursorPosition = 0
    descriptionField.forceActiveFocus()
  }

  function hide() {
    save()
    forgetTyping()
    taskId = ""
  }

  // Saves now instead of after the typing pause. While the store refuses
  // changes (it shows an error), the typed fields stay marked: leaving one
  // keeps what was typed, and a later save writes it once the store can.
  function save() {
    saveTimer.stop()
    if (!task || !(titleEdited || descriptionEdited)) return
    store.edit(taskId, titleEdited ? titleField.text : task.text,
               descriptionEdited ? descriptionField.text : task.description)
    if (store.error === "") forgetTyping()
  }

  // Leaving the task drops typing the store refused.
  function forgetTyping() {
    titleEdited = false
    descriptionEdited = false
  }

  // Shows what is stored in the fields not being edited and not waiting to
  // be saved.
  function refresh() {
    if (!task) return
    if (!titleField.activeFocus && !titleEdited && titleField.text !== task.text) titleField.text = task.text
    if (!descriptionField.activeFocus && !descriptionEdited && descriptionField.text !== task.description)
      descriptionField.text = task.description
  }

  function leaveField() {
    save()
    refresh()
  }

  // A task deleted elsewhere closes here. Changes from elsewhere (the other
  // view, the file) show in the fields not being edited.
  onTaskChanged: {
    if (task) refresh()
    else Qt.callLater(forgetDeleted)
  }

  // Not in onTaskChanged: changing taskId there would be a binding loop.
  function forgetDeleted() {
    if (!task) taskId = ""
  }

  Timer {
    id: saveTimer
    interval: 500
    onTriggered: detail.save()
  }

  ColumnLayout {
    id: layout
    anchors.fill: parent
    spacing: Style.spacing.lg

    RowLayout {
      Layout.fillWidth: true

      Ui.Button {
        iconText: ""
        text: "Back"
        foreground: detail.foreground
        fontFamily: detail.fontFamily
        tooltipText: "Esc"
        onClicked: detail.backRequested()
      }
      Item { Layout.fillWidth: true }
    }

    // The title is one line: Enter and Tab go on to the description.
    TextBox {
      id: titleField
      Layout.fillWidth: true
      quiet: true
      placeholderText: "Title"
      maximumLength: Tasks.MAX_TEXT_LENGTH
      foreground: detail.done ? detail.dim : detail.foreground
      accent: detail.accent
      font.family: detail.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
      font.strikeout: detail.done
      Keys.onReturnPressed: descriptionField.forceActiveFocus()
      Keys.onEnterPressed: descriptionField.forceActiveFocus()
      Keys.onTabPressed: descriptionField.forceActiveFocus()
      onTextChanged: if (activeFocus) {
        detail.titleEdited = true
        saveTimer.restart()
      }
      onActiveFocusChanged: if (!activeFocus) detail.leaveField()
    }

    Text {
      Layout.fillWidth: true
      visible: !!detail.store && detail.store.error !== ""
      textFormat: Text.PlainText
      text: detail.store ? detail.store.error : ""
      wrapMode: Text.Wrap
      color: detail.urgent
      font.family: detail.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    ScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: Math.max(Style.space(180), descriptionField.implicitHeight)
      Layout.minimumHeight: Style.space(80)

      TextBox {
        id: descriptionField
        placeholderText: "Add a description"
        maximumLength: Tasks.MAX_DESCRIPTION_LENGTH
        foreground: detail.foreground
        accent: detail.accent
        font.family: detail.fontFamily
        Keys.onBacktabPressed: titleField.forceActiveFocus()
        onTextChanged: if (activeFocus) {
          detail.descriptionEdited = true
          saveTimer.restart()
        }
        onActiveFocusChanged: if (!activeFocus) detail.leaveField()
      }
    }
  }
}
