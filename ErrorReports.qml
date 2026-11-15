import QtQuick
import Quickshell
import "sentry.js" as Sentry

// Sends errors to the plugin's Sentry project. Off when DO_NOT_TRACK is set.
// Each error is sent once per shell session, at most maxEvents in all.
QtObject {
  id: reports

  readonly property string dsn: "https://3d67047e69cbc44478121e507a9407b8@o4511987937705984.ingest.de.sentry.io/4512433525162064"
  property string release: ""
  // Whether release names the installed version yet. It does not while the
  // shell starts the plugin, so errors from then (a tasks file it cannot
  // read) wait for it, but at most releaseWait ms.
  property bool releaseKnown: false
  property int releaseWait: 10000
  // The dev desktop sets SENTRY_ENVIRONMENT=development.
  property string environment: Quickshell.env("SENTRY_ENVIRONMENT") || "production"
  // URL of the plugin folder, ending in "/": its frames count as in-app.
  property string pluginUrl: ""
  property int maxEvents: 10

  readonly property var target: Sentry.parseDsn(dsn)
  readonly property bool enabled: target !== null && !Sentry.optedOut(Quickshell.env("DO_NOT_TRACK"))
  readonly property string home: Quickshell.env("HOME") || ""

  property var sent: ({})
  property int sentCount: 0
  // Events waiting for the release.
  property var waiting: []
  property bool waitedEnough: false
  readonly property bool ready: releaseKnown || waitedEnough

  onReadyChanged: if (ready) flush()

  property Timer releaseTimer: Timer {
    interval: reports.releaseWait
    running: !reports.ready
    onTriggered: reports.waitedEnough = true
  }

  function options() {
    return { release: release, environment: environment, pluginUrl: pluginUrl, home: home,
      os: Qt.platform.os, now: Date.now(), random: Math.random }
  }

  function captureException(error, action) {
    if (!enabled) return
    send("exception:" + action + ":" + (error && error.message), Sentry.exceptionEvent(error, action, options()))
  }

  function captureMessage(kind, message, detail) {
    if (!enabled) return
    send("message:" + kind + ":" + detail, Sentry.messageEvent(kind, message, detail, options()))
  }

  function send(key, event) {
    if (sent[key] || sentCount >= maxEvents) return
    sent[key] = true
    sentCount++
    if (ready) post(event)
    else waiting.push(event)
  }

  function flush() {
    var events = waiting
    waiting = []
    events.forEach(post)
  }

  function post(event) {
    event.release = release
    var request = new XMLHttpRequest()
    request.onreadystatechange = function() {
      if (request.readyState === XMLHttpRequest.DONE && (request.status < 200 || request.status >= 300))
        console.warn("omarchy-todo: error report not sent (HTTP " + request.status + ")")
    }
    request.open("POST", target.envelopeUrl)
    request.setRequestHeader("Content-Type", "application/x-sentry-envelope")
    request.send(Sentry.envelope(event, dsn, Date.now()))
  }
}
