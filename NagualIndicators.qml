import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Indicators.js" as IndicatorModel

// nagualbar's own indicator row.
//
// Omarchy ships these as `omarchy.indicators`, a widget that keeps inactive
// icons concealed until you hover them. nagualbar treats them as ordinary bar
// icons instead: all six are mounted, all six are always on screen (inactive
// ones dimmed), and each one can be hidden on its own from the right-click
// contents menu — same as any other icon in the bar.
//
// The icons are vendored under `indicators/`, so nagualbar does not depend on
// omarchy's copy staying where it is. They still read the same first-party
// services (`omarchy.idle`, `omarchy.nightlight`, `omarchy.notifications`),
// which the shell exposes to a full-bar plugin as narrow proxies, so toggling
// one here drives the real system state either way.
Item {
  id: root

  property var bar: null
  property string moduleName: "nagualbar.indicators"

  // The vendored indicators were written for omarchy's indicator host, which
  // refreshes them on demand. Keep that contract: Reminder and
  // ScreenRecording both listen for this.
  signal refreshRequested()

  // Always on, unlike omarchy's host: the point of the row is that you can see
  // the state without hovering first.
  readonly property bool revealInactiveIndicators: true

  readonly property var entries: IndicatorModel.list()
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function isHidden(id) {
    if (!bar || typeof bar.isHiddenKey !== "function") return false
    return bar.isHiddenKey(id) === true
  }

  function setIndicatorItemHovered(hovered) {
    // Nothing to reveal: the inactive icons are already showing.
  }

  implicitWidth: listLoader.item ? listLoader.item.implicitWidth : 0
  implicitHeight: listLoader.item ? listLoader.item.implicitHeight : 0

  Component.onCompleted: refreshRequested()

  IpcHandler {
    target: "nagualbar.indicators"

    function refresh(): void {
      root.refreshRequested()
    }
  }

  Loader {
    id: listLoader
    anchors.fill: parent
    // One list, not one per orientation: a Column and a Row both mounted
    // would run two of every indicator, each with its own poll process.
    sourceComponent: root.vertical ? verticalList : horizontalList
  }

  Component {
    id: horizontalList

    Row {
      spacing: 0

      Repeater {
        model: root.entries

        IndicatorSlot {
          required property var modelData
          entry: modelData
          bar: root.bar
          host: root
        }
      }
    }
  }

  Component {
    id: verticalList

    Column {
      spacing: 0

      Repeater {
        model: root.entries

        IndicatorSlot {
          required property var modelData
          entry: modelData
          bar: root.bar
          host: root
        }
      }
    }
  }

  // One vendored indicator. The `Loader` is what carries visibility: the
  // indicator's own `visible` is a binding the vendored file owns, so
  // assigning to it would break the file's logic. Hiding the Loader instead
  // takes the item out of the render and hit-test trees while the indicator
  // stays mounted and polling underneath.
  component IndicatorSlot: Item {
    id: slot

    required property var entry
    required property var bar
    required property var host

    readonly property string indicatorId: String(entry && entry.id ? entry.id : "")
    readonly property bool hidden: host ? host.isHidden(indicatorId) : false
    readonly property var item: indicatorSource.item

    // Read by the bar's synthesized click routing: a hidden icon must not
    // answer a click that the bar forwards on its behalf.
    property bool barHidden: hidden

    implicitWidth: hidden || !item || !item.visible ? 0 : item.implicitWidth
    implicitHeight: hidden || !item || !item.visible ? 0 : item.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: indicatorSource
      anchors.fill: parent
      visible: !slot.hidden
      source: slot.indicatorId !== "" ? Qt.resolvedUrl("indicators/" + slot.indicatorId + ".qml") : ""

      onLoaded: slot.injectProps()
      onStatusChanged: {
        if (status === Loader.Error) console.warn("nagualbar: indicator failed to load:", slot.indicatorId, source)
      }
    }

    function injectProps() {
      var target = indicatorSource.item
      if (!target) return
      if ("bar" in target) target.bar = slot.bar
      if ("moduleName" in target) target.moduleName = slot.indicatorId
      if ("indicatorHost" in target) target.indicatorHost = slot.host
      if ("indicatorBlock" in target) target.indicatorBlock = "single"
      if ("activeOverride" in target) target.activeOverride = null
    }
  }
}
