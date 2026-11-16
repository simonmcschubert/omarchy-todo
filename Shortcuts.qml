import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// The keyboard shortcuts box (Ctrl+?), over the task list. Esc, Ctrl+?, or a
// click outside the box closes it.
FocusScope {
  id: box

  // "window" or "dropdown" (TaskView). The drop-down shows only the Focus
  // tab, so no keys switch tabs, and Esc closes it.
  property string surface: "window"
  readonly property bool inWindow: surface === "window"

  property color foreground: Commons.Color.menu.text
  property color background: Commons.Color.menu.background
  property color accent: Commons.Color.accent
  property color border: Commons.Color.menu.border
  property string fontFamily: Style.font.family
  readonly property color dim: Util.alpha(foreground, 0.55)

  // Width of the widest keys column, so the descriptions line up.
  property real keysWidth: 0
  readonly property int padding: Style.spacing.popupPadding

  readonly property var sections: [
    { title: "Tasks", rows: [
      { keys: ["Enter"], text: "Add the typed task" },
      { keys: ["Tab"], text: "Add a description to it" },
      { keys: ["Ctrl+Enter"], text: "Add the task from its description" },
      { keys: ["", ""], text: "Select a task in the list" },
      { keys: ["Enter"], text: "Open the selected task (nothing typed)" },
      { keys: ["Ctrl+D"], text: "Due date of the selected or typed task" },
      { keys: ["Ctrl+F"], text: "Star or unstar the selected or typed task" }
    ].concat(inWindow ? [
      { keys: ["Ctrl+1"], text: "Focus: starred and due today" },
      { keys: ["Ctrl+2"], text: "To do" },
      { keys: ["Ctrl+3"], text: "Done" }
    ] : []).concat([
      { keys: ["Ctrl+?"], text: "These shortcuts" },
      { keys: ["Esc"], text: inWindow ? "Back from a task, or unselect it" : "Back from a task, unselect it, or close" }
    ]).concat(inWindow ? [{ keys: ["Super+W"], text: "Close the window" }] : []) },
    { title: "Date picker", rows: [
      { keys: ["", ""], text: "Day before or after" },
      { keys: ["", ""], text: "Week before or after" },
      { keys: ["PgUp", "PgDn"], text: "Month before or after" },
      { keys: ["Enter"], text: "Pick the highlighted day" },
      { keys: ["1", "2", "3"], text: "Today, Tomorrow, Next Mon" },
      { keys: ["4", "5", "6"], text: "In a week, In a month, No date" },
      { keys: ["Esc"], text: "Close without changing" }
    ] },
    { title: "Anywhere", rows: [
      { keys: ["Super+Alt+T"], text: "Drop-down on and off" },
      { keys: ["Super+Alt+N"], text: "Quick add on and off" },
      { keys: ["Super+Shift+Alt+T"], text: "Window" }
    ] }
  ]

  signal closeRequested()

  implicitHeight: content.implicitHeight + padding * 2

  // Dims the list; a click on it closes the box.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(box.background, 0.8)

    MouseArea {
      anchors.fill: parent
      onClicked: box.closeRequested()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(460))
    height: Math.min(parent.height, content.implicitHeight + box.padding * 2)
    color: box.background
    border.color: box.border
    border.width: Math.max(1, Style.normalBorderWidth)
    radius: Style.cornerRadius

    // Keep clicks inside the box from closing it.
    MouseArea { anchors.fill: parent }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: box.padding
      clip: true
      contentWidth: width
      contentHeight: content.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      ColumnLayout {
        id: content
        width: flick.width
        spacing: Style.spacing.md

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Keyboard shortcuts"
            color: box.foreground
            font.family: box.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Ui.Button {
            iconText: ""
            text: "Esc"
            foreground: box.foreground
            fontFamily: box.fontFamily
            onClicked: box.closeRequested()
          }
        }

        Repeater {
          model: box.sections
          delegate: ColumnLayout {
            id: section
            required property var modelData
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: section.modelData.title
              color: box.accent
              font.family: box.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Repeater {
              model: section.modelData.rows
              delegate: RowLayout {
                id: shortcut
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.spacing.xl

                Row {
                  id: keys
                  Layout.preferredWidth: box.keysWidth
                  Layout.alignment: Qt.AlignTop
                  spacing: Style.spacing.xs
                  onImplicitWidthChanged: box.keysWidth = Math.max(box.keysWidth, implicitWidth)

                  Repeater {
                    model: shortcut.modelData.keys
                    delegate: Rectangle {
                      required property string modelData
                      implicitWidth: keyText.implicitWidth + Style.spacing.md * 2
                      implicitHeight: keyText.implicitHeight + Style.spacing.xxs * 2
                      radius: Math.max(2, Style.cornerRadius / 2)
                      color: Util.alpha(box.foreground, 0.06)
                      border.width: 1
                      border.color: Util.alpha(box.foreground, 0.25)

                      Text {
                        id: keyText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: parent.modelData
                        color: box.foreground
                        font.family: box.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: shortcut.modelData.text
                  wrapMode: Text.Wrap
                  color: box.dim
                  font.family: box.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
