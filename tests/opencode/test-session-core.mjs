// test-session-core.mjs — unit tests for orchestrate-core.ts: the pure
// wave/dependency/parse/review logic of the ported build workflow. Run via
// test-session-core.sh (needs node >= 23 for TS type stripping).
import assert from "node:assert/strict"
import path from "node:path"

const repo = path.resolve(import.meta.dirname, "../..")
const core = await import(path.join(repo, "plugins-opencode/session/src/orchestrate-core.ts"))

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

// --- tier bump ---------------------------------------------------------------

await t("bump walks up and clamps at opus", () => {
	assert.equal(core.bump("haiku"), "sonnet")
	assert.equal(core.bump("sonnet"), "opus")
	assert.equal(core.bump("opus"), "opus")
})

// --- normalizeArgs -------------------------------------------------------------

await t("normalizeArgs rejects empty/missing waves", () => {
	assert.throws(() => core.normalizeArgs({}), /non-empty/)
	assert.throws(() => core.normalizeArgs({ waves: [] }), /non-empty/)
	assert.throws(() => core.normalizeArgs({ waves: "x" }), /non-empty/)
	assert.throws(() => core.normalizeArgs(null), /non-empty/)
})

await t("normalizeArgs rejects non-array waves", () => {
	assert.throws(() => core.normalizeArgs({ waves: [{ id: "c1" }] }), /must be an array/)
})

await t("normalizeArgs defaults unknown tiers to sonnet", () => {
	const args = core.normalizeArgs({
		description: "d",
		plan: "p",
		testsRequired: false,
		waves: [[{ id: "c1", scope: "s", model: "gpt-999" }, { id: "c2", scope: "s", model: "haiku" }]],
	})
	assert.equal(args.waves[0][0].model, "sonnet")
	assert.equal(args.waves[0][1].model, "haiku")
})

// --- extractLastJsonBlock --------------------------------------------------------

await t("extractLastJsonBlock parses a trailing json fence", () => {
	const out = core.extractLastJsonBlock('prose\n```json\n{"status":"done","summary":"ok"}\n```\n')
	assert.deepEqual(out, { status: "done", summary: "ok" })
})

await t("extractLastJsonBlock takes the LAST block when several exist", () => {
	const out = core.extractLastJsonBlock('```json\n{"n":1}\n```\nmid\n```json\n{"n":2}\n```')
	assert.deepEqual(out, { n: 2 })
})

await t("extractLastJsonBlock returns null on missing or invalid block (retry trigger)", () => {
	assert.equal(core.extractLastJsonBlock("no fence here"), null)
	assert.equal(core.extractLastJsonBlock("```json\n{not json}\n```"), null)
	assert.equal(core.extractLastJsonBlock(""), null)
})

await t("extractLastJsonBlock tolerates trailing spaces after the fence tag", () => {
	const out = core.extractLastJsonBlock('```json \n{"a":1}\n```')
	assert.deepEqual(out, { a: 1 })
})

// --- validateExec / validateReview -------------------------------------------------

await t("validateExec accepts done and blocked, coerces junk fields away", () => {
	assert.deepEqual(core.validateExec({ status: "done", summary: "s" }), { status: "done", summary: "s" })
	const r = core.validateExec({ status: "blocked", summary: "s", blocker: "b", filesChanged: ["a", 7], testsPassed: false })
	assert.deepEqual(r, { status: "blocked", summary: "s", filesChanged: ["a"], testsPassed: false, blocker: "b" })
})

await t("validateExec rejects malformed objects", () => {
	assert.equal(core.validateExec(null), null)
	assert.equal(core.validateExec("str"), null)
	assert.equal(core.validateExec({ status: "done" }), null) // no summary
	assert.equal(core.validateExec({ status: "meh", summary: "s" }), null)
	assert.equal(core.validateExec({ status: "done", summary: 42 }), null)
})

await t("validateReview accepts well-formed findings incl. empty list", () => {
	assert.deepEqual(core.validateReview({ findings: [] }), [])
	const fs = core.validateReview({
		findings: [{ chunkId: "c1", severity: "blocker", title: "t", detail: "d", file: "f.ts", line: 3 }],
	})
	assert.deepEqual(fs, [{ chunkId: "c1", severity: "blocker", title: "t", detail: "d", file: "f.ts", line: 3 }])
})

await t("validateReview rejects malformed findings", () => {
	assert.equal(core.validateReview({}), null)
	assert.equal(core.validateReview({ findings: "x" }), null)
	assert.equal(core.validateReview({ findings: [{ chunkId: "c1", severity: "critical", title: "t" }] }), null)
	assert.equal(core.validateReview({ findings: [{ severity: "nit", title: "t" }] }), null)
})

// --- planWave (dependency skip) -----------------------------------------------------

const chunk = (id, extra) => ({ id, scope: id, ...extra })

await t("planWave: implicit deps on all prior chunks; skips on any failure", () => {
	const plan = core.planWave(1, [chunk("c3"), chunk("c4", { dependsOn: ["c2"] })], ["c1", "c2"], new Set(["c1"]))
	assert.deepEqual(
		plan.runnable.map((c) => c.id),
		["c4"],
	)
	assert.deepEqual(plan.skipped, [{ chunkId: "c3", reason: "dependency failed: c1" }])
})

await t("planWave: explicit dependsOn overrides implicit prior-wave deps", () => {
	// c3 explicitly depends only on c2; c1's failure must not skip it
	const plan = core.planWave(1, [chunk("c3", { dependsOn: ["c2"] })], ["c1", "c2"], new Set(["c1"]))
	assert.deepEqual(
		plan.runnable.map((c) => c.id),
		["c3"],
	)
	assert.equal(plan.skipped.length, 0)
})

await t("planWave: all runnable when nothing failed", () => {
	const plan = core.planWave(0, [chunk("c1"), chunk("c2")], [], new Set())
	assert.equal(plan.runnable.length, 2)
	assert.equal(plan.skipped.length, 0)
})

await t("planWave: transitive poison via executor-set notOk", () => {
	// wave2 c5 depends on c3 which was itself skipped (executor adds skips to notOk)
	const plan = core.planWave(2, [chunk("c5", { dependsOn: ["c3"] })], ["c1", "c2", "c3"], new Set(["c3"]))
	assert.equal(plan.runnable.length, 0)
	assert.match(plan.skipped[0].reason, /dependency failed: c3/)
})

// --- findings ---------------------------------------------------------------------

const finding = (chunkId, severity, title, extra) => ({ chunkId, severity, title, ...extra })

await t("dedupeFindings collapses identical (chunk,severity,file,line,title-prefix)", () => {
	const out = core.dedupeFindings([
		finding("c1", "blocker", "Null deref", { file: "a.ts", line: 3 }),
		finding("c1", "blocker", "NULL DEREF", { file: "a.ts", line: 3 }), // case-insensitive title
		finding("c1", "blocker", "Null deref", { file: "a.ts", line: 4 }), // different line
	])
	assert.equal(out.length, 2)
})

await t("splitFindings separates known-chunk from unassigned and dedupes assigned", () => {
	const { assigned, unassigned } = core.splitFindings(
		[finding("c1", "nit", "a"), finding("c1", "nit", "a"), finding("cX", "concern", "b")],
		["c1", "c2"],
	)
	assert.equal(assigned.length, 1)
	assert.equal(unassigned.length, 1)
	assert.equal(unassigned[0].chunkId, "cX")
})

await t("mergeReReview replaces re-reviewed chunks' findings, keeps the rest", () => {
	const old = [finding("c1", "blocker", "b"), finding("c1", "concern", "c"), finding("c2", "nit", "n")]
	const re = [finding("c1", "concern", "fixed, minor residue")]
	const out = core.mergeReReview(old, ["c1"], re)
	// c1's blocker AND concern are gone; only the fresh c1 finding + c2's stand
	assert.deepEqual(
		out.map((f) => `${f.chunkId}/${f.severity}`),
		["c2/nit", "c1/concern"],
	)
})

await t("mergeReReview: clean re-review clears the chunk's blockers (loop terminates)", () => {
	const old = [finding("c1", "blocker", "b")]
	const out = core.mergeReReview(old, ["c1"], [])
	assert.deepEqual(out, [])
})

await t("mergeReReview dedupes across the merge boundary", () => {
	const old = [finding("c2", "nit", "same")]
	const re = [finding("c1", "nit", "same")] // same title/severity, different chunk → distinct key
	const out = core.mergeReReview(old, ["c1"], re.concat([finding("c1", "nit", "same")]))
	assert.equal(out.length, 2)
})

// --- semaphore ----------------------------------------------------------------------

await t("semaphore runs all tasks and preserves result order", async () => {
	const tasks = Array.from({ length: 9 }, (_, i) => async () => {
		await Promise.resolve()
		return i * 2
	})
	assert.deepEqual(await core.semaphore(4, tasks), [0, 2, 4, 6, 8, 10, 12, 14, 16])
})

await t("semaphore caps concurrency at the limit", async () => {
	let live = 0
	let max = 0
	const tasks = Array.from({ length: 12 }, () => async () => {
		live++
		max = Math.max(max, live)
		await new Promise((r) => setTimeout(r, 5))
		live--
		return true
	})
	await core.semaphore(3, tasks)
	assert.ok(max <= 3, `observed concurrency ${max} > 3`)
})

await t("semaphore with fewer tasks than slots still completes", async () => {
	assert.deepEqual(await core.semaphore(8, [async () => 1, async () => 2]), [1, 2])
	assert.deepEqual(await core.semaphore(4, []), [])
})

// --- prompts ---------------------------------------------------------------------------

const args = { description: "add widgets", plan: "# plan", testsRequired: true, waves: [[chunk("c1", { scope: "widget api", files: ["w.ts"], tests: true })]] }
const findChunk = (id) => args.waves.flat().find((c) => c.id === id)

await t("execPrompt carries feature, plan, chunk scope, files, and the output contract", () => {
	const p = core.execPrompt(args, findChunk("c1"))
	assert.match(p, /add widgets/)
	assert.match(p, /# plan/)
	assert.match(p, /Your chunk: c1/)
	assert.match(p, /widget api/)
	assert.match(p, /w\.ts/)
	assert.match(p, /```json block/)
	assert.match(p, /status.*done.*blocked/s)
})

await t("execPrompt appends attempt context when retrying", () => {
	const p = core.execPrompt(args, findChunk("c1"), "Attempt 1 failed: build broke")
	assert.match(p, /Context for this attempt/)
	assert.match(p, /build broke/)
})

await t("reviewPrompt notes blocked implementations", () => {
	const p = core.reviewPrompt(args, findChunk, () => ({ summary: "stuck", ok: false, attempts: 3 }), "c1")
	assert.match(p, /Chunk under review: c1/)
	assert.match(p, /reported this chunk as BLOCKED/)
	assert.match(p, /stuck/)
})

await t("opusReviewPrompt lists all in-scope chunks", () => {
	const p = core.opusReviewPrompt(args, findChunk, ["c1", "c9"])
	assert.match(p, /c1: widget api/)
	assert.match(p, /c9: \?/)
})

console.log("")
console.log(`Total: ${pass + fail}  PASS: ${pass}  FAIL: ${fail}`)
process.exit(fail === 0 ? 0 : 1)
