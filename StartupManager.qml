import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

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
  property bool loading: false
  property bool refreshQueued: false

  readonly property var visibleItems: Model.filtered(items, query)
  readonly property string helperPath: {
    var value = String(Qt.resolvedUrl("bin/omarchy-startupctl"))
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: Color.popups.text
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: Style.font.family
  readonly property bool busy: loading || actionProc.running

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (error) {}
    if (payload.scope === "user" || payload.scope === "system" || payload.scope === "autostart")
      scope = payload.scope
    opened = true
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() { opened = false }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "rajaniraiyn.startup-manager")
    else close()
  }

  function refresh(clearModel) {
    if (clearModel === undefined) clearModel = false
    if (actionProc.running) return
    if (clearModel) {
      items = []
      summary = ({})
      selectedIndex = 0
      cursorActive = false
    }
    loading = true
    errorText = ""
    noticeText = ""
    if (listProc.running) {
      refreshQueued = true
      return
    }
    var command = [helperPath, "list", "--scope", scope]
    if (includeAll && scope !== "autostart") command.push("--all")
    listProc.requestScope = scope
    listProc.requestIncludeAll = includeAll
    listProc.resultText = ""
    listProc.errorResult = ""
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
    if (scope === nextScope) return
    scope = nextScope
    refresh(true)
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
    listView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      selectedIndex = 0
      refresh(true)
    } else {
      query = ""
      confirmDialog.opened = false
    }
  }

  Process {
    id: listProc
    property string requestScope: ""
    property bool requestIncludeAll: false
    property string resultText: ""
    property string errorResult: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: listProc.resultText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: listProc.errorResult = text.trim()
    }
    onExited: function(code) {
      var currentRequest = listProc.requestScope === root.scope
        && listProc.requestIncludeAll === root.includeAll
      if (currentRequest) {
        if (code === 0) root.updatePayload(listProc.resultText)
        else root.errorText = listProc.errorResult !== ""
          ? listProc.errorResult
          : "Startup helper exited with code " + code
        root.loading = false
      }
      listProc.resultText = ""
      listProc.errorResult = ""
      if (root.refreshQueued || !currentRequest) {
        root.refreshQueued = false
        Qt.callLater(function() { root.refresh(false) })
      }
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
    onTriggered: root.refresh(true)
  }

  FloatingWindow {
    id: window
    title: "Omarchy Startup Manager"
    visible: root.opened
    color: Color.popups.background
    implicitWidth: 875
    implicitHeight: 600
    minimumSize: Qt.size(680, 500)

    onVisibleChanged: {
      if (!visible && root.opened) root.dismiss()
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: Style.spacing.popupPadding
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
        onCloseRequested: root.dismiss()
        onTextKey: function(text) {
          if (text === "/") searchField.forceActiveFocus()
          else if (text === "r" || text === "R") root.refresh(false)
          else if (text === "a" || text === "A") {
            root.includeAll = !root.includeAll
            root.refresh(true)
          }
        }

      Column {
        anchors.fill: parent
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool loading: root.loading
          function refreshPanel() { root.refresh(false) }

          PanelHero {
            id: hero
            width: parent.width
            title: "Startup Manager"
            meta: root.loading
              ? "Reading " + (root.scope === "autostart" ? "login applications" : root.scope + " services")
              : ((root.summary.running || 0) + " running  ·  "
                 + (root.summary.enabled || 0) + " enabled  ·  "
                 + (root.summary.protected || 0) + " protected")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰒓"
                color: hero.foreground
                font.family: hero.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Button {
                iconText: "󰑐"
                iconSpinning: header.loading
                tooltipText: header.loading ? "Reading system state" : "Refresh (R)"
                foreground: hero.foreground
                fontFamily: hero.fontFamily
                bordered: true
                enabled: !header.loading && !actionProc.running
                onClicked: header.refreshPanel()
              }
            }
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          ButtonGroup {
            options: [
              { value: "user", label: "User services" },
              { value: "system", label: "System services" },
              { value: "autostart", label: "Login apps" }
            ]
            value: root.scope
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            onChanged: function(value) { root.selectScope(value) }
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
              root.refresh(true)
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

        Item {
          id: listArea
          width: parent.width
          height: Math.max(0, parent.height - y)

          ListView {
            id: listView
            anchors.fill: parent
            visible: !root.loading
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(4)
            model: root.visibleItems
            keyNavigationEnabled: false
            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

            delegate: CursorSurface {
                required property var modelData
                required property int index
                width: listView.width
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

          Column {
            anchors.centerIn: parent
            visible: root.loading
            spacing: Style.space(12)

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(7)

              Repeater {
                model: 3

                Rectangle {
                  required property int index
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.foreground

                  SequentialAnimation on opacity {
                    running: root.loading
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 120 }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { from: 1.0; to: 0.25; duration: 360; easing.type: Easing.InCubic }
                    PauseAnimation { duration: (2 - index) * 120 }
                  }
                }
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Loading " + (root.scope === "autostart" ? "login applications" : root.scope + " services") + "…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !root.loading && root.visibleItems.length === 0
            text: root.query === "" ? "No startup items in this view" : "No matching startup items"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
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
}
