// test-inbox-core.mjs — unit tests for the harness-free inbox core module
// (snapshot parsing, counts, blocking, triage round-trips against the real
// vendored CLI with a sandboxed state dir). Run via test-inbox-core.sh.
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const repo = path.resolve(import.meta.dirname, "../..")
const CLI = path.join(repo, "plugins-opencode/inbox/scripts/inbox")

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "inbox-core-"))
process.env.INBOX_STATE_DIR = path.join(TMP, "state")

const core = await import(path.join(repo, "plugins-opencode/inbox/src/core.ts"))

let pass = 0
let fail = 0
const t = async (label, fn) => {
	try {
		await fn()
		console.log(`  \x1b[32m✓\x1b[0m ${label}`)
		pass++
	} catch (err) {
		console.log(`  \x1b[31m✗\x1b[0m ${label}  (${err.message})`)
		fail++
	}
}

const cli = (...args) => execFileSync("bash", [CLI, ...args], { encoding: "utf8" })

await t("inboxStateDir honors INBOX_STATE_DIR", () => {
	assert.equal(core.inboxStateDir(), process.env.INBOX_STATE_DIR)
})

await t("inboxCliPath resolves inside the plugin", () => {
	assert.ok(fs.existsSync(core.inboxCliPath()), core.inboxCliPath())
})

await t("empty session snapshot is all zeros", async () => {
	const snap = await core.readSnapshot("core-empty")
	assert.deepEqual(snap.counts, { questions: 0, decisions: 0, followups: 0, blocking: 0 })
})

cli("--session", "core-mixed", "add", "question", "--title", "Plain?")
cli("--session", "core-mixed", "add", "question", "--blocking", "--title", "Hard stop?")
cli("--session", "core-mixed", "add", "decision", "--title", "Chose X", "--chosen", "X")
cli("--session", "core-mixed", "add", "followup", "--title", "Add docs")

await t("counts reflect all kinds and blocking", async () => {
	const snap = await core.readSnapshot("core-mixed")
	assert.deepEqual(snap.counts, { questions: 2, decisions: 1, followups: 1, blocking: 1 })
})

await t("items carry titles and blocking flags", async () => {
	const snap = await core.readSnapshot("core-mixed")
	assert.equal(snap.items.questions[1].blocking, true)
	assert.equal(snap.items.questions[0].blocking, false)
	assert.equal(snap.items.questions[1].title, "Hard stop?")
})

await t("countsOf computes from items", () => {
	const c = core.countsOf({
		questions: [{ id: 1, title: "a", blocking: true }, { id: 2, title: "b" }],
		decisions: [],
		followups: [{ id: 1, title: "f" }],
	})
	assert.deepEqual(c, { questions: 2, decisions: 0, followups: 1, blocking: 1 })
})

await t("runTriage answer removes the question and returns fresh snapshot", async () => {
	const snap = await core.runTriage("core-mixed", "answer", "Q1")
	assert.equal(snap.counts.questions, 1)
	assert.equal(snap.counts.blocking, 1) // the blocking one remains
})

await t("runTriage resolve/done clear decisions/followups", async () => {
	let snap = await core.runTriage("core-mixed", "resolve", "D1")
	assert.equal(snap.counts.decisions, 0)
	snap = await core.runTriage("core-mixed", "done", "F1")
	assert.equal(snap.counts.followups, 0)
})

await t("runTriage on a missing item rejects (caller surfaces cli_failed)", async () => {
	await assert.rejects(() => core.runTriage("core-mixed", "answer", "Q99"))
})

await t("answerFeedback names the item and the note", () => {
	const text = core.answerFeedback("Q3", "use postgres")
	assert.match(text, /Q3/)
	assert.match(text, /use postgres/)
})

console.log("")
console.log(`Total: ${pass + fail}  PASS: ${pass}  FAIL: ${fail}`)
fs.rmSync(TMP, { recursive: true, force: true })
process.exit(fail === 0 ? 0 : 1)
