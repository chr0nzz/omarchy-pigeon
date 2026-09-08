import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Item {
  id: strip
  property var tabs: []
  property string current: ""
  property color foreground: "white"
  property string fontFamily: ""
  property bool bordered: false
  signal picked(string topic)

  height: row.implicitHeight
  readonly property int gap: Style.space(4)
  readonly property int pad: Style.space(6)
  property var fit: []

  function scheduleFit() { Qt.callLater(refit) }

  function refit() {
    var naturals = []
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i)
      naturals.push(item ? item.naturalWidth : 0)
    }
    fit = Model.fitWidths(naturals, width, gap)
  }

  onWidthChanged: scheduleFit()

  Row {
    id: row
    spacing: strip.gap

    Repeater {
      id: repeater
      model: strip.tabs
      onItemAdded: strip.scheduleFit()
      onItemRemoved: strip.scheduleFit()

      Item {
        id: tabItem
        required property var modelData
        required property int index
        readonly property string suffix: modelData.unread > 0 ? "  " + modelData.unread : ""
        readonly property string fullLabel: modelData.label + suffix
        readonly property real naturalWidth: probe.implicitWidth
        readonly property real assigned: strip.fit[index] > 0 ? strip.fit[index] : naturalWidth
        width: assigned
        height: tab.implicitHeight
        onNaturalWidthChanged: strip.scheduleFit()

        Button {
          id: probe
          visible: false
          text: tabItem.fullLabel
          bordered: strip.bordered
          fontFamily: strip.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: strip.pad
          verticalPadding: Style.space(3)
        }

        Button {
          id: tab
          width: tabItem.assigned
          text: Model.fitLabel(tabItem.modelData.label, tabItem.suffix, tabItem.naturalWidth, tabItem.assigned, strip.pad * 2)
          selected: strip.current === tabItem.modelData.topic
          bordered: strip.bordered
          foreground: strip.foreground
          fontFamily: strip.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: strip.pad
          verticalPadding: Style.space(3)
          onClicked: strip.picked(tabItem.modelData.topic)
        }
      }
    }
  }
}
