// orchestrate-core.ts — the deterministic logic of the Claude
// `orchestrate-build.workflow.js`, ported to run inside the OpenCode plugin
// tool. Pure functions only (no ctx, no I/O) so the wave/dependency/parse/
// review semantics are unit-testable; the plugin part supplies the session
// mechanics (create/prompt/wait/context/remove).

export type Tier = "haiku" | "sonnet" | "opus"
const TIERS: Tier[] = ["haiku", "sonnet", "opus"]
export const bump = (m: Tier): Tier => TIERS[Math.min(TIERS.indexOf(m) + 1, TIERS.length - 1)]

export type Chunk = {
	id: string
	scope: string
	files?: string[]
	model?: Tier
	tests?: boolean
	testScope?: string
	opusReview?: boolean
	dependsOn?: string[]
}

export type OrchestrateArgs = {
	description: string
	plan: string
	testsRequired: boolean
	waves: Chunk[][]
}

export function normalizeArgs(raw: unknown): OrchestrateArgs {
	const a = raw as OrchestrateArgs
	if (!a || !Array.isArray(a.waves) || a.waves.length === 0) {
		throw new Error("orchestrate_build: args.waves must be a non-empty array of chunk arrays")
	}
	for (const wave of a.waves) if (!Array.isArray(wave)) throw new Error("orchestrate_build: each wave must be an array of chunks")
	// Unknown tiers would make bump() downgrade (indexOf -1 → haiku); default to sonnet.
	for (const c of a.waves.flat()) if (!TIERS.includes(c.model as Tier)) c.model = "sonnet"
	return a
}

// --- exec/review result shapes (mirror the Claude workflow's schemas) --------

export type ExecResult = {
	status: "done" | "blocked"
	summary: string
	filesChanged?: string[]
	testsPassed?: boolean
	blocker?: string
}

export type Finding = {
	chunkId: string
	severity: "blocker" | "concern" | "nit"
	title: string
	detail?: string
	file?: string
	line?: number
}

export function validateExec(obj: unknown): ExecResult | null {
	if (typeof obj !== "object" || obj === null) return null
	const o = obj as Record<string, unknown>
	if (o.status !== "done" && o.status !== "blocked") return null
	if (typeof o.summary !== "string") return null
	const r: ExecResult = { status: o.status, summary: o.summary }
	if (Array.isArray(o.filesChanged)) r.filesChanged = o.filesChanged.filter((f): f is string => typeof f === "string")
	if (typeof o.testsPassed === "boolean") r.testsPassed = o.testsPassed
	if (typeof o.blocker === "string") r.blocker = o.blocker
	return r
}

export function validateReview(obj: unknown): Finding[] | null {
	if (typeof obj !== "object" || obj === null) return null
	const o = obj as Record<string, unknown>
	if (!Array.isArray(o.findings)) return null
	const out: Finding[] = []
	for (const f of o.findings as unknown[]) {
		if (typeof f !== "object" || f === null) return null
		const x = f as Record<string, unknown>
		if (typeof x.chunkId !== "string") return null
		if (x.severity !== "blocker" && x.severity !== "concern" && x.severity !== "nit") return null
		if (typeof x.title !== "string") return null
		const finding: Finding = { chunkId: x.chunkId, severity: x.severity, title: x.title }
		if (typeof x.detail === "string") finding.detail = x.detail
		if (typeof x.file === "string") finding.file = x.file
		if (typeof x.line === "number") finding.line = x.line
		out.push(finding)
	}
	return out
}

// --- output-block extraction --------------------------------------------------
// Children are instructed to end with a fenced ```json block. Parsing free
// text is fragile: "no/invalid block" is a RETRY TRIGGER, never a silent pass.
export function extractLastJsonBlock(text: string): unknown {
	const fence = /```json[ \t]*\r?\n([\s\S]*?)```/g
	let last: string | null = null
	for (let m = fence.exec(text); m !== null; m = fence.exec(text)) last = m[1]
	if (last === null) return null
	try {
		return JSON.parse(last)
	} catch {
		return null
	}
}

// --- prompts (ported verbatim from the workflow script) -----------------------

export const OUTPUT_INSTRUCTION = (schema: object) =>
	`\n\nEnd your FINAL message with exactly one fenced \`\`\`json block containing the result object matching this JSON schema (no trailing prose after the block):\n${JSON.stringify(schema, null, 2)}`

export const EXEC_SCHEMA = {
	type: "object",
	required: ["status", "summary"],
	properties: {
		status: { type: "string", enum: ["done", "blocked"] },
		summary: { type: "string", description: "Concise description of what was changed" },
		filesChanged: { type: "array", items: { type: "string" } },
		testsPassed: { type: "boolean", description: "true if tests were run and passed, false if run and failed; omit if not applicable" },
		blocker: { type: "string", description: "If status=blocked, describe the blocker precisely" },
	},
} as const

export const REVIEW_SCHEMA = {
	type: "object",
	required: ["findings"],
	properties: {
		findings: {
			type: "array",
			items: {
				type: "object",
				required: ["chunkId", "severity", "title"],
				properties: {
					chunkId: { type: "string" },
					severity: { type: "string", enum: ["blocker", "concern", "nit"] },
					title: { type: "string" },
					detail: { type: "string" },
					file: { type: "string" },
					line: { type: "integer" },
				},
			},
		},
	},
} as const

export function execPrompt(args: OrchestrateArgs, chunk: Chunk, extra?: string): string {
	const lines = [
		`You are implementing ONE chunk of an approved feature plan. Stay strictly within this chunk's scope.`,
		``,
		`## Feature`,
		args.description,
		``,
		`## Agreed plan (context — do not re-litigate)`,
		args.plan,
		``,
		`## Your chunk: ${chunk.id}`,
		`Scope: ${chunk.scope}`,
		`Files you own: ${(chunk.files || []).join(", ") || "(determine from scope; touch nothing owned by other chunks)"}`,
		chunk.tests
			? `Tests: write/update tests for this chunk. ${chunk.testScope || ""}`.trim()
			: args.testsRequired
				? `Tests: ensure existing tests still pass; you need not add new ones.`
				: `Tests: this project has no test suite requirement.`,
		``,
		`## Rules`,
		`- Implement only this chunk. Do NOT modify files owned by other chunks.`,
		`- Follow existing codebase conventions: naming, file layout, imports, idioms.`,
		args.testsRequired ? `- Run the relevant tests/lint before reporting status="done".` : null,
		`- If you cannot complete it, set status="blocked" and describe the blocker precisely — do not guess or fake completion.`,
		extra ? `\n## Context for this attempt\n${extra}` : null,
	]
	return lines.filter((l) => l !== null).join("\n") + OUTPUT_INSTRUCTION(EXEC_SCHEMA)
}

export function reviewPrompt(
	args: OrchestrateArgs,
	findChunk: (id: string) => Chunk | undefined,
	execSummary: (id: string) => { summary?: string; ok?: boolean; attempts?: number } | undefined,
	id: string,
): string {
	const chunk = findChunk(id)
	const exec = execSummary(id)
	const lines = [
		`Review the implementation of ONE chunk for correctness, convention compliance, and spec adherence. You may read files and run tests/lint. Do NOT modify code.`,
		``,
		`## Feature`,
		args.description,
		``,
		`## Chunk under review: ${id}`,
		`Scope: ${chunk?.scope ?? "(unknown chunk)"}`,
		`Files: ${(chunk?.files || []).join(", ")}`,
		`Implementer reported: ${exec?.summary ?? "(no summary)"}`,
		exec && exec.ok === false ? `NOTE: the implementer reported this chunk as BLOCKED/incomplete after ${exec.attempts} attempts.` : null,
		``,
		`## Check`,
		`- Codebase conventions: naming, file layout, imports, idioms`,
		args.testsRequired ? `- Tests pass; lint/type checks are clean` : `- (no test suite required for this project)`,
		`- Spec compliance: does it implement what the chunk asked for?`,
		`- Pitfalls: error paths, null/empty handling, dead code, stale TODOs, leftover debug output`,
		`- No regressions in unrelated code`,
		``,
		`Tag each finding's severity: "blocker" (broken/wrong/tests fail — must fix), "concern" (should consider), "nit" (trivial). Set chunkId="${id}" on every finding. Return an empty findings array if clean.`,
	]
	return lines.filter((l) => l !== null).join("\n") + OUTPUT_INSTRUCTION(REVIEW_SCHEMA)
}

export function opusReviewPrompt(args: OrchestrateArgs, findChunk: (id: string) => Chunk | undefined, ids: string[]): string {
	const lines = [
		`Senior correctness/security review of the following chunks ONLY. Read the code and reason hard about edge cases, concurrency, data integrity, auth, and security. Do NOT modify code.`,
		``,
		`## Feature`,
		args.description,
		``,
		`## Chunks in scope`,
		...ids.map((id) => {
			const c = findChunk(id)
			return `- ${id}: ${c?.scope ?? "?"} [${(c?.files || []).join(", ")}]`
		}),
		``,
		`Tag findings blocker/concern/nit and set chunkId to the relevant chunk. Empty findings array if clean.`,
	]
	return lines.filter((l) => l !== null).join("\n") + OUTPUT_INSTRUCTION(REVIEW_SCHEMA)
}

// --- wave/dependency planning (pure; the executor runs the plan) --------------

export type WavePlan = { wave: number; runnable: Chunk[]; skipped: { chunkId: string; reason: string }[] }

// Mirror of the workflow's skip logic: a chunk is skipped when any dependency
// (explicit dependsOn, else all earlier-wave chunks) already failed/was
// skipped. `notOk` is the transitive poison set maintained by the executor.
export function planWave(waveIndex: number, wave: Chunk[], priorIds: string[], notOk: Set<string>): WavePlan {
	const runnable: Chunk[] = []
	const skipped: { chunkId: string; reason: string }[] = []
	for (const chunk of wave) {
		const deps = Array.isArray(chunk.dependsOn) ? chunk.dependsOn : priorIds
		const bad = deps.filter((d) => notOk.has(d))
		if (bad.length) skipped.push({ chunkId: chunk.id, reason: `dependency failed: ${bad.join(", ")}` })
		else runnable.push(chunk)
	}
	return { wave: waveIndex, runnable, skipped }
}

export function dedupeFindings(findings: Finding[]): Finding[] {
	const seen = new Set<string>()
	const out: Finding[] = []
	for (const f of findings) {
		const key = `${f.chunkId}|${f.severity}|${f.file || ""}|${f.line ?? ""}|${(f.title || "").toLowerCase().slice(0, 60)}`
		if (seen.has(key)) continue
		seen.add(key)
		out.push(f)
	}
	return out
}

export function splitFindings(findings: Finding[], reviewedIds: string[]) {
	const known = new Set(reviewedIds)
	const assigned: Finding[] = []
	const unassigned: Finding[] = []
	for (const f of findings) (known.has(f.chunkId) ? assigned : unassigned).push(f)
	return { assigned: dedupeFindings(assigned), unassigned }
}

// Re-review merge: findings for the re-dispatched chunks are REPLACED by the
// fresh review; clean chunks' findings stand. Pure so the loop bookkeeping is
// unit-testable (the executor in index.ts just wires children to it).
export function mergeReReview(findings: Finding[], reReviewedIds: string[], reFindings: Finding[]): Finding[] {
	const re = new Set(reReviewedIds)
	return dedupeFindings(
		findings.filter((f) => !re.has(f.chunkId)).concat(reFindings),
	)
}

// --- small concurrency helper --------------------------------------------------

export async function semaphore<T>(limit: number, tasks: (() => Promise<T>)[]): Promise<T[]> {
	const results: T[] = new Array(tasks.length)
	let next = 0
	const workers = Array.from({ length: Math.min(limit, tasks.length) }, async () => {
		for (let i = next++; i < tasks.length; i = next++) {
			if (i >= tasks.length) break
			results[i] = await tasks[i]()
		}
	})
	await Promise.all(workers)
	return results
}
