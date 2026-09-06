import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// Pigeon inbox popup. Mounted (hidden) by BarWidget.qml; the bar identifies
// the popup by the widget in its slot, so `hostWidget` stands in for this
// panel wherever the bar needs an owner (popout coordinator, Tab switching).
Panel {
  id: root
  moduleName: "xyzlab.pigeon"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool openedFromHotkey: false
  readonly property var barIdentity: hostWidget || root

  // ------------------------------------------------------------ open/close
  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    onOpened()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    onOpened()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function onOpened() {
    nowMs = Date.now()
    cursorActive = openedFromHotkey && rows.length > 0
    selectedIndex = 0
    confirmOpen = false
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    confirmOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // --------------------------------------------------------------- theme
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------ view state
  property string topicFilter: ""
  property string query: ""
  property bool searchOpen: false
  property bool composeOpen: false
  property bool confirmOpen: false
  property int confirmIndex: 1
  property bool cursorActive: false
  property int selectedIndex: 0
  property string expandedId: ""
  property double nowMs: Date.now()
  property int composePriority: 3

  readonly property var allMessages: service ? service.messages : []
  readonly property var rows: Model.filterMessages(allMessages, topicFilter, query)
  readonly property var topicTabs: buildTopicTabs(allMessages, service ? service.topics : [])
  readonly property bool showTabs: topicTabs.length > 1
  readonly property bool configured: service ? service.configured && !service.authIncomplete : false
  readonly property bool connected: service ? service.status === "connected" : false
  readonly property bool muted: service ? service.muted : false
  readonly property int unread: service ? service.unreadCount : 0
  readonly property string editorFocusBlock: searchField.activeFocus || topicField.activeFocus || titleField.activeFocus || messageField.activeFocus ? "yes" : ""

  readonly property string statusCaps: {
    if (!service) return "LOADING"
    var parts = []
    if (!service.configured) parts.push(service.statusLine)
    else if (service.authIncomplete) parts.push(service.statusLine)
    else {
      parts.push(service.status === "connected" ? "Connected" : service.statusLine)
      if (service.status === "connected") {
        parts.push(service.topics.length + (service.topics.length === 1 ? " topic" : " topics"))
        parts.push(unread === 0 ? "all read" : unread + " unread")
      }
    }
    if (muted) parts.push(Model.muteLabel(service.muteUntil, nowMs))
    return parts.join(" · ").toUpperCase()
  }

  readonly property string heroGlyph: muted ? "󰂛" : (service && service.urgentUnreadCount > 0 ? "󱅫" : (unread > 0 ? "󰂞" : "󰂚"))

  function buildTopicTabs(messages, configuredTopics) {
    var order = []
    var seen = {}
    for (var i = 0; i < configuredTopics.length; i++) {
      if (!seen[configuredTopics[i]]) { seen[configuredTopics[i]] = true; order.push(configuredTopics[i]) }
    }
    for (var j = 0; j < messages.length; j++) {
      var t = messages[j] ? messages[j].topic : ""
      if (t && !seen[t]) { seen[t] = true; order.push(t) }
    }
    var tabs = [{ topic: "", label: "All", unread: Model.countUnread(messages, "").unread }]
    for (var k = 0; k < order.length; k++) tabs.push({ topic: order[k], label: "#" + order[k], unread: Model.countUnread(messages, order[k]).unread })
    return tabs
  }

  onRowsChanged: {
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
  }

  onTopicFilterChanged: { selectedIndex = 0 }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // ---------------------------------------------------------- navigation
  function selectedMessage() {
    if (!rows.length) return null
    return rows[Math.max(0, Math.min(selectedIndex, rows.length - 1))]
  }

  function moveCursor(dy) {
    if (!rows.length) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + dy))
  }

  function moveTopic(dx) {
    if (!showTabs) return
    var idx = 0
    for (var i = 0; i < topicTabs.length; i++) if (topicTabs[i].topic === topicFilter) idx = i
    idx = (idx + dx + topicTabs.length) % topicTabs.length
    topicFilter = topicTabs[idx].topic
  }

  function activateCursor() {
    var msg = selectedMessage()
    if (!msg) return
    cursorActive = true
    expandedId = expandedId === msg.id ? "" : msg.id
    if (msg.unread && service) service.markRead(msg.id, true)
  }

  function activateRow(index) {
    selectedIndex = index
    activateCursor()
  }

  function deleteSelected() {
    var msg = selectedMessage()
    if (msg && service) service.remove(msg.id)
  }

  function openSelectedClick() {
    var msg = selectedMessage()
    if (msg && service) service.openClick(msg)
  }

  function openSelectedAttachment() {
    var msg = selectedMessage()
    if (msg && service) service.openAttachment(msg)
  }

  function copySelected() {
    var msg = selectedMessage()
    if (msg && service) service.copyMessage(msg)
  }

  function runSelectedAction(n) {
    var msg = selectedMessage()
    if (msg && service) service.runAction(msg, n)
  }

  function toggleSearch() {
    searchOpen = !searchOpen
    if (searchOpen) {
      Qt.callLater(function() { searchField.forceActiveFocus(); searchField.selectAll() })
    } else {
      query = ""
      searchField.text = ""
      refocusPanel()
    }
  }

  function toggleCompose() {
    composeOpen = !composeOpen
    if (composeOpen) {
      if (topicField.text === "") topicField.text = topicFilter || (service && service.topics.length ? service.topics[0] : "")
      Qt.callLater(function() { messageField.forceActiveFocus() })
    } else {
      refocusPanel()
    }
  }

  function refocusPanel() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function requestClear() {
    if (!rows.length) return
    confirmIndex = 1
    confirmOpen = true
  }

  function confirmClear() {
    confirmOpen = false
    if (service) service.clear(topicFilter)
  }

  function sendCompose() {
    if (!service) return
    var ok = service.publish(topicField.text, titleField.text, messageField.text, composePriority, "")
    if (ok) {
      titleField.text = ""
      messageField.text = ""
    }
  }

  function cyclePriority() {
    composePriority = composePriority >= 5 ? 1 : composePriority + 1
  }

  function priorityCaption(p) {
    return ["", "min", "low", "default", "high", "urgent"][Model.clampPriority(p)]
  }

  function handleEditorKey(event, field) {
    if (event.key === Qt.Key_Escape) {
      if (field === "search") toggleSearch()
      else toggleCompose()
      event.accepted = true
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && field !== "search") {
      sendCompose()
      event.accepted = true
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && field === "search") {
      refocusPanel()
      cursorActive = rows.length > 0
      event.accepted = true
      return true
    }
    return false
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPublishFinished(ok, text) {
      if (ok && root.composeOpen) Qt.callLater(function() { messageField.forceActiveFocus() })
    }
  }

  // ------------------------------------------------------------------ UI
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editorFocusBlock !== ""

      onMoveRequested: function(dx, dy) {
        if (root.confirmOpen) {
          if (dx !== 0) root.confirmIndex = root.confirmIndex === 0 ? 1 : 0
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveTopic(dx)
      }
      onActivateRequested: {
        if (root.confirmOpen) {
          if (root.confirmIndex === 1) root.confirmClear()
          else root.confirmOpen = false
          return
        }
        root.activateCursor()
      }
      onCloseRequested: {
        if (root.confirmOpen) { root.confirmOpen = false; return }
        if (root.composeOpen) { root.toggleCompose(); return }
        if (root.searchOpen) { root.toggleSearch(); return }
        root.close()
      }
      onDeleteRequested: if (!root.confirmOpen) root.deleteSelected()
      onTabRequested: function(direction) { if (!root.confirmOpen) root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.confirmOpen) return
        if (!root.service) return
        switch (t) {
        case "c": root.toggleCompose(); break
        case "/": root.toggleSearch(); break
        case "u": root.service.markAllRead(root.topicFilter); break
        case "m": root.service.toggleMute(); break
        case "r": root.service.reconnect(); break
        case "o": root.openSelectedClick(); break
        case "a": root.openSelectedAttachment(); break
        case "y": root.copySelected(); break
        case "d": root.deleteSelected(); break
        case "D": root.requestClear(); break
        case "e": root.activateCursor(); break
        case "1": root.runSelectedAction(0); break
        case "2": root.runSelectedAction(1); break
        case "3": root.runSelectedAction(2); break
        case "g": root.selectedIndex = 0; root.cursorActive = root.rows.length > 0; break
        case "G": root.selectedIndex = Math.max(0, root.rows.length - 1); root.cursorActive = root.rows.length > 0; break
        default: break
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ---------- Hero: glyph · title · status · header actions ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerActions.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.heroGlyph
            color: root.service && root.service.urgentUnreadCount > 0 ? root.urgentColor : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.connected || root.unread > 0 ? 1.0 : 0.5
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Pigeon"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusCaps
              color: root.service && root.service.status === "error" ? root.urgentColor : Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              iconText: "󰏫"
              tooltipText: "Compose (c)"
              foreground: root.fg
              fontFamily: root.fontFamily
              hasCursor: root.composeOpen
              onClicked: root.toggleCompose()
            }
            PanelActionButton {
              iconText: "󰍉"
              tooltipText: "Search (/)"
              foreground: root.fg
              fontFamily: root.fontFamily
              hasCursor: root.searchOpen
              onClicked: root.toggleSearch()
            }
            PanelActionButton {
              iconText: "󰄬"
              tooltipText: root.topicFilter ? "Mark #" + root.topicFilter + " read (u)" : "Mark all read (u)"
              enabled: root.unread > 0
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.markAllRead(root.topicFilter)
            }
            PanelActionButton {
              iconText: root.muted ? "󰂚" : "󰂛"
              tooltipText: root.muted ? "Unmute toasts (m)" : "Mute toasts (m)"
              foreground: root.fg
              fontFamily: root.fontFamily
              hasCursor: root.muted
              onClicked: if (root.service) root.service.toggleMute()
            }
            PanelActionButton {
              iconText: "󰑓"
              tooltipText: "Reconnect (r)"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.reconnect()
            }
            PanelActionButton {
              iconText: "󰆴"
              tooltipText: root.topicFilter ? "Clear #" + root.topicFilter + " (D)" : "Clear inbox (D)"
              enabled: root.rows.length > 0
              foreground: root.fg
              hoverColor: root.urgentColor
              fontFamily: root.fontFamily
              onClicked: root.requestClear()
            }
          }
        }

        // ---------- Setup hint when nothing is configured ----------
        Column {
          visible: !root.configured
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator { foreground: root.fg }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service && root.service.authIncomplete
              ? "Auth mode \"" + root.service.authMode + "\" is set but no credentials are configured."
              : "Point Pigeon at a ntfy server and one or more topics to start receiving messages."
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service && root.service.authIncomplete
              ? "omarchy bar set xyzlab.pigeon token tk_…\nomarchy bar set xyzlab.pigeon auth none"
              : "omarchy bar set xyzlab.pigeon server https://ntfy.example.com\nomarchy bar set xyzlab.pigeon topics alerts,home"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Error detail ----------
        Text {
          visible: root.configured && root.service && root.service.status === "error" && root.service.lastError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.service ? root.service.lastError : ""
          color: root.urgentColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator {
          visible: root.showTabs || root.searchOpen || root.composeOpen || root.rows.length > 0
          foreground: root.fg
        }

        // ---------- Topic tabs ----------
        Flow {
          visible: root.showTabs
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.topicTabs
            Button {
              required property var modelData
              text: modelData.label + (modelData.unread > 0 ? "  " + modelData.unread : "")
              selected: root.topicFilter === modelData.topic
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.topicFilter = modelData.topic
            }
          }
        }

        // ---------- Search ----------
        TextField {
          id: searchField
          visible: root.searchOpen
          width: parent.width
          placeholderText: "Filter messages"
          foreground: root.fg
          font.family: root.fontFamily
          onTextChanged: root.query = text
          Keys.onPressed: function(event) { root.handleEditorKey(event, "search") }
        }

        // ---------- Compose ----------
        Column {
          visible: root.composeOpen
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "SEND A MESSAGE"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: topicField
              width: Style.space(140)
              placeholderText: "topic"
              foreground: root.fg
              font.family: root.fontFamily
              Keys.onPressed: function(event) { root.handleEditorKey(event, "topic") }
            }

            TextField {
              id: titleField
              width: parent.width - topicField.width - Style.space(6)
              placeholderText: "Title (optional)"
              foreground: root.fg
              font.family: root.fontFamily
              Keys.onPressed: function(event) { root.handleEditorKey(event, "title") }
            }
          }

          TextField {
            id: messageField
            width: parent.width
            placeholderText: "Message — Enter sends, Esc closes"
            foreground: root.fg
            font.family: root.fontFamily
            Keys.onPressed: function(event) { root.handleEditorKey(event, "message") }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(composeControls.implicitHeight, composeStatus.implicitHeight)

            Row {
              id: composeControls
              spacing: Style.space(6)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Button {
                iconText: Model.priorityGlyph(root.composePriority)
                text: "Priority " + root.priorityCaption(root.composePriority)
                foreground: root.composePriority >= 5 ? root.urgentColor : root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                tooltipText: "Click to cycle priority"
                onClicked: root.cyclePriority()
              }

              Button {
                iconText: "󰒊"
                text: root.service && root.service.publishing ? "Sending…" : "Send"
                enabled: !!root.service && !root.service.publishing
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                bordered: true
                onClicked: root.sendCompose()
              }
            }

            Text {
              id: composeStatus
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - composeControls.implicitWidth - Style.space(10))
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: root.service ? root.service.publishStatus : ""
              color: root.service && root.service.publishOk ? root.accent : (root.service && root.service.publishStatus && !root.service.publishing ? root.urgentColor : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelSeparator { foreground: root.fg }
        }

        // ---------- Message list ----------
        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(460))
          visible: root.rows.length > 0
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: root.rows
          currentIndex: root.cursorActive ? root.selectedIndex : -1
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepCurrentVisible)
          function keepCurrentVisible() {
            if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
          }

          delegate: MessageRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            message: modelData
            rowIndex: index
            expanded: root.expandedId === modelData.id
            showTopic: root.topicFilter === ""
            allowHttp: root.service ? root.service.allowHttpActions : false
            service: root.service
            fg: root.fg
            dim: root.dim
            accent: root.accent
            urgentColor: root.urgentColor
            fontFamily: root.fontFamily
            nowMs: root.nowMs
            hasCursor: root.cursorActive && root.selectedIndex === index
            onHovered: function(i) { root.cursorActive = true; root.selectedIndex = i }
            onActivated: function(i) { root.activateRow(i) }
          }
        }

        // ---------- Empty state ----------
        Text {
          visible: root.rows.length === 0 && root.configured
          width: parent.width
          wrapMode: Text.Wrap
          text: root.query !== ""
            ? "Nothing matches \"" + root.query + "\""
            : (root.topicFilter ? "No messages in #" + root.topicFilter + " yet" : (root.connected ? "Inbox is empty — waiting for messages" : "No messages yet"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        // ---------- Key hints ----------
        Text {
          visible: root.rows.length > 0 && !root.composeOpen
          width: parent.width
          textFormat: Text.PlainText
          text: "j/k move · ⏎ expand · o link · a file · d delete · u read all · c compose · / search"
          color: Qt.darker(root.fg, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        selectedIndex: root.confirmIndex
        message: root.topicFilter ? "Delete every message in #" + root.topicFilter + "?" : "Delete every message in the inbox?"
        confirmText: "Delete"
        background: Color.popups.background
        foreground: root.fg
        scrim: Util.alpha(Color.popups.background, 0.75)
        selectedBackground: Style.hoverFillFor(root.fg, root.accent)
        selectedText: root.accent
        fontFamily: root.fontFamily
        onSelectedIndexChanged: root.confirmIndex = selectedIndex
        onCanceled: root.confirmOpen = false
        onConfirmed: root.confirmClear()
      }
    }
  }
}
