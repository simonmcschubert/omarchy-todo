// Tests for the update script against real git repositories: an "origin"
// with releases and a plugin checkout cloned from it. Omarchy's commands are
// stand-ins that log their calls. Run: node --test test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const SCRIPT = new URL("../update", import.meta.url).pathname

function sandbox(t) {
  const root = mkdtempSync(join(tmpdir(), "todo-update-"))
  t.after(() => rmSync(root, { recursive: true, force: true }))

  const bin = join(root, "bin")
  const log = join(root, "calls.log")
  mkdirSync(bin)
  const stub = (name, body) => {
    writeFileSync(join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\n${body}\n`)
    chmodSync(join(bin, name), 0o755)
  }
  // A release with a file named "broken" fails Omarchy's check.
  stub("omarchy-plugin-validate", '[[ ! -e $1/broken ]] || { echo "omarchy-plugin-validate: broken" >&2; exit 1; }')
  stub("omarchy-restart-shell", "")
  stub("notify-send", "")

  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_AUTHOR_NAME: "Test", GIT_AUTHOR_EMAIL: "test@example.com",
    GIT_COMMITTER_NAME: "Test", GIT_COMMITTER_EMAIL: "test@example.com",
  }
  const git = (cwd, ...args) => {
    const r = spawnSync("git", args, { cwd, env, encoding: "utf8" })
    assert.equal(r.status, 0, `git ${args.join(" ")}: ${r.stderr}`)
    return r.stdout.trim()
  }

  const origin = join(root, "origin")
  mkdirSync(origin)
  git(origin, "init", "--quiet", "--initial-branch=main")
  // Each commit carries the script, as every real release does.
  const commit = (message, files = {}) => {
    copyFileSync(SCRIPT, join(origin, "update"))
    writeFileSync(join(origin, "manifest.json"), "{}\n")
    for (const [name, text] of Object.entries(files)) writeFileSync(join(origin, name), text)
    git(origin, "add", "-A")
    git(origin, "commit", "--quiet", "--allow-empty", "-m", message)
    return git(origin, "rev-parse", "HEAD")
  }
  const release = (version, files) => {
    commit(`Release ${version}`, files)
    git(origin, "tag", "--annotate", `v${version}`, "--message", `v${version}`)
  }

  const plugin = join(root, "plugin")
  const install = (ref) => {
    git(root, "clone", "--quiet", origin, plugin)
    if (ref) git(plugin, "reset", "--quiet", "--hard", ref)
  }

  // stdin and stderr are pipes, as when the app runs it: no terminal.
  const run = (...args) => spawnSync(join(plugin, "update"), args, { env, encoding: "utf8" })
  const calls = () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : [])
  const head = () => git(plugin, "rev-parse", "HEAD")

  return { root, origin, plugin, git, commit, release, install, run, calls, head }
}

test("check finds the newest release on origin", (t) => {
  const s = sandbox(t)
  s.commit("Initial")
  s.install()
  assert.equal(s.run("check").stdout, "current\n", "no releases yet")

  s.release("0.9.0")
  s.release("0.10.0")
  s.git(s.origin, "tag", "v2.0.0-rc.1") // candidates and other tags are no releases
  s.git(s.origin, "tag", "latest")
  const r = s.run("check")
  assert.equal(r.status, 0, r.stderr)
  assert.equal(r.stdout, "available 0.10.0\n")
})

test("check reads lightweight tags too", (t) => {
  const s = sandbox(t)
  s.commit("Initial")
  s.install()
  s.commit("Change")
  s.git(s.origin, "tag", "v0.2.0")
  assert.equal(s.run("check").stdout, "available 0.2.0\n")
})

test("check says current at or past the newest release", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.commit("Unreleased")
  s.install("v0.1.0")
  assert.equal(s.run("check").stdout, "current\n")

  rmSync(s.plugin, { recursive: true })
  s.install() // main, ahead of v0.1.0
  assert.equal(s.run("check").stdout, "current\n")
})

test("download fetches the release and changes no files", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.install()
  s.release("0.2.0", { "new.txt": "new\n" })
  const before = s.head()

  const r = s.run("download", "0.2.0")
  assert.equal(r.status, 0, r.stderr)
  assert.equal(s.head(), before)
  assert.equal(existsSync(join(s.plugin, "new.txt")), false)
  assert.equal(s.run("check").stdout, "downloaded 0.2.0\n")
  assert.deepEqual(s.calls(), [])
})

test("install moves to the release, restarts the shell, and says so", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.install()
  s.release("0.2.0", { "new.txt": "new\n" })
  s.commit("Unreleased", { "unreleased.txt": "not yet\n" })

  const r = s.run("install", "0.2.0") // downloads first when needed
  assert.equal(r.status, 0, r.stderr)
  assert.equal(s.head(), s.git(s.origin, "rev-parse", "v0.2.0^{commit}"))
  assert.equal(existsSync(join(s.plugin, "new.txt")), true)
  assert.equal(existsSync(join(s.plugin, "unreleased.txt")), false)
  assert.equal(s.git(s.plugin, "branch", "--show-current"), "main")
  assert.deepEqual(s.calls(), [
    `omarchy-plugin-validate ${s.plugin}`,
    "omarchy-restart-shell ",
    "notify-send To Do updated Version 0.2.0 is installed.",
  ])
  assert.equal(s.run("check").stdout, "current\n")
})

test("install goes back when the release is not a valid plugin", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.install()
  s.release("0.2.0", { broken: "x\n" })
  const before = s.head()

  const r = s.run("install", "0.2.0")
  assert.equal(r.status, 1)
  assert.match(r.stderr, /not a valid plugin.*broken/)
  assert.equal(s.head(), before)
  assert.equal(existsSync(join(s.plugin, "broken")), false)
  assert.equal(s.calls().includes("omarchy-restart-shell "), false)
  assert.match(s.calls().at(-1), /^notify-send To Do update failed /)
})

test("install leaves a checkout with local changes alone", (t) => {
  const s = sandbox(t)
  s.release("0.1.0", { "file.txt": "one\n" })
  s.install()
  s.release("0.2.0", { "file.txt": "two\n" })
  writeFileSync(join(s.plugin, "file.txt"), "mine\n")
  const before = s.head()

  const r = s.run("install", "0.2.0")
  assert.equal(r.status, 1)
  assert.match(r.stderr, /local changes/)
  assert.equal(s.head(), before)
  assert.equal(readFileSync(join(s.plugin, "file.txt"), "utf8"), "mine\n")
  assert.equal(s.calls().includes("omarchy-restart-shell "), false)
})

test("install keeps local changes to files the release does not touch", (t) => {
  const s = sandbox(t)
  s.release("0.1.0", { "file.txt": "one\n" })
  s.install()
  // Going back from this release would otherwise reset the whole checkout.
  s.release("0.2.0", { broken: "x\n" })
  writeFileSync(join(s.plugin, "file.txt"), "mine\n")
  const before = s.head()

  const r = s.run("install", "0.2.0")
  assert.equal(r.status, 1)
  assert.match(r.stderr, /local changes/)
  assert.equal(s.head(), before)
  assert.equal(readFileSync(join(s.plugin, "file.txt"), "utf8"), "mine\n")
})

test("refuses a plugin that is not its own checkout", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.install()
  // A plugin copied into a repository that keeps the whole config directory.
  const nested = join(s.plugin, "plugins", "task")
  mkdirSync(nested, { recursive: true })
  copyFileSync(SCRIPT, join(nested, "update"))

  const r = spawnSync(join(nested, "update"), ["check"], { encoding: "utf8" })
  assert.equal(r.status, 1)
  assert.match(r.stderr, /not a git checkout/)
})

test("rejects versions that are not releases", (t) => {
  const s = sandbox(t)
  s.release("0.1.0")
  s.install()
  for (const version of ["", "v0.2.0", "0.2", "0.2.0-rc.1", "0.2.0;true"]) {
    const r = s.run("install", version)
    assert.equal(r.status, 1, version)
    assert.match(r.stderr, /not a release version/)
  }
  assert.deepEqual(s.calls(), [])
})

test("version names the installed release", (t) => {
  const s = sandbox(t)
  s.commit("Initial")
  s.install()
  assert.equal(s.run("version").stdout, "", "before the first release")

  s.release("0.1.0")
  s.git(s.origin, "tag", "v0.2.0-rc.1") // a candidate is no release
  rmSync(s.plugin, { recursive: true })
  s.install()
  assert.equal(s.run("version").stdout, "0.1.0\n")

  s.commit("Unreleased")
  rmSync(s.plugin, { recursive: true })
  s.install()
  assert.match(s.run("version").stdout, /^0\.1\.0-1-g[0-9a-f]+\n$/)
})
