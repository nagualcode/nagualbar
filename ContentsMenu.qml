import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The right-click "bar contents" panel.
//
// Opened by right-clicking empty bar space. Every icon nagualbar draws gets one
// row: the bar widgets from the live shell.json layout, then the indicator row
// and its individual icons. A switch here is *visible*, not *enabled* —
// flipping it off parks the icon and leaves the widget mounted and running,
// which is the whole difference from `omarchy plugin disable`.
//
// Hidden entries stay listed, because they are still there: only the icon went
// away. They read as dimmed rather than absent so a mis-click is recoverable
// by eye.
KeyboardPanel {
  id: root

  property var rows: bar ? bar.contentsRows() : []
  property int cursorIndex: -1
  property bool cursorActive: false

  readonly property color foreground: Color.foreground
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(Color.foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property int visibleCount: visibleRowCount()
  readonly property int hiddenCount: rows.length - visibleCount

  function visibleRowCount() {
    var count = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].kind === "row" && !bar.isHiddenKey(String(rows[i].key || ""))) count++
    }
    return count
  }

  function rowKey(index) {
    var row = rows[index]
    return row && row.kind === "row" ? String(row.key || "") : ""
  }

  function toggleRow(index) {
    var key = rowKey(index)
    if (key === "" || !bar) return
    bar.setHiddenKey(key, !bar.isHiddenKey(key))
  }

  // Navigation steps over the toggleable rows only, so the cursor never lands
  // on a section header.
  function stepTarget(fromIndex, step) {
    var index = fromIndex
    for (var i = 0; i < rows.length; i++) {
      index += step
      if (index < 0 || index >= rows.length) return -1
      if (rows[index] && rows[index].kind === "row") return index
    }
    return -1
  }

  function moveCursor(step) {
    cursorActive = true
    var target = step > 0 ? stepTarget(cursorIndex, 1) : stepTarget(rows.length - 1, -1)
    cursorIndex = target
    Qt.callLater(revealCursor)
  }

  // Tab wraps; arrows stop at the ends, which is what the arrow keys mean in
  // every other Omarchy panel.
  function tabCursor(step) {
    var next = cursorIndex < 0 ? (step > 0 ? 0 : rows.length - 1) : cursorIndex + step
    while (next >= 0 && next < rows.length) {
      if (rows[next] && rows[next].kind === "row") {
        cursorActive = true
        cursorIndex = next
        Qt.callLater(revealCursor)
        return
      }
      next += step
    }
  }

  function activateCursor() {
    if (cursorIndex < 0) return
    toggleRow(cursorIndex)
  }

  function revealCursor() {
    var item = repeater.itemAt(cursorIndex)
    if (!item || !flick) return
    var top = item.y + column.y
    var bottom = top + item.height
    if (top < flick.contentY) flick.contentY = top
    else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height
  }

  function showAll() {
    if (bar) bar.showAllKeys()
  }

  function hideIndicators() {
    if (bar) bar.hideKeys(bar.indicatorIds())
  }

  onOpenChanged: {
    if (!open) return
    cursorActive = false
    cursorIndex = -1
    if (flick) flick.contentY = 0
    if (keyCatcher) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // A toggle replaces the rows array, and the panel is full of bars this size
  // — re-anchoring the cursor to the same key rather than the same index keeps
  // arrow-key navigation steady across a hide.
  onRowsChanged: {
    var key = rowKey(cursorIndex)
    if (key === "") return
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].kind === "row" && String(rows[i].key || "") === key) {
        cursorIndex = i
        return
      }
    }
    cursorIndex = -1
  }

  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Style.space(320), Style.space(420))
  contentHeight: fittedContentHeight(column.implicitHeight, Style.space(560))

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent

    onMoveRequested: function(dx, dy) {
      if (dy !== 0) root.moveCursor(dy)
    }
    onActivateRequested: root.activateCursor()
    onCloseRequested: root.close()
    onTabRequested: function(direction) { root.tabCursor(direction) }
    onTextKey: function(t) {
      if (t === "a" || t === "A") root.showAll()
    }


    Flickable {
      id: flick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
        spacing: Style.spacing.xs

        PanelHero {
          id: hero
          width: parent.width
          title: "Bar contents"
          meta: root.rows.length === 0
            ? "Nothing configured"
            : root.visibleCount + " shown · " + root.hiddenCount + " hidden"
          foreground: root.foreground
          fontFamily: root.fontFamily

          trailingControl: Component {
            Button {
              text: "All"
              tooltipText: "Show every bar icon (A)"
              bordered: true
              horizontalPadding: Style.spacing.md
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.showAll()
            }
          }
        }

        PanelSeparator {}

        Repeater {
          id: repeater
          model: root.rows

          // `modelData` is declared once, by ContentsRow itself. Repeating it
          // here would redeclare a required property that the component
          // already has, and the delegate then cannot be created at all.
          delegate: ContentsRow {
            required property int index

            width: column.width
            menu: root
            rowIndex: index
          }
        }

        Item {
          width: parent.width
          implicitHeight: Style.spacing.sm
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Button {
            text: "Hide indicators"
            bordered: true
            leftAlign: true
            horizontalPadding: Style.spacing.md
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.hideIndicators()
          }

          Button {
            text: "Show all"
            bordered: true
            leftAlign: true
            horizontalPadding: Style.spacing.md
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.showAll()
          }
        }
      }
    }
  }

  // One line per entry: a section tag, the name, and the switch. The whole row
  // is the click target, so the switch itself never has to be hit precisely.
  component ContentsRow: BorderSurface {
    id: row

    required property var modelData
    property var menu: null
    property int rowIndex: -1

    readonly property bool isHeader: modelData && modelData.kind === "header"
    readonly property bool isRow: modelData && modelData.kind === "row"
    readonly property bool hidden: isRow && menu ? menu.bar.isHiddenKey(String(modelData.key || "")) : false
    readonly property bool cursorHere: isRow && menu ? menu.cursorActive && menu.cursorIndex === rowIndex : false

    implicitHeight: isHeader ? Style.space(22) : Style.spacing.popupRowHeight
    height: implicitHeight
    visible: isHeader || isRow
    radius: Style.cornerRadius
    color: cursorHere ? Style.hoverFillFor(menu.foreground, menu.accent, menu.urgent) : "transparent"
    borderSpec: cursorHere
      ? Border.controlSpec("hover-cursor", menu.foreground, menu.accent, menu.urgent)
      : Border.none()

    PanelSectionHeader {
      visible: row.isHeader
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.sm
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      text: row.modelData ? String(row.modelData.label || "") : ""
      foreground: row.menu.foreground
      fontFamily: row.menu.fontFamily
    }

    Text {
      id: sectionTag
      visible: row.isRow
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(26)
      text: row.modelData && row.modelData.section
        ? String(row.modelData.section).charAt(0).toUpperCase()
        : ""
      color: row.hidden ? row.menu.dim : row.menu.accent
      font.family: row.menu.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      visible: row.isRow
      anchors.left: sectionTag.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: switchItem.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      text: row.modelData ? String(row.modelData.label || "") : ""
      color: row.hidden ? row.menu.dim : row.menu.foreground
      font.family: row.menu.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.strikeout: row.hidden
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: switchItem
      visible: row.isRow
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      checked: !row.hidden
      hasCursor: row.cursorHere
      // The row's MouseArea owns the click; a second one here would swallow it.
      interactive: false
      trackHeight: Math.max(14, Math.round(Style.spacing.controlHeight * 0.42))
      foreground: row.menu.foreground
      accent: row.menu.accent
    }

    MouseArea {
      id: rowPointer
      visible: row.isRow
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onClicked: {
        row.menu.cursorActive = false
        row.menu.toggleRow(row.rowIndex)
      }

      PanelToolTip {
        visible: rowPointer.containsMouse
          && row.modelData
          && String(row.modelData.description || "") !== ""
        // Coerced, because a row that is being torn down arrives here with no
        // modelData at all, and a QString property will not take undefined.
        text: row.modelData ? String(row.modelData.description || "") : ""
        fontFamily: row.menu ? row.menu.fontFamily : Style.font.family
      }
    }
  }
}
