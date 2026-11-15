import QtQuick
import Quickshell
import Quickshell.Io

// Offers new releases of To Do the way a desktop app offers its updates: it
// checks shortly after the shell starts and every four hours, downloads a
// release when asked, and installs it with a restart of the shell. The
// update script next to this file does the work.
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

  function check() {
    if (worker.running || status === "installing") return
    run(["check"])
  }

  // The update button's one action in each state.
  function act() {
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
      var words = output.trim().split(" ")
      if (exitCode !== 0) {
        // Keep what an earlier check found; offline is no reason to hide it.
        console.warn("omarchy-todo: update check failed:", message)
      } else if (words[0] === "available" || words[0] === "downloaded") {
        status = words[0]
        version = words[1]
      } else {
        status = ""
        version = ""
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
      onStreamFinished: updater.installed = text.trim()
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
    id: settle
    interval: 60000
    onTriggered: {
      updater.status = ""
      updater.check()
    }
  }
}
