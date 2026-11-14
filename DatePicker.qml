import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks

// Due date picker: quick choices and a month calendar. Emits picked("") for
// "No date".
Popup {
  id: picker

  property string today: Tasks.dateKey(new Date())
  property string selected: ""
  // Follows Omarchy's language setting (Qt uses 7 for Sunday).
  property int firstDayOfWeek: Qt.locale(Commons.I18n.formatLocale).firstDayOfWeek % 7
  property int viewYear: 2026
  property int viewMonth: 0

  property color foreground: Commons.Color.menu.text
  property color surface: Commons.Color.menu.background
  property color accent: Commons.Color.accent
  property color border: Commons.Color.menu.border
  property color hoverFill: Commons.Color.menu.selectedBackground
  property string fontFamily: Style.font.family

  readonly property var cells: Tasks.monthGrid(viewYear, viewMonth, firstDayOfWeek)
  readonly property int cellSize: Style.space(30)

  signal picked(string due)

  function openFor(current) {
    selected = current || ""
    var base = Tasks.parseDateKey(selected || today) || new Date()
    viewYear = base.getFullYear()
    viewMonth = base.getMonth()
    open()
  }

  function choose(key) {
    picked(key)
    close()
  }

  function shiftMonth(delta) {
    var d = new Date(viewYear, viewMonth + delta, 1)
    viewYear = d.getFullYear()
    viewMonth = d.getMonth()
  }

  modal: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  padding: Style.spacing.popupPadding

  background: Rectangle {
    color: picker.surface
    border.color: picker.border
    border.width: Math.max(1, Style.normalBorderWidth)
    radius: Style.cornerRadius
  }

  contentItem: ColumnLayout {
    spacing: Style.spacing.lg

    GridLayout {
      columns: 3
      columnSpacing: Style.spacing.sm
      rowSpacing: Style.spacing.sm
      Layout.fillWidth: true

      Repeater {
        model: [
          { label: "Today", key: picker.today },
          { label: "Tomorrow", key: Tasks.addDays(picker.today, 1) },
          { label: "Next Mon", key: Tasks.nextWeekday(picker.today, 1) },
          { label: "In a week", key: Tasks.addDays(picker.today, 7) },
          { label: "In a month", key: Tasks.addMonths(picker.today, 1) },
          { label: "No date", key: "" }
        ]
        delegate: Ui.Button {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.label
          bordered: true
          selected: picker.selected === modelData.key
          foreground: picker.foreground
          fontFamily: picker.fontFamily
          onClicked: picker.choose(modelData.key)
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Ui.Button {
        iconText: ""
        foreground: picker.foreground
        tooltipText: "Previous month"
        onClicked: picker.shiftMonth(-1)
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Tasks.monthTitle(picker.viewYear, picker.viewMonth)
        color: picker.foreground
        font.family: picker.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Ui.Button {
        iconText: ""
        foreground: picker.foreground
        tooltipText: "Next month"
        onClicked: picker.shiftMonth(1)
      }
    }

    Grid {
      columns: 7
      spacing: Style.spacing.xxs
      Layout.alignment: Qt.AlignHCenter

      Repeater {
        model: Tasks.weekdayHeaders(picker.firstDayOfWeek)
        delegate: Text {
          required property var modelData
          width: picker.cellSize
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData
          color: Util.alpha(picker.foreground, 0.55)
          font.family: picker.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Repeater {
        model: picker.cells
        delegate: Rectangle {
          id: cell
          required property var modelData
          readonly property bool isSelected: modelData.key === picker.selected
          readonly property bool isToday: modelData.key === picker.today
          readonly property bool isPast: Tasks.daysBetween(picker.today, modelData.key) < 0
          width: picker.cellSize
          height: picker.cellSize
          radius: Math.max(2, Style.cornerRadius / 2)
          color: isSelected ? picker.accent : (cellMouse.containsMouse ? picker.hoverFill : "transparent")
          border.width: isToday && !isSelected ? 1 : 0
          border.color: picker.accent

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: cell.modelData.day
            color: cell.isSelected ? picker.surface
              : Util.alpha(picker.foreground, cell.modelData.inMonth ? (cell.isPast ? 0.45 : 1) : 0.3)
            font.family: picker.fontFamily
            font.pixelSize: Style.font.body
            font.bold: cell.isToday
          }

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: picker.choose(cell.modelData.key)
          }
        }
      }
    }
  }
}
