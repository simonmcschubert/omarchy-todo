import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "tasks.js" as Tasks

// Due date picker: quick choices and a month calendar. Emits picked("") for
// "No date".
//
// It opens below `anchorItem`, or above it when there is more room there, and
// always stays inside `boundsItem` (the whole window when unset). When even
// that does not fit, the day cells shrink.
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

  property Item anchorItem: null
  property Item boundsItem: null
  // Both in the parent's coordinates, measured by place().
  property rect anchorRect: Qt.rect(0, 0, 0, 0)
  property rect boundsRect: Qt.rect(0, 0, 0, 0)
  readonly property int gap: Style.spacing.sm

  readonly property var cells: Tasks.monthGrid(viewYear, viewMonth, firstDayOfWeek)
  readonly property int naturalCell: Style.space(30)
  readonly property int minimumCell: Style.space(18)
  // Everything but the day cells, so the cells alone can shrink to fit.
  readonly property real chromeWidth: leftPadding + rightPadding + 6 * days.spacing
  readonly property real chromeHeight: topPadding + bottomPadding + quickChoices.implicitHeight
    + monthRow.implicitHeight + weekdayHeight + 2 * content.spacing + 6 * days.spacing
  readonly property int weekdayHeight: Math.ceil(captionMetrics.height)

  readonly property real roomBelow: boundsRect.y + boundsRect.height - (anchorRect.y + anchorRect.height + gap)
  readonly property real roomAbove: anchorRect.y - gap - boundsRect.y
  readonly property bool opensBelow: {
    var natural = chromeHeight + 6 * naturalCell
    return natural <= roomBelow || (natural > roomAbove && roomBelow >= roomAbove)
  }
  readonly property int cellSize: Math.max(minimumCell, Math.min(naturalCell,
    Math.floor(((opensBelow ? roomBelow : roomAbove) - chromeHeight) / 6),
    Math.floor((boundsRect.width - chromeWidth) / 7)))

  signal picked(string due)

  function clamp(value, low, high) {
    return Math.max(low, Math.min(value, high))
  }

  // Measures where the anchor and the bounds are now. Positions come from
  // the bindings below, so they follow the picker's real size.
  function place() {
    var host = parent
    if (!host) return
    var bounds = boundsItem
    if (!bounds) {
      bounds = host
      while (bounds.parent) bounds = bounds.parent
    }
    var b = bounds.mapToItem(host, 0, 0)
    boundsRect = Qt.rect(b.x + gap, b.y + gap,
                         Math.max(0, bounds.width - gap * 2), Math.max(0, bounds.height - gap * 2))
    if (anchorItem) {
      var a = anchorItem.mapToItem(host, 0, 0)
      anchorRect = Qt.rect(a.x, a.y, anchorItem.width, anchorItem.height)
    }
  }

  function openFor(current) {
    selected = current || ""
    var base = Tasks.parseDateKey(selected || today) || new Date()
    viewYear = base.getFullYear()
    viewMonth = base.getMonth()
    place()
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

  width: Math.min(implicitWidth, boundsRect.width)
  // Right edges line up with the anchor's; below it, or above it.
  x: clamp(anchorRect.x + anchorRect.width - width,
           boundsRect.x, boundsRect.x + boundsRect.width - width)
  y: clamp(opensBelow ? anchorRect.y + anchorRect.height + gap : anchorRect.y - gap - height,
           boundsRect.y, boundsRect.y + boundsRect.height - height)

  // Follow the anchor while open: the window resizing moves it.
  Connections {
    target: picker.opened ? picker.parent : null
    function onWidthChanged() { picker.place() }
    function onHeightChanged() { picker.place() }
  }
  Connections {
    target: picker.opened ? picker.anchorItem : null
    function onXChanged() { picker.place() }
    function onYChanged() { picker.place() }
    function onWidthChanged() { picker.place() }
  }

  FontMetrics {
    id: captionMetrics
    font.family: picker.fontFamily
    font.pixelSize: Style.font.caption
  }

  background: Rectangle {
    color: picker.surface
    border.color: picker.border
    border.width: Math.max(1, Style.normalBorderWidth)
    radius: Style.cornerRadius
  }

  contentItem: ColumnLayout {
    id: content
    spacing: Style.spacing.lg

    GridLayout {
      id: quickChoices
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
      id: monthRow
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
      id: days
      columns: 7
      spacing: Style.spacing.xxs
      Layout.alignment: Qt.AlignHCenter

      Repeater {
        model: Tasks.weekdayHeaders(picker.firstDayOfWeek)
        delegate: Text {
          required property var modelData
          width: picker.cellSize
          height: picker.weekdayHeight
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
