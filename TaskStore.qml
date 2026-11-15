import QtQuick
import Quickshell
import Quickshell.Io
import "tasks.js" as Tasks

// Loads and saves the task list. The drop-down and the window share one store.
Item {
  id: store
  visible: false

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string directory: stateHome + "/omarchy-todo"
  readonly property string filePath: directory + "/tasks.json"

  // ErrorReports, or null.
  property var reports: null

  property var tasks: []
  property bool ready: false
  property string error: ""
  property string today: Tasks.dateKey(new Date())
  property string lastText: ""

  readonly property var openRows: Tasks.rows(Tasks.openSections(tasks, today))
  readonly property var doneRows: Tasks.rows(Tasks.doneSections(tasks, today))
  readonly property int openCount: Tasks.countOpen(tasks)
  readonly property int doneCount: Tasks.countDone(tasks)

  function apply(text) {
    if (ready && error === "" && text === lastText) return
    var result = Tasks.parseStore(text)
    ready = true
    if (!result.ok) {
      // Never overwrite a file this version cannot read.
      fail("unreadable-file", "Can't read " + filePath + " (" + result.error + "). Changes are not saved until the file is fixed or moved away.", result.error)
      return
    }
    error = ""
    lastText = text
    tasks = result.tasks
  }

  // Shows the error and reports it. kind groups the reports.
  function fail(kind, message, detail) {
    error = message
    if (reports) reports.captureMessage(kind, message, detail || "")
  }

  // Runs an action; an exception in it is reported, then thrown on.
  function run(action, fn) {
    try {
      return fn()
    } catch (e) {
      if (reports) reports.captureException(e, action)
      throw e
    }
  }

  function commit(next) {
    if (!ready || error !== "" || next === tasks) return false
    var text = Tasks.serialize(next)
    lastText = text
    tasks = next
    file.setText(text)
    return true
  }

  // Returns the new task's id, or "" when nothing was added.
  function add(text, due) {
    return run("add", function() {
      var next = Tasks.addTask(tasks, text, due, Date.now(), Math.random())
      return next !== tasks && commit(next) ? next[0].id : ""
    })
  }
  function setDone(id, done) { return run("setDone", function() { return commit(Tasks.setDone(tasks, id, done, Date.now())) }) }
  function toggleStar(id) { return run("toggleStar", function() { return commit(Tasks.toggleStar(tasks, id)) }) }
  function setDue(id, due) { return run("setDue", function() { return commit(Tasks.setDue(tasks, id, due)) }) }
  function remove(id) { return run("remove", function() { return commit(Tasks.removeTask(tasks, id)) }) }
  function clearDone() { return run("clearDone", function() { return commit(Tasks.clearDone(tasks)) }) }

  function refreshToday() {
    var key = Tasks.dateKey(new Date())
    if (key !== today) today = key
  }

  // The directory is private (0700), also when it already exists. The file
  // is only read after it.
  Process {
    command: ["install", "-d", "-m", "700", store.directory]
    running: true
    onExited: function(exitCode) {
      if (exitCode !== 0) store.fail("create-directory", "Can't create " + store.directory + ".", "exit " + exitCode)
      file.path = store.filePath
    }
  }

  FileView {
    id: file
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: store.run("load", function() { store.apply(file.text()) })
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        store.apply("")
      } else {
        store.ready = true
        store.fail("read-failed", "Can't read " + store.filePath + ".", "FileViewError " + error)
      }
    }
    onSaveFailed: function(error) {
      store.fail("save-failed", "Can't save " + store.filePath + ". Recent changes are not saved.", "FileViewError " + error)
    }
    onFileChanged: reload()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: store.refreshToday()
  }
}
