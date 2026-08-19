import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Free-writing streak widget — a VIEWER, nothing more.
// All state and policy live in the omarchy-writing-streak CLI and its event
// log; this file shells out to `status` and renders. Never add streak math
// here (see reference/streak-reminder-widget-implementation-log.md).
//
// Anti-shaming rules (solution doc §4): the number 0 is never rendered;
// states are done | open | restart; no red, no ✗, no escalating anything.

Panel {
  id: root
  moduleName: "noviadi.writing-streak"
  ipcTarget: "noviadi.writing-streak"
  manageIpc: false

  property var status: null

  readonly property string state: status ? String(status.state) : ""
  readonly property int streak: status ? Number(status.streak) : 0
  readonly property int best: status ? Number(status.best) : 0
  readonly property bool todayDone: status ? status.todayDone === true : false

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/writing-streak"
  readonly property string cliBin: home + "/.local/bin/omarchy-writing-streak"
  readonly property string eventsPath: stateHome + "/events.jsonl"

  // ---- display strings (the token is the anti-shaming contract) ----------

  readonly property string token: {
    if (!status) return ""
    if (state === "done") return "✒ " + streak
    if (state === "open") return "✒ " + streak + "°"
    return "✒ ↻1" // restart: day 1 of a new run — never "0"
  }

  readonly property string stateLine: {
    if (!status) return "…"
    if (state === "done") return "Today: done"
    if (state === "open") return "Today: open"
    return "Today is day 1 of a new run"
  }

  readonly property string numbersLine: {
    var run = state === "restart" ? 1 : streak
    return "current run " + run + " · longest " + best
  }

  readonly property string footerLine: {
    if (!status) return ""
    var parts = [status.policy + " · pings " + hoursLabel(status.pingHours)]
    if (todayDone) {
      parts.push("day done — no more pings")
    } else if (status.nextPing) {
      var when = (status.nextPing.hour < 10 ? "0" : "") + status.nextPing.hour + ":00"
      parts.push(status.nextPing.tomorrow ? "next ping tomorrow " + when : "next ping " + when)
    }
    return parts.join(" · ")
  }

  function hoursLabel(hours) {
    var out = []
    for (var i = 0; i < hours.length; i++)
      out.push((hours[i] < 10 ? "0" : "") + hours[i])
    return out.join(" ")
  }

  readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"]

  readonly property real cellSize: Style.space(26)

  readonly property string monthLabel: {
    if (!status || !status.month) return ""
    var ym = String(status.month).split("-")
    return monthNames[Number(ym[1]) - 1] + " " + ym[0]
  }

  // Mon-first offset for day 1 of the month (status.firstWeekday is 0=Sunday).
  readonly property int leadingBlanks: status && status.firstWeekday !== undefined
    ? (Number(status.firstWeekday) + 6) % 7 : 0

  // ---- data plumbing ------------------------------------------------------

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function runAction(action) {
    if (actionProc.running) return
    actionProc.command = [root.cliBin, action]
    actionProc.running = true
  }

  visible: status !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: [root.cliBin, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && parsed.today) root.status = parsed
        } catch (e) { /* keep last good status */ }
      }
    }
  }

  Process {
    id: actionProc
    running: false
    command: [root.cliBin, "status"]
    onExited: function(exitCode) { root.refresh() }
  }

  // React the moment the CLI appends an event (mark/undo/reminder).
  FileView {
    path: root.eventsPath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      root.refresh()
    }
  }

  // And to the day rolling over with no file write (open -> restart at midnight).
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function mark(): string { root.runAction("mark"); return "ok" }
    function undo(): string { root.runAction("undo"); return "ok" }
    function toggleMark(): string { root.runAction("toggle"); return "ok" }
  }

  // ---- bar item -----------------------------------------------------------

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.token
    fontSize: Style.font.caption
    tooltipText: "Free writing — " + root.numbersLine
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runAction("toggle")
      else root.toggle()
    }
  }

  // ---- panel --------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onActivateRequested: root.runAction("toggle")
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // header
          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: glyphText
              text: "✒"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: nameText
              text: "Free writing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Item {
              height: 1
              width: parent.width - glyphText.width - nameText.width - numbersText.width - 2 * Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: numbersText
              text: root.numbersLine
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // state line
          Text {
            width: parent.width
            text: root.stateLine
            color: root.state === "done" ? root.foreground : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // month grid
          Text {
            text: root.monthLabel
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            columns: 7
            spacing: Style.space(4)
            anchors.horizontalCenter: parent.horizontalCenter

            // weekday header, Monday-first
            Repeater {
              model: ["M", "T", "W", "T", "F", "S", "S"]
              Text {
                required property string modelData
                width: cellSize
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // leading blanks
            Repeater {
              model: root.leadingBlanks
              Item { width: cellSize; height: cellSize }
            }

            // days — data not verdict: done = filled, missed = faint outline,
            // open today = accent ring, future = near-invisible.
            Repeater {
              model: root.status && root.status.grid ? root.status.grid : []

              delegate: Rectangle {
                required property var modelData
                readonly property bool dayDone: modelData.done === true
                readonly property bool isFuture: modelData.future === true
                readonly property bool isToday: modelData.isToday === true
                readonly property int dayOfMonth: Number(String(modelData.date).slice(8))

                width: cellSize
                height: cellSize
                radius: Math.min(Style.cornerRadius, cellSize / 4)
                color: dayDone && !isFuture ? root.foreground : "transparent"
                opacity: isFuture ? 0.10
                  : dayDone ? 0.88
                  : isToday ? 1.0
                  : 0.30
                border.width: isToday ? Math.max(1, Style.space(1)) : (dayDone ? 0 : 1)
                border.color: isToday ? root.accent : root.dim

                Text {
                  anchors.centerIn: parent
                  // anchor numbers only: the 1st and every 7th day
                  visible: parent.dayOfMonth === 1 || parent.dayOfMonth % 7 === 1
                  text: parent.dayOfMonth
                  color: parent.dayDone && !parent.isFuture ? root.surface : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // action
          Button {
            width: parent.width
            text: root.todayDone ? "Undo today's mark" : "Mark today done"
            onClicked: root.runAction("toggle")
          }

          // footer
          Text {
            width: parent.width
            text: root.footerLine
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }
  }
}
