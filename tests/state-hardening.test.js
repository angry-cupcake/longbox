// State-hardening test suite for the inline permission helper in Panel.qml.
// Unlike store.test.js / model.test.js this suite additionally spawns
// /usr/bin/python3 as an external dev-only dependency: the helper under test
// is a python one-liner embedded in QML, so its behavior can only be checked
// by running it. The script text is extracted verbatim from Panel.qml (single
// source of truth); if extraction fails these tests fail loudly.
'use strict'
process.env.TZ = 'UTC'

const test = require('node:test')
const assert = require('node:assert')
const { spawnSync } = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const PANEL = fs.readFileSync(path.join(__dirname, '..', 'Panel.qml'), 'utf8')

// Pull the -c argument out of permsProcess.command. The script is written as
// adjacent string literals joined by '+', so collect and concatenate them.
const cmdMatch = PANEL.match(
  /permsProcess\.command\s*=\s*\["\/usr\/bin\/python3",\s*"-c",\s*([\s\S]*?),\s*Quickshell\.env\(/
)
assert.ok(cmdMatch, 'could not extract hardener script from Panel.qml permsProcess.command')
const scriptLiterals = [...cmdMatch[1].matchAll(/"(?:\\.|[^"\\])*"/g)].map(m => JSON.parse(m[0]))
const SCRIPT = scriptLiterals.join('')
assert.ok(SCRIPT.includes('O_NOFOLLOW'), 'extracted script looks wrong')

let tmpDir

test.before(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'longbox-test-'))
})

test.after(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true })
})

function runHardener(target) {
  return spawnSync('/usr/bin/python3', ['-c', SCRIPT, target])
}

function fixturePath(name) {
  return path.join(tmpDir, name)
}

test('regular file is verified and forced to mode 600', () => {
  const p = fixturePath('regular.json')
  fs.writeFileSync(p, '{"t":1}', { mode: 0o644 })
  const r = runHardener(p)
  assert.equal(r.status, 0)
  assert.ok(r.stdout.toString().includes('ok'))
  assert.equal(fs.statSync(p).mode & 0o777, 0o600)
})

test('symlink at the path is refused and the target stays untouched', () => {
  const target = fixturePath('target.json')
  const link = fixturePath('link.json')
  fs.writeFileSync(target, '{"secret":true}', { mode: 0o644 })
  fs.symlinkSync(target, link)
  const r = runHardener(link)
  assert.notEqual(r.status, 0)
  assert.ok(r.stdout.toString().startsWith('refused:'))
  // The planted link must not have been chmodded through.
  assert.equal(fs.statSync(target).mode & 0o777, 0o644)
  assert.equal(fs.readFileSync(target, 'utf8'), '{"secret":true}')
})

test('directory at the path is refused cleanly', () => {
  // O_RDWR|O_CREAT on a directory fails at open() with EISDIR - caught by
  // the helper's OSError handler - so refusal comes from there, not from
  // the S_ISREG check.
  const p = fixturePath('adir')
  fs.mkdirSync(p)
  const r = runHardener(p)
  assert.equal(r.status, 1)
  assert.ok(r.stdout.toString().startsWith('refused:'))
})

test('non-regular file at the path trips the not-regular check', () => {
  // A character device opens O_RDWR fine, so refusal comes from S_ISREG
  // (checked before ownership). /dev/null keeps this hermetic without
  // needing mkfifo, which Node does not expose.
  const r = runHardener('/dev/null')
  assert.equal(r.status, 1)
  assert.ok(r.stdout.toString().startsWith('refused:not-regular'))
})

test('missing parent dir exits cleanly per O_CREAT semantics', () => {
  // Either creation succeeds or open() refuses with OSError; both are
  // acceptable - what must never happen is an unhandled crash (signal or
  // uncaught traceback instead of our refused:/ok protocol).
  const p = path.join(tmpDir, 'no', 'such', 'dir', 'state.json')
  const r = runHardener(p)
  assert.equal(r.error, undefined)
  assert.equal(r.signal, null)
  assert.ok(typeof r.status === 'number')
  if (r.status === 0) {
    assert.ok(r.stdout.toString().includes('ok'))
    assert.equal(fs.statSync(p).mode & 0o777, 0o600)
  } else {
    assert.ok(r.stdout.toString().startsWith('refused:'))
  }
})
