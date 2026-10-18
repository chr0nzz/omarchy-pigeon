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

  height: flow.implicitHeight
  readonly property int gap: Style.space(4)
  readonly property int pad: Style.space(6)

  Flow {
    id: flow
    width: strip.width
    spacing: strip.gap

    Repeater {
      model: strip.tabs

      Item {
        id: tabItem
        required property var modelData
        readonly property string suffix: modelData.unread > 0 ? "  " + modelData.unread : ""
        readonly property real naturalWidth: probe.implicitWidth
        readonly property real assigned: strip.width > 0 ? Math.min(naturalWidth, strip.width) : naturalWidth
        width: assigned
        height: tab.implicitHeight

        Button {
          id: probe
          visible: false
          text: tabItem.modelData.label + tabItem.suffix
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
