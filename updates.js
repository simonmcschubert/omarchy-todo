.pragma library

// The update button's states without QML: what a finished `update check`
// means, and which button each state shows. Updater.qml runs the update
// script and the timers; the node tests in test/ load this file directly.
//
// State, as Updater.qml keeps it:
//   status            "": nothing to offer; else available, downloading,
//                     downloaded, installing, or failed (the download)
//   version           the release offered
//   installed         the installed release, "" before the first one
//   checking          a check is running
//   checkError        why the last check the button asked for failed
//   confirmedCurrent  a check the button asked for found nothing newer

// Nerd Font icons.
var DOWNLOAD = ""
var RESTART = ""
var SPINNER = ""
var WARNING = ""
var REFRESH = ""
var CHECK = ""

// What a finished check changes. exitCode, output (stdout), and message
// (stderr) are the script's; asked: the update button asked for this check,
// so its result is shown. Returns only the fields that change, plus confirm:
// show "Up to date" for a few seconds.
function checked(exitCode, output, message, asked) {
  if (exitCode !== 0) {
    // Keep what an earlier check found; offline is no reason to hide it.
    // The script's own reason is the last line, after git's.
    if (!asked) return {}
    return { checkError: String(message).split("\n").pop().replace(/^update: /, "") || "the update script failed" }
  }
  var words = String(output).trim().split(" ")
  if (words[0] === "available" || words[0] === "downloaded")
    return { checkError: "", status: words[0], version: words[1] }
  return { checkError: "", status: "", version: "", confirm: asked === true }
}

// The update button for a state; null hides it. The window always shows it,
// as a circle that checks for updates when clicked. The drop-down shows it
// only to offer a release. color: "accent", "urgent", or "normal".
function button(state, inWindow) {
  var name = "To Do " + state.version
  switch (state.status) {
  case "available":
    return { icon: DOWNLOAD, text: "Update", color: "accent", tip: name + " is available. Click to download it." }
  case "downloading":
    return { icon: DOWNLOAD, text: "Downloading", color: "accent", tip: "Downloading " + name + "." }
  case "downloaded":
    return { icon: RESTART, text: "Restart to update", color: "accent",
             tip: name + " is downloaded. Click to restart the Omarchy shell with it. Your tasks stay as they are." }
  case "installing":
    return { icon: SPINNER, text: "Updating", color: "accent", tip: "Installing " + name + " and restarting the shell.", busy: true }
  case "failed":
    return { icon: WARNING, text: "Update failed", color: "urgent", tip: "Can't download " + name + ". Click to try again." }
  }
  if (!inWindow) return null
  var installed = state.installed !== "" ? "To Do " + state.installed : "To Do"
  if (state.checking)
    return { icon: REFRESH, text: "", color: "normal", tip: "Checking for updates…", busy: true }
  if (state.checkError !== "")
    return { icon: WARNING, text: "Can't check", color: "urgent",
             tip: "Can't check for updates: " + state.checkError + ". Click to try again." }
  if (state.confirmedCurrent)
    return { icon: CHECK, text: "Up to date", color: "normal", tip: installed + " is up to date." }
  return { icon: REFRESH, text: "", color: "normal",
           tip: (state.installed !== "" ? installed + " is installed. " : "") + "Click to check for updates." }
}
