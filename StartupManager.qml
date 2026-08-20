import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "rajaniraiyn.startup-manager"
  ipcTarget: "rajaniraiyn.startup-manager"

  property string scope: "user"
  property var items: []
  property var summary: ({})
  property string query: ""
  property string errorText: ""
  property string noticeText: ""
  property bool includeAll: false
  property int selectedIndex: 0
  property bool cursorActive: false
  property var pendingItem: null
  property string pendingAction: ""

  readonly property var visibleItems: Model.filtered(items, query)
  readonly property string helperPath: {
    var value = String(Qt.resolvedUrl("bin/omarchy-startupctl"))
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool busy: listProc.running || actionProc.running

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (listProc.running || actionProc.running) return
    errorText = ""
    noticeText = ""
    var command = [helperPath, "list", "--scope", scope]
    if (includeAll && scope !== "autostart") command.push("--all")
    listProc.command = command
    listProc.running = true
  }

  function updatePayload(raw) {
    var result = Model.parsePayload(raw)
    if (!result.ok) {
      errorText = "Could not read startup state"
      items = []
      summary = ({})
      return
    }
    items = result.items
    summary = result.summary
    selectedIndex = Math.max(0, Math.min(selectedIndex, visibleItems.length - 1))
  }

  function selectScope(nextScope) {
    if (scope === nextScope || busy) return
    scope = nextScope
    selectedIndex = 0
    cursorActive = false
    refresh()
  }

  function requestAction(item, action) {
    if (!item || item.protected || !item.mutable || busy) return
    pendingItem = item
    pendingAction = action
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function runPendingAction() {
    confirmDialog.opened = false
    if (!pendingItem || pendingAction === "") return
    errorText = ""
    noticeText = ""
    actionProc.command = [helperPath, "action", "--scope", pendingItem.scope,
                          "--unit", pendingItem.id, "--action", pendingAction]
    actionProc.running = true
  }

  function selectedItem() {
    if (visibleItems.length === 0) return null
    return visibleItems[Math.max(0, Math.min(selectedIndex, visibleItems.length - 1))]
  }

  function defaultAction(item) {
    if (!item || item.protected || !item.mutable) return
    if (item.scope === "autostart") requestAction(item, item.enabled ? "disable" : "enable")
    else requestAction(item, item.running ? "stop" : "start")
  }

  function moveSelection(delta) {
    if (visibleItems.length === 0) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(visibleItems.length - 1, selectedIndex + delta))
    Qt.callLater(function() {
      var child = rowsRepeater.itemAt(selectedIndex)
      var flick = listView.contentItem
      if (!child || !flick) return
      if (child.y < flick.contentY) flick.contentY = child.y
      else if (child.y + child.height > flick.contentY + flick.height)
        flick.contentY = child.y + child.height - flick.height
    })
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      selectedIndex = 0
      refresh()
    } else {
      query = ""
      confirmDialog.opened = false
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updatePayload(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim()
    }
    onExited: function(code) {
      if (code !== 0 && root.errorText === "") root.errorText = "Startup helper exited with code " + code
    }
  }

  Process {
    id: actionProc
    property string resultText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProc.resultText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim()
    }
    onExited: function(code) {
      if (actionProc.resultText !== "") {
        try {
          var payload = JSON.parse(actionProc.resultText)
          if (payload.ok) root.noticeText = payload.message || "Action completed"
          else root.errorText = payload.error || "Action failed"
        } catch (error) {
          root.errorText = "Invalid response from startup helper"
        }
      } else if (code !== 0 && root.errorText === "") {
        root.errorText = "Action failed with code " + code
      }
      pendingItem = null
      pendingAction = ""
      actionProc.resultText = ""
      refreshDelay.restart()
    }
  }

  Timer {
    id: refreshDelay
    interval: 250
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.busy ? "󰑓" : "󰒓"
    tooltipText: "Startup Manager"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && root.opened) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(720))
    contentHeight: panel.cappedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || confirmDialog.opened
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
        else if (dx < 0) {
          if (root.scope === "system") root.selectScope("user")
          else if (root.scope === "autostart") root.selectScope("system")
        } else if (dx > 0) {
          if (root.scope === "user") root.selectScope("system")
          else if (root.scope === "system") root.selectScope("autostart")
        }
      }
      onActivateRequested: root.defaultAction(root.selectedItem())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "/") searchField.forceActiveFocus()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "a" || text === "A") {
          root.includeAll = !root.includeAll
          root.refresh()
        }
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "󰒓"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text {
              text: "Startup Manager"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.busy
                ? "READING SYSTEM STATE"
                : ((root.summary.running || 0) + " RUNNING  ·  "
                   + (root.summary.enabled || 0) + " ENABLED  ·  "
                   + (root.summary.protected || 0) + " PROTECTED")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
            }
          }

          Button {
            iconText: "󰑐"
            tooltipText: "Refresh (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.busy
            onClicked: root.refresh()
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: [
              { id: "user", label: "User services" },
              { id: "system", label: "System services" },
              { id: "autostart", label: "Login apps" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              foreground: root.foreground
              fontFamily: root.fontFamily
              selected: root.scope === modelData.id
              bordered: true
              onClicked: root.selectScope(modelData.id)
            }
          }

          Item { Layout.fillWidth: true }

          Button {
            visible: root.scope !== "autostart"
            text: root.includeAll ? "All units" : "Startup only"
            iconText: root.includeAll ? "󰄬" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            selected: root.includeAll
            bordered: true
            onClicked: {
              root.includeAll = !root.includeAll
              root.refresh()
            }
          }
        }

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search services and startup apps…  (press /)"
          foreground: root.foreground
          accent: Color.accent
          onTextChanged: {
            root.query = text
            root.selectedIndex = 0
          }
          Keys.onEscapePressed: function(event) {
            text = ""
            keyCatcher.forceActiveFocus()
            event.accepted = true
          }
          Keys.onReturnPressed: function(event) {
            keyCatcher.forceActiveFocus()
            event.accepted = true
          }
        }

        BorderSurface {
          visible: root.errorText !== "" || root.noticeText !== ""
          width: parent.width
          implicitHeight: messageText.implicitHeight + Style.space(12)
          color: root.errorText !== ""
            ? Util.alpha(root.urgent, 0.12)
            : Util.alpha(root.foreground, 0.06)
          borderSpec: Border.flat(root.errorText !== "" ? root.urgent : root.dim, Style.normalBorderWidth)
          radius: Style.cornerRadius

          Text {
            id: messageText
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.errorText !== "" ? root.errorText : root.noticeText
            color: root.errorText !== "" ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        QQC.ScrollView {
          id: listView
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
          QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded

          Column {
            id: rowsColumn
            width: listView.availableWidth
            spacing: Style.space(4)

            Text {
              visible: !root.busy && root.visibleItems.length === 0
              width: parent.width
              topPadding: Style.space(48)
              text: root.query === "" ? "No startup items in this view" : "No matching startup items"
              horizontalAlignment: Text.AlignHCenter
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              id: rowsRepeater
              model: root.visibleItems

              CursorSurface {
                required property var modelData
                required property int index
                width: rowsColumn.width
                implicitHeight: Style.space(62)
                hasCursor: root.cursorActive && root.selectedIndex === index
                foreground: root.foreground
                accent: Color.accent
                bordered: true

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  onEntered: {
                    root.cursorActive = true
                    root.selectedIndex = index
                  }
                  onClicked: root.defaultAction(modelData)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  Rectangle {
                    Layout.preferredWidth: Style.space(8)
                    Layout.preferredHeight: Style.space(8)
                    radius: width / 2
                    color: modelData.failed ? root.urgent
                      : (modelData.running ? Color.accent : root.dim)
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)
                    Text {
                      Layout.fillWidth: true
                      text: modelData.name || modelData.id
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      Layout.fillWidth: true
                      text: (modelData.description || modelData.kind || "")
                        + (Model.memory(modelData.memory_bytes) !== "" ? "  ·  " + Model.memory(modelData.memory_bytes) : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: modelData.protected ? "󰌾 " + modelData.protected_reason : Model.status(modelData)
                    color: modelData.failed ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.maximumWidth: Style.space(190)
                    elide: Text.ElideRight
                  }

                  RowLayout {
                    visible: !modelData.protected && modelData.mutable
                    spacing: Style.space(4)

                    PanelActionButton {
                      visible: modelData.scope !== "autostart"
                      iconText: modelData.running ? "󰓛" : "󰐊"
                      tooltipText: modelData.running ? "Stop" : "Start"
                      foreground: root.foreground
                      hoverColor: modelData.running ? root.urgent : root.foreground
                      onClicked: root.requestAction(modelData, modelData.running ? "stop" : "start")
                    }
                    PanelActionButton {
                      visible: modelData.scope !== "autostart" && modelData.running
                      iconText: "󰑐"
                      tooltipText: "Restart"
                      foreground: root.foreground
                      onClicked: root.requestAction(modelData, "restart")
                    }
                    PanelActionButton {
                      iconText: modelData.enabled ? "󰅖" : "󰄬"
                      tooltipText: modelData.enabled ? "Disable startup" : "Enable startup"
                      foreground: root.foreground
                      hoverColor: modelData.enabled ? root.urgent : root.foreground
                      onClicked: root.requestAction(modelData, modelData.enabled ? "disable" : "enable")
                    }
                  }
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        foreground: root.foreground
        message: root.pendingItem
          ? Model.actionLabel(root.pendingAction) + " for " + root.pendingItem.name + "?\n\n"
            + (root.pendingAction === "disable"
               ? "It will remain available, but will not start automatically."
               : root.pendingAction === "stop"
                 ? "It can be started again without logging out."
                 : "This changes the current system state.")
          : ""
        confirmText: Model.actionLabel(root.pendingAction)
        onCanceled: {
          opened = false
          root.pendingItem = null
          root.pendingAction = ""
          keyCatcher.forceActiveFocus()
        }
        onConfirmed: root.runPendingAction()
      }
    }
  }
}
