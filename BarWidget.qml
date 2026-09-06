import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "xyzlab.pigeon"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("xyzlab.pigeon") : null
  readonly property int unread: service ? service.unreadCount : 0
  readonly property int urgent: service ? service.urgentUnreadCount : 0
  readonly property string status: service ? service.status : "unconfigured"
  readonly property bool connected: status === "connected"
  readonly property bool muted: service ? service.muted : false
  readonly property bool showCount: boolSetting("showCount", true)
  readonly property bool showZero: boolSetting("showZero", false)
  readonly property string customGlyph: String(setting("glyph", "") || "").trim()

  readonly property string glyph: customGlyph || "󱗆"
  readonly property string countText: unread > 99 ? "99+" : String(unread)
  readonly property bool countVisible: !vertical && showCount && (unread > 0 || showZero)
  readonly property color glyphColor: {
    var base = button.foreground
    if (urgent > 0) return root.bar ? root.bar.urgent : Color.urgent
    if (unread > 0) return Color.accent
    return base
  }
  readonly property string tooltip: {
    var parts = []
    parts.push(unread === 0 ? "No unread messages" : (unread === 1 ? "1 unread message" : unread + " unread messages"))
    if (service) parts.push(service.statusLine)
    if (muted) parts.push(Model.muteLabel(service.muteUntil, service.nowMs))
    return parts.join(" · ")
  }

  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "boolean") return v
    var s = String(v).toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    dimmed: root.muted || (!root.connected && root.unread === 0)
    tooltipText: root.tooltip
    horizontalMargin: root.countVisible ? 6 : 0
    fixedWidth: root.vertical ? -1 : (root.countVisible ? content.implicitWidth + Style.spaceReal(12) : Style.bar.iconSlot)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.RightButton) root.service.markAllRead("")
      else if (b === Qt.MiddleButton) root.service.toggleMute()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        id: glyphText
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: root.glyphColor
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 160 } }
      }

      Text {
        visible: root.countVisible
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.countText
        color: root.glyphColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: root.unread > 0
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }
  }
}
