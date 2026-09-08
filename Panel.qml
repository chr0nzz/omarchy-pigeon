import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

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
    statusIndex = 0
    cursorActive = openedFromHotkey && rows.length > 0
    selectedIndex = 0
    confirmOpen = false
    settingsOpen = false
    settingsStatus = ""
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    confirmOpen = false
    settingsOpen = false
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

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

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

  property bool settingsOpen: false
  property string settingsStatus: ""
  property bool settingsError: false
  property string dServer: ""
  property string dTopics: ""
  property string dAuth: "none"
  property string dToken: ""
  property string dUser: ""
  property string dPass: ""
  property bool dToasts: true
  property int dMinPriority: 2
  property bool dAllowHttp: false
  property bool dShowCount: true
  property bool dShowZero: false
  property string dGlyph: ""
  property string dBackfill: "all"
  property string dMaxMessages: "200"

  readonly property var allMessages: service ? service.messages : []
  readonly property var rows: Model.filterMessages(allMessages, topicFilter, query)
  readonly property var topicTabs: buildTopicTabs(allMessages, service ? service.topics : [])
  readonly property bool showTabs: topicTabs.length > 1
  readonly property bool configured: service ? service.configured && !service.authIncomplete : false
  readonly property bool connected: service ? service.status === "connected" : false
  readonly property bool muted: service ? service.muted : false
  readonly property int unread: service ? service.unreadCount : 0
  readonly property bool settingsFieldFocused: sServer.activeFocus || sTopics.activeFocus || sToken.activeFocus || sUser.activeFocus || sPass.activeFocus || sGlyph.activeFocus || sBackfill.activeFocus || sMax.activeFocus
  readonly property string editorFocusBlock: searchField.activeFocus || topicField.activeFocus || titleField.activeFocus || messageField.activeFocus ? "yes" : ""

  readonly property var statusParts: {
    if (!service) return ["Loading"]
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
    return parts
  }
  property int statusIndex: 0
  onStatusPartsChanged: if (statusIndex >= statusParts.length) statusIndex = 0
  readonly property string statusCaps: statusParts.length ? String(statusParts[Math.min(statusIndex, statusParts.length - 1)]).toUpperCase() : ""

  Timer {
    interval: 3000
    running: root.opened && root.statusParts.length > 1
    repeat: true
    onTriggered: root.statusIndex = (root.statusIndex + 1) % root.statusParts.length
  }

  readonly property string heroGlyph: "󱗆"

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
    for (var k = 0; k < order.length; k++) tabs.push({ topic: order[k], label: order[k], unread: Model.countUnread(messages, order[k]).unread })
    return tabs
  }

  onRowsChanged: {
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
  }

  onTopicFilterChanged: { selectedIndex = 0 }
  onOpenedChanged: if (opened && service) service.dismissAllToasts()

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

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

  function currentSetting(name, fallback) {
    var v = settings ? settings[name] : undefined
    if (v === undefined || v === null) {
      var d = service && service.defaults ? service.defaults[name] : undefined
      return d === undefined || d === null ? fallback : d
    }
    return v
  }

  function asBool(v, fallback) {
    if (typeof v === "boolean") return v
    var t = String(v).toLowerCase()
    if (t === "true" || t === "1" || t === "yes" || t === "on") return true
    if (t === "false" || t === "0" || t === "no" || t === "off") return false
    return fallback
  }

  function loadDraft() {
    dServer = String(currentSetting("server", "https://ntfy.sh"))
    var topics = currentSetting("topics", "")
    dTopics = typeof topics === "string" ? topics : Model.parseTopics(topics).join(",")
    var auth = String(currentSetting("auth", "none")).toLowerCase()
    dAuth = auth === "token" || auth === "basic" ? auth : "none"
    dToken = String(currentSetting("token", ""))
    dUser = String(currentSetting("username", ""))
    dPass = String(currentSetting("password", ""))
    dToasts = asBool(currentSetting("toasts", true), true)
    dMinPriority = Model.clampPriority(currentSetting("toastMinPriority", 2))
    dAllowHttp = asBool(currentSetting("allowHttpActions", false), false)
    dShowCount = asBool(currentSetting("showCount", true), true)
    dShowZero = asBool(currentSetting("showZero", false), false)
    dGlyph = String(currentSetting("glyph", ""))
    dBackfill = String(currentSetting("backfill", "all"))
    dMaxMessages = String(currentSetting("maxMessages", 200))
    sServer.text = dServer
    sTopics.text = dTopics
    sToken.text = dToken
    sUser.text = dUser
    sPass.text = dPass
    sGlyph.text = dGlyph
    sBackfill.text = dBackfill
    sMax.text = dMaxMessages
  }

  function openSettings() {
    settingsStatus = ""
    settingsError = false
    loadDraft()
    composeOpen = false
    searchOpen = false
    confirmOpen = false
    settingsOpen = true
    settingsFocusTimer.restart()
  }

  Timer {
    id: settingsFocusTimer
    interval: 60
    onTriggered: {
      if (!root.settingsOpen) return
      sServer.forceActiveFocus()
      sServer.cursorPosition = sServer.text.length
    }
  }

  function closeSettings() {
    settingsOpen = false
    settingsStatus = ""
    refocusPanel()
  }

  function toggleSettings() {
    if (settingsOpen) closeSettings()
    else openSettings()
  }

  function failSettings(text) {
    settingsError = true
    settingsStatus = text
    return false
  }

  function saveSettings() {
    var server = Model.normalizeServer(dServer)
    if (!server) return failSettings("Server URL is required")
    var topics = Model.parseTopics(dTopics)
    if (dTopics.trim() !== "" && topics.length === 0) return failSettings("Topic names may only use letters, digits, - and _")
    if (dAuth === "token" && dToken.trim() === "") return failSettings("Token auth needs an access token")
    if (dAuth === "basic" && dUser.trim() === "") return failSettings("Basic auth needs a username")
    var max = parseInt(dMaxMessages, 10)
    if (!isFinite(max) || max < 20) return failSettings("Keep at least 20 messages")
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function")
      return failSettings("Shell refused the update")

    var entry = {}
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry.server = server
    entry.topics = topics.join(",")
    entry.auth = dAuth
    entry.token = dAuth === "token" ? dToken.trim() : ""
    entry.username = dAuth === "basic" ? dUser.trim() : ""
    entry.password = dAuth === "basic" ? dPass : ""
    entry.toasts = dToasts
    entry.toastMinPriority = dMinPriority
    entry.allowHttpActions = dAllowHttp
    entry.showCount = dShowCount
    entry.showZero = dShowZero
    entry.glyph = dGlyph.trim()
    entry.backfill = dBackfill.trim() || "all"
    entry.maxMessages = Math.min(2000, max)
    root.bar.shell.updateEntryInline(root.moduleName, entry)
    settingsError = false
    settingsStatus = "Saved"
    settingsOpen = false
    refocusPanel()
    return true
  }

  function cycleMinPriority() {
    dMinPriority = dMinPriority >= 5 ? 1 : dMinPriority + 1
  }

  function handleSettingsKey(event) {
    if (event.key === Qt.Key_Escape) {
      closeSettings()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      saveSettings()
      event.accepted = true
    }
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(517))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editorFocusBlock !== "" || (root.settingsOpen && (settingsScope.activeFocus || root.settingsFieldFocused))

      onMoveRequested: function(dx, dy) {
        if (root.confirmOpen) {
          if (dx !== 0) root.confirmIndex = root.confirmIndex === 0 ? 1 : 0
          return
        }
        if (root.settingsOpen) return
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveTopic(dx)
      }
      onActivateRequested: {
        if (root.confirmOpen) {
          if (root.confirmIndex === 1) root.confirmClear()
          else root.confirmOpen = false
          return
        }
        if (root.settingsOpen) return
        root.activateCursor()
      }
      onCloseRequested: {
        if (root.confirmOpen) { root.confirmOpen = false; return }
        if (root.settingsOpen) { root.closeSettings(); return }
        if (root.composeOpen) { root.toggleCompose(); return }
        if (root.searchOpen) { root.toggleSearch(); return }
        root.close()
      }
      onDeleteRequested: if (!root.confirmOpen) root.deleteSelected()
      onTabRequested: function(direction) {
        if (root.confirmOpen) return
        if (root.settingsOpen) { sServer.forceActiveFocus(); return }
        root.switchPanel(direction)
      }
      onTextKey: function(t) {
        if (root.confirmOpen) return
        if (root.settingsOpen) { if (t === "s") root.closeSettings(); return }
        if (!root.service) return
        switch (t) {
        case "s": root.openSettings(); break
        case "c": root.toggleCompose(); break
        case "/": root.toggleSearch(); break
        case "u": root.service.markAllRead(root.topicFilter); break
        case "m": root.service.toggleMute(); break
        case "r": root.service.reload(); break
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
              tooltipText: "Reload history from the server (r)"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.reload()
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
            PanelActionButton {
              iconText: "󰒓"
              tooltipText: root.settingsOpen ? "Back to inbox (s)" : "Settings (s)"
              foreground: root.fg
              fontFamily: root.fontFamily
              hasCursor: root.settingsOpen
              onClicked: root.toggleSettings()
            }
          }
        }

        FocusScope {
          id: settingsScope
          visible: root.settingsOpen
          width: parent.width
          implicitHeight: settingsColumn.implicitHeight
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.closeSettings(); event.accepted = true }
          }

          component FieldLabel: Text {
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          component SettingsToggle: Toggle {
            width: parent.width
            foreground: root.fg
            fontFamily: root.fontFamily
            titleSize: Style.font.body
          }

          Column {
            id: settingsColumn
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.fg }

            PanelSectionHeader { text: "SERVER"; foreground: root.fg; fontFamily: root.fontFamily }

            FieldLabel { text: "Server URL" }
            TextField {
              id: sServer
              width: parent.width
              placeholderText: "https://ntfy.example.com"
              foreground: root.fg
              font.family: root.fontFamily
              onTextChanged: root.dServer = text
              Keys.onPressed: function(event) { root.handleSettingsKey(event) }
            }

            FieldLabel { text: "Topics (comma separated)" }
            TextField {
              id: sTopics
              width: parent.width
              placeholderText: "alerts,home,backups"
              foreground: root.fg
              font.family: root.fontFamily
              onTextChanged: root.dTopics = text
              Keys.onPressed: function(event) { root.handleSettingsKey(event) }
            }

            FieldLabel { text: "Authentication" }
            Row {
              spacing: Style.space(4)
              Repeater {
                model: [{ v: "none", l: "None" }, { v: "token", l: "Access token" }, { v: "basic", l: "Username + password" }]
                Button {
                  required property var modelData
                  text: modelData.l
                  selected: root.dAuth === modelData.v
                  bordered: true
                  focusable: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.dAuth = modelData.v
                }
              }
            }

            FieldLabel { visible: root.dAuth === "token"; text: "Access token" }
            TextField {
              id: sToken
              visible: root.dAuth === "token"
              width: parent.width
              placeholderText: "tk_…"
              password: true
              foreground: root.fg
              font.family: root.fontFamily
              onTextChanged: root.dToken = text
              Keys.onPressed: function(event) { root.handleSettingsKey(event) }
            }

            Row {
              visible: root.dAuth === "basic"
              width: parent.width
              spacing: Style.space(6)
              Column {
                width: (parent.width - Style.space(6)) / 2
                spacing: Style.space(4)
                FieldLabel { text: "Username" }
                TextField {
                  id: sUser
                  width: parent.width
                  foreground: root.fg
                  font.family: root.fontFamily
                  onTextChanged: root.dUser = text
                  Keys.onPressed: function(event) { root.handleSettingsKey(event) }
                }
              }
              Column {
                width: (parent.width - Style.space(6)) / 2
                spacing: Style.space(4)
                FieldLabel { text: "Password" }
                TextField {
                  id: sPass
                  width: parent.width
                  password: true
                  foreground: root.fg
                  font.family: root.fontFamily
                  onTextChanged: root.dPass = text
                  Keys.onPressed: function(event) { root.handleSettingsKey(event) }
                }
              }
            }

            PanelSectionHeader { text: "NOTIFICATIONS"; foreground: root.fg; fontFamily: root.fontFamily; topPadding: Style.space(6) }

            SettingsToggle {
              label: "Desktop toasts"
              description: "Show an Omarchy toast for every new message"
              checked: root.dToasts
              onClicked: root.dToasts = !root.dToasts
            }

            Button {
              iconText: Model.priorityGlyph(root.dMinPriority)
              text: "Toast from priority " + root.dMinPriority + " (" + root.priorityCaption(root.dMinPriority) + ") and up"
              enabled: root.dToasts
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Click to cycle 1–5"
              onClicked: root.cycleMinPriority()
            }

            SettingsToggle {
              label: "Allow HTTP actions"
              description: "Let publishers attach buttons that send HTTP requests from this machine"
              checked: root.dAllowHttp
              onClicked: root.dAllowHttp = !root.dAllowHttp
            }

            PanelSectionHeader { text: "BAR"; foreground: root.fg; fontFamily: root.fontFamily; topPadding: Style.space(6) }

            SettingsToggle {
              label: "Show unread count"
              checked: root.dShowCount
              onClicked: root.dShowCount = !root.dShowCount
            }

            SettingsToggle {
              label: "Show the count when it is zero"
              enabled: root.dShowCount
              opacity: root.dShowCount ? 1 : 0.5
              checked: root.dShowZero
              onClicked: root.dShowZero = !root.dShowZero
            }

            Row {
              id: bottomFields
              width: parent.width
              spacing: Style.space(6)
              readonly property real colWidth: (width - spacing * 2) / 3
              Column {
                width: bottomFields.colWidth
                spacing: Style.space(4)
                FieldLabel { text: "Bar glyph" }
                TextField {
                  id: sGlyph
                  width: parent.width
                  placeholderText: "󱗆"
                  foreground: root.fg
                  font.family: root.fontFamily
                  onTextChanged: root.dGlyph = text
                  Keys.onPressed: function(event) { root.handleSettingsKey(event) }
                }
              }
              Column {
                width: bottomFields.colWidth
                spacing: Style.space(4)
                FieldLabel { text: "Backfill on first run" }
                TextField {
                  id: sBackfill
                  width: parent.width
                  placeholderText: "all"
                  foreground: root.fg
                  font.family: root.fontFamily
                  onTextChanged: root.dBackfill = text
                  Keys.onPressed: function(event) { root.handleSettingsKey(event) }
                }
              }
              Column {
                width: bottomFields.colWidth
                spacing: Style.space(4)
                FieldLabel { text: "Messages kept" }
                TextField {
                  id: sMax
                  width: parent.width
                  placeholderText: "200"
                  foreground: root.fg
                  font.family: root.fontFamily
                  onTextChanged: root.dMaxMessages = text
                  Keys.onPressed: function(event) { root.handleSettingsKey(event) }
                }
              }
            }

            PanelSeparator { foreground: root.fg }

            Item {
              width: parent.width
              implicitHeight: Math.max(settingsButtons.implicitHeight, settingsStatusText.implicitHeight)

              Row {
                id: settingsButtons
                spacing: Style.space(6)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Button {
                  id: saveButton
                  iconText: "󰆓"
                  text: "Save"
                  width: Math.max(implicitWidth, cancelButton.implicitWidth)
                  height: Math.max(implicitHeight, cancelButton.implicitHeight)
                  bordered: true
                  focusable: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  tooltipText: "Enter"
                  onClicked: root.saveSettings()
                }
                Button {
                  id: cancelButton
                  text: "Cancel"
                  width: Math.max(implicitWidth, saveButton.implicitWidth)
                  height: Math.max(implicitHeight, saveButton.implicitHeight)
                  bordered: true
                  focusable: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  tooltipText: "Esc"
                  onClicked: root.closeSettings()
                }
              }

              Text {
                id: settingsStatusText
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - settingsButtons.implicitWidth - Style.space(10))
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                text: root.settingsStatus || "Saved to shell.json · Tab moves between fields"
                color: root.settingsError ? root.urgentColor : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Column {
          visible: !root.configured && !root.settingsOpen
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
            text: "Press s or the gear to open settings, or from a terminal:\nomarchy bar set xyzlab.pigeon server https://ntfy.example.com\nomarchy bar set xyzlab.pigeon topics alerts,home"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: !root.settingsOpen && root.configured && root.service && root.service.status === "error" && root.service.lastError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.service ? root.service.lastError : ""
          color: root.urgentColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator {
          visible: !root.settingsOpen && (root.showTabs || root.searchOpen || root.composeOpen || root.rows.length > 0)
          foreground: root.fg
        }

        Item {
          id: tabStrip
          visible: root.showTabs && !root.settingsOpen
          width: parent.width
          height: tabRow.implicitHeight
          readonly property int gap: Style.space(4)
          readonly property int pad: Style.space(6)
          property var fit: []

          function scheduleFit() { Qt.callLater(refit) }

          function refit() {
            var naturals = []
            for (var i = 0; i < tabRepeater.count; i++) {
              var item = tabRepeater.itemAt(i)
              naturals.push(item ? item.naturalWidth : 0)
            }
            fit = Model.fitWidths(naturals, width, gap)
          }

          onWidthChanged: scheduleFit()

          Row {
            id: tabRow
            spacing: tabStrip.gap

            Repeater {
              id: tabRepeater
              model: root.topicTabs
              onItemAdded: tabStrip.scheduleFit()
              onItemRemoved: tabStrip.scheduleFit()

              Item {
                id: tabItem
                required property var modelData
                required property int index
                readonly property string suffix: modelData.unread > 0 ? "  " + modelData.unread : ""
                readonly property string fullLabel: modelData.label + suffix
                readonly property real naturalWidth: probe.implicitWidth
                readonly property real assigned: tabStrip.fit[index] > 0 ? tabStrip.fit[index] : naturalWidth
                width: assigned
                height: tab.implicitHeight
                onNaturalWidthChanged: tabStrip.scheduleFit()

                Button {
                  id: probe
                  visible: false
                  text: tabItem.fullLabel
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: tabStrip.pad
                  verticalPadding: Style.space(3)
                }

                Button {
                  id: tab
                  width: tabItem.assigned
                  text: Model.fitLabel(tabItem.modelData.label, tabItem.suffix, tabItem.naturalWidth, tabItem.assigned, tabStrip.pad * 2)
                  selected: root.topicFilter === tabItem.modelData.topic
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: tabStrip.pad
                  verticalPadding: Style.space(3)
                  onClicked: root.topicFilter = tabItem.modelData.topic
                }
              }
            }
          }
        }

        TextField {
          id: searchField
          visible: root.searchOpen && !root.settingsOpen
          width: parent.width
          placeholderText: "Filter messages"
          foreground: root.fg
          font.family: root.fontFamily
          onTextChanged: root.query = text
          Keys.onPressed: function(event) { root.handleEditorKey(event, "search") }
        }

        Column {
          visible: root.composeOpen && !root.settingsOpen
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
            placeholderText: "Message, Enter sends, Esc closes"
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

        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(460))
          visible: root.rows.length > 0 && !root.settingsOpen
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

        Text {
          visible: root.rows.length === 0 && root.configured && !root.settingsOpen
          width: parent.width
          wrapMode: Text.Wrap
          text: root.query !== ""
            ? "Nothing matches \"" + root.query + "\""
            : (root.topicFilter ? "No messages in #" + root.topicFilter + " yet" : (root.connected ? "Inbox is empty, waiting for messages" : "No messages yet"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Text {
          visible: root.rows.length > 0 && !root.composeOpen && !root.settingsOpen
          width: parent.width
          textFormat: Text.PlainText
          text: "j/k move · ⏎ expand · o link · d delete · u read all · c compose · / search · s settings"
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
