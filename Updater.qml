import QtQuick
import Quickshell
import Quickshell.Io
import "updates.js" as Updates

// Offers new releases of To Do the way a desktop app offers its updates: it
// checks shortly after the shell starts, every four hours, and when the
// update button is clicked; it downloads a release when asked, and installs
// it with a restart of the shell. The update script next to this file does
// the work.
Item {
  id: updater
  visible: false

  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("update")).replace(/^file:\/\//, ""))

  // "": nothing to offer (up to date, not checked yet, offline, or no git
  // checkout). Otherwise available, downloading, downloaded, installing, or
  // failed (the download; the shell's log says why).
  property string status: ""
  property string version: ""
  // The installed release (`update version`): the tags hold the version, not
  // manifest.json. "" before the first release or without a git checkout.
  property string installed: ""
  // Whether installed is set: `update version` runs after the shell starts.
  property bool installedKnown: false

  // A check is running, on a timer or because the update button asked.
  readonly property bool checking: worker.running && worker.command[1] === "check"
  // Why the last check the update button asked for failed; "" again once
  // any check works. A failed check on the timer does not set it.
  property string checkError: ""
  // A check the update button asked for found no newer release. True for a
  // few seconds, so the button can say so.
  property bool confirmedCurrent: false
  // The update button asked for the running check.
  property bool checkAsked: false

  // The update button for the window or the drop-down; null hides it
  // (updates.js).
  function buttonFor(inWindow) {
    return Updates.button({
      status: status, version: version, installed: installed, checking: checking,
      checkError: checkError, confirmedCurrent: confirmedCurrent
    }, inWindow)
  }

  // asked: the update button wants the result shown, not only a newer release.
  function check(asked) {
    if (status === "installing") return
    if (asked) {
      checkAsked = true
      checkError = ""
      confirmedCurrent = false
    }
    // A running check answers the button too.
    if (worker.running) return
    run(["check"])
  }

  // The update button's one action in each state.
  function act() {
    if (status === "") {
      check(true)
      return
    }
    if (worker.running) return
    if (status === "available" || status === "failed") {
      status = "downloading"
      run(["download", version])
    } else if (status === "downloaded") {
      status = "installing"
      // Detached: installing changes this plugin's files, so the shell
      // reloads it, and the restart ends the shell.
      Quickshell.execDetached(["setsid", "-f", script, "install", version])
      // Still here after that means it failed; the script said why in a
      // notification.
      settle.restart()
    }
  }

  function run(args) {
    worker.command = [script].concat(args)
    worker.running = true
  }

  function finished(action, exitCode, output, message) {
    if (action === "check") {
      var asked = checkAsked
      checkAsked = false
      if (exitCode !== 0) console.warn("omarchy-todo: update check failed:", message)
      var change = Updates.checked(exitCode, output, message, asked)
      if (change.checkError !== undefined) checkError = change.checkError
      if (change.status !== undefined) {
        status = change.status
        version = change.version
      }
      if (change.confirm) {
        confirmedCurrent = true
        confirmation.restart()
      }
    } else if (action === "download") {
      status = exitCode === 0 ? "downloaded" : "failed"
      if (exitCode !== 0) console.warn("omarchy-todo: update download failed:", message)
    }
  }

  Process {
    id: worker
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(exitCode) {
      updater.finished(command[1], exitCode, String(out.text || ""), String(err.text || "").trim())
    }
  }

  Process {
    command: [updater.script, "version"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        updater.installed = text.trim()
        updater.installedKnown = true
      }
    }
  }

  // The first check waits until the shell has settled after starting.
  Timer {
    interval: 15000
    running: true
    onTriggered: updater.check()
  }

  Timer {
    interval: 4 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: updater.check()
  }

  Timer {
    id: confirmation
    interval: 4000
    onTriggered: updater.confirmedCurrent = false
  }

  Timer {
    id: settle
    interval: 60000
    onTriggered: {
      updater.status = ""
      updater.check()
    }
  }
}
