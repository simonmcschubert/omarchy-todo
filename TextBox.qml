import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Plain text over several lines, styled like the kit's TextField. A quiet
// box shows no fill or border until hovered or focused, so it reads like
// the text it holds.
TextArea {
  id: box

  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property bool quiet: false

  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"),
                                                       foreground, accent)

  textFormat: TextEdit.PlainText
  wrapMode: TextEdit.Wrap
  color: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)
  selectionColor: Style.selectionFillFor(foreground, accent)
  selectedTextColor: foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  leftPadding: Style.spacing.controlPaddingX + Border.left(borderSpec)
  rightPadding: Style.spacing.controlPaddingX + Border.right(borderSpec)
  topPadding: Style.spacing.inputPaddingY + Border.top(borderSpec)
  bottomPadding: Style.spacing.inputPaddingY + Border.bottom(borderSpec)

  background: Ui.BorderSurface {
    visible: !box.quiet || box.activeFocus || box.hovered
    color: Style.controlFill(box.activeFocus, box.hovered, box.foreground, box.accent)
    borderSpec: box.borderSpec
    radius: Style.cornerRadius
  }
}
