import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// One inbox entry. Collapsed shows glyph, title, two lines of body and a
// meta line; expanded adds the full body, attachment preview, ntfy actions,
// click link, copy, and the absolute timestamp. Visual state follows the
// panel cursor (hasCursor) as every kit row does — never containsMouse.
CursorSurface {
  id: row

  required property var message
  required property int rowIndex
  property bool expanded: false
  property bool showTopic: true
  property bool allowHttp: false
  property var service: null
  property color fg: Color.foreground
  property color dim: Qt.darker(fg, 1.5)
  property color urgentColor: Color.urgent
  property string fontFamily: Style.font.family
  property double nowMs: Date.now()

  signal hovered(int rowIndex)
  signal activated(int rowIndex)

  readonly property var tags: Model.splitTags(message.tags)
  readonly property string leadGlyph: tags.emoji.length ? tags.emoji[0] : Model.priorityGlyph(message.priority)
  readonly property color leadColor: message.priority >= 5 ? urgentColor : (message.priority === 4 ? accent : (message.unread ? fg : dim))
  readonly property string timeText: Model.relativeTime(message.time, nowMs)
  readonly property var attachment: message.attachment
  readonly property bool hasAttachment: !!(attachment && attachment.url)
  readonly property bool isImage: Model.isImageAttachment(attachment)
  readonly property var actions: Model.toList(message.actions)
  readonly property string clickUrl: Model.safeHttpUrl(message.click)
  readonly property bool showInlineActions: hasCursor || mouse.containsMouse
  readonly property string priorityLabel: message.priority >= 5 ? "URGENT" : (message.priority === 4 ? "HIGH" : (message.priority <= 2 ? Model.priorityName(message.priority).toUpperCase() : ""))

  // Meta-line parts. Computed here rather than read back from the children's
  // `visible`: Item.visible reports effective visibility, so a container that
  // asks its children whether to show latches hidden once it hides.
  readonly property bool showTopicMeta: showTopic && message.topic !== ""
  readonly property bool showPriorityMeta: priorityLabel !== ""
  readonly property bool showAttachmentMeta: hasAttachment && !expanded
  readonly property bool showLinkMeta: clickUrl !== "" && !expanded
  readonly property bool showMeta: showTopicMeta || showPriorityMeta || tags.plain.length > 0 || showAttachmentMeta || showLinkMeta

  foreground: fg
  fill: Style.hoverFillFor(fg, accent)
  currentFill: Style.selectedFillFor(fg, accent)
  implicitHeight: content.implicitHeight + Style.space(14)

  function actionStateText(index) {
    if (!service) return ""
    var s = service.actionState(message, index)
    if (s === "running") return "…"
    if (s === "ok") return "✓"
    return s
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) row.hovered(row.rowIndex)
    onClicked: function(m) {
      if (m.button === Qt.LeftButton) row.activated(row.rowIndex)
      else if (m.button === Qt.MiddleButton) { if (row.service) row.service.remove(row.message.id) }
      else if (row.service) {
        if (!row.service.openClick(row.message)) row.service.copyMessage(row.message)
      }
    }
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    implicitHeight: Math.max(lead.implicitHeight, body.implicitHeight)

    Text {
      id: lead
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: Style.space(1)
      text: row.leadGlyph
      color: row.leadColor
      font.family: row.fontFamily
      font.pixelSize: Style.font.heading
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      id: body
      anchors.left: lead.right
      anchors.leftMargin: Style.space(10)
      anchors.right: trailing.left
      anchors.rightMargin: Style.space(8)
      anchors.top: parent.top
      spacing: Style.space(3)

      Item {
        width: parent.width
        implicitHeight: Math.max(titleText.implicitHeight, timeLabel.implicitHeight)

        Text {
          id: titleText
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: timeLabel.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: Model.displayTitle(row.message)
          color: row.fg
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.message.unread
          elide: Text.ElideRight
        }

        Text {
          id: timeLabel
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.timeText
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: messageText
        textFormat: Text.PlainText
        visible: text !== "" && (row.message.title !== "" || row.expanded || text !== Model.displayTitle(row.message))
        width: parent.width
        text: row.message.message
        color: row.message.unread ? row.fg : Qt.darker(row.fg, 1.15)
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        maximumLineCount: row.expanded ? 1000 : 2
        elide: Text.ElideRight
      }

      Flow {
        width: parent.width
        spacing: Style.space(8)
        visible: row.showMeta

        Text {
          id: metaTopic
          textFormat: Text.PlainText
          visible: row.showTopicMeta
          text: "#" + row.message.topic
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: metaPriority
          textFormat: Text.PlainText
          visible: row.showPriorityMeta
          text: row.priorityLabel
          color: row.message.priority >= 5 ? row.urgentColor : (row.message.priority === 4 ? row.accent : row.dim)
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: row.message.priority >= 4
          font.letterSpacing: 1
        }

        Repeater {
          model: row.tags.plain
          Text {
            required property var modelData
            textFormat: Text.PlainText
            text: "· " + modelData
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: metaAttachment
          textFormat: Text.PlainText
          visible: row.showAttachmentMeta
          text: "󰁦 " + (row.attachment ? row.attachment.name : "")
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, Style.space(160))
        }

        Text {
          id: metaLink
          textFormat: Text.PlainText
          visible: row.showLinkMeta
          text: "󰖟"
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Expanded extras
      Column {
        visible: row.expanded
        width: parent.width
        spacing: Style.space(8)
        topPadding: Style.space(4)

        Image {
          id: preview
          visible: row.isImage && status !== Image.Error
          width: parent.width
          height: status === Image.Ready && implicitWidth > 0
            ? Math.min(Style.space(220), Math.round(width * implicitHeight / implicitWidth))
            : (row.isImage ? Style.space(28) : 0)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          horizontalAlignment: Image.AlignLeft
          source: row.expanded && row.isImage ? row.attachment.url : ""
          sourceSize.width: 1200

          Text {
            anchors.centerIn: parent
            visible: preview.status === Image.Loading
            text: "Loading preview…"
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (row.service) row.service.openAttachment(row.message)
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Button {
            visible: row.hasAttachment
            iconText: "󰁦"
            text: (row.attachment ? row.attachment.name : "Attachment") + (row.attachment && row.attachment.size ? "  " + Model.fileSize(row.attachment.size) : "")
            foreground: row.fg
            fontFamily: row.fontFamily
            fontSize: Style.font.caption
            bordered: true
            tooltipText: "Open attachment"
            onClicked: if (row.service) row.service.openAttachment(row.message)
          }

          Button {
            visible: row.clickUrl !== ""
            iconText: "󰖟"
            text: "Open link"
            foreground: row.fg
            fontFamily: row.fontFamily
            fontSize: Style.font.caption
            bordered: true
            tooltipText: row.clickUrl
            onClicked: if (row.service) row.service.openClick(row.message)
          }

          Repeater {
            model: row.actions
            Button {
              required property var modelData
              required property int index
              readonly property string state: row.actionStateText(index)
              iconText: modelData.action === "view" ? "󰖟" : "󰘧"
              text: (index + 1) + " " + modelData.label + (state ? "  " + state : "")
              enabled: modelData.action === "view" || row.allowHttp
              foreground: row.fg
              fontFamily: row.fontFamily
              fontSize: Style.font.caption
              bordered: true
              tooltipText: modelData.action === "view"
                ? modelData.url
                : (row.allowHttp ? modelData.method + " " + modelData.url : "HTTP actions are disabled (allowHttpActions)")
              onClicked: if (row.service) row.service.runAction(row.message, index)
            }
          }

          Button {
            iconText: "󰆏"
            text: "Copy"
            foreground: row.fg
            fontFamily: row.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: if (row.service) row.service.copyMessage(row.message)
          }
        }

        Text {
          textFormat: Text.PlainText
          text: Model.absoluteTime(row.message.time) + (row.message.id ? "  ·  " + row.message.id : "")
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- Trailing: unread dot at rest, inline actions on hover/cursor.
    Item {
      id: trailing
      anchors.right: parent.right
      anchors.top: parent.top
      width: row.showInlineActions ? inlineActions.implicitWidth : Style.space(10)
      height: Math.max(Style.space(10), inlineActions.implicitHeight)

      Rectangle {
        visible: row.message.unread && !row.showInlineActions
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(4)
        width: Style.space(7)
        height: Style.space(7)
        radius: width / 2
        color: row.message.priority >= 5 ? row.urgentColor : row.accent
      }

      Row {
        id: inlineActions
        visible: row.showInlineActions
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(2)

        PanelActionButton {
          visible: row.clickUrl !== ""
          iconText: "󰖟"
          tooltipText: "Open link"
          foreground: row.fg
          fontFamily: row.fontFamily
          onClicked: if (row.service) row.service.openClick(row.message)
        }

        PanelActionButton {
          iconText: row.message.unread ? "󰄬" : "󰇮"
          tooltipText: row.message.unread ? "Mark as read" : "Mark as unread"
          foreground: row.fg
          fontFamily: row.fontFamily
          onClicked: if (row.service) row.service.markRead(row.message.id, row.message.unread)
        }

        PanelActionButton {
          iconText: "󰅙"
          tooltipText: "Delete"
          foreground: row.fg
          hoverColor: row.urgentColor
          fontFamily: row.fontFamily
          onClicked: if (row.service) row.service.remove(row.message.id)
        }
      }
    }
  }
}
