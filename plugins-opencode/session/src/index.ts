import { Plugin } from "@opencode/plugin"
import {
	normalizeArgs,
	bump,
	execPrompt,
	reviewPrompt,
	opusReviewPrompt,
	extractLastJsonBlock,
	validateExec,
	validateReview,
	planWave,
	splitFindings,
	semaphore,
	EXEC_SCHEMA,
	REVIEW_SCHEMA,
	type Chunk,
	type ExecResult,
	type Finding,
	type Tier,
	type OrchestrateArgs,
} from "./orchestrate-core.js"

const CONCURRENCY = 4
const MAX_REVIEW_ITERS = 2

// `haiku|sonnet|opus` → concrete model refs. Override per install with plugin
// options: { "modelTiers": { "haiku": "provider/model-id", ... } }. Default:
// fuzzy-match the enabled model list for a model whose id contains the tier
// name; fall back to the session default when nothing matches.
async function resolveTier(ctx: any, tier: Tier): Promise<{ providerID: string; id: string } | undefined> {
	const override = (ctx.options?.modelTiers as Record<string, string> | undefined)?.[tier]
	if (override) {
		const [providerID, ...rest] = String(override).split("/")
		if (providerID && rest.length) return { providerID, id: rest.join("/") }
	}
	try {
		const models = (await ctx.model.list()) as Array<{ providerID: string; id: string; enabled?: boolean }>
		const match = models.find((m) => m.enabled !== false && m.id.toLowerCase().includes(tier))
		if (match) return { providerID: match.providerID, id: match.id }
	} catch {
		/* provider list unavailable; children use the session default */
	}
	return undefined
}

// Defensive text extraction: message shapes vary across versions.
function lastAssistantText(messages: readonly unknown[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i] as Record<string, any>
		const role = m.role ?? m.info?.role
		if (role !== "assistant") continue
		const content = m.content ?? m.parts ?? m.text
		if (typeof content === "string" && content) return content
		if (Array.isArray(content)) {
			const text = content
				.filter((p: any) => p && (p.type === "text" || typeof p.text === "string"))
				.map((p: any) => p.text ?? "")
				.join("\n")
			if (text.trim()) return text
		}
	}
	return ""
}

export default Plugin.define({
	id: "agent-toolkit.session",
	async setup(ctx) {
		// One child session per attempt: create → build agent → tier → prompt
		// → wait → parse the last ```json block. Unparseable output is a retry
		// trigger, never a silent pass. Children are top-level build sessions
		// (not the subagent tool), so the depth-1 subagent limit doesn't apply;
		// only the parent session ever has orchestrate_build, so no recursion.
		async function runChild(label: string, tier: Tier, prompt: string): Promise<unknown> {
			const child = await ctx.session.create({ title: `orchestrate ${label}` })
			try {
				await ctx.session.switchAgent({ sessionID: child.id, agent: "build" })
				const model = await resolveTier(ctx, tier)
				if (model) await ctx.session.switchModel({ sessionID: child.id, model })
				await ctx.session.prompt({ sessionID: child.id, text: prompt })
				await ctx.session.wait({ sessionID: child.id })
				const messages = await ctx.session.context({ sessionID: child.id })
				return extractLastJsonBlock(lastAssistantText(messages as readonly unknown[]))
			} finally {
				await ctx.session.remove({ sessionID: child.id }).catch(() => {})
			}
		}

		type ExecAttempt = {
			chunkId: string
			ok: boolean
			attempts: number
			model: Tier
			result: ExecResult | null
			blocker?: string
		}

		// Failure escalation (cap 3): attempt 1 base tier + base prompt;
		// attempt 2 base tier + failure-refined prompt; attempt 3 bumped tier +
		// refined prompt. Mirrors the Claude workflow's executeChunk.
		async function executeChunk(args: OrchestrateArgs, chunk: Chunk, seedContext?: string): Promise<ExecAttempt> {
			const baseModel = (chunk.model || "sonnet") as Tier
			let extra = seedContext || ""
			let last: ExecResult | null = null
			let usedModel = baseModel
			for (let attempt = 1; attempt <= 3; attempt++) {
				usedModel = attempt === 3 ? bump(baseModel) : baseModel
				let parsed: ExecResult | null = null
				try {
					parsed = validateExec(await runChild(`exec:${chunk.id}#${attempt}`, usedModel, execPrompt(args, chunk, extra)))
				} catch {
					parsed = null
				}
				last = parsed
				if (parsed && parsed.status === "done") {
					return { chunkId: chunk.id, ok: true, attempts: attempt, model: usedModel, result: parsed }
				}
				const why = parsed ? parsed.blocker || parsed.summary : "no parsable result block (retrying)"
				extra = `Attempt ${attempt} did not complete. Reported blocker: ${why}\nClarify the success criteria and address this blocker directly.`
			}
			return {
				chunkId: chunk.id,
				ok: false,
				attempts: 3,
				model: usedModel,
				result: last,
				blocker: last ? last.blocker || last.summary : "no result after 3 attempts",
			}
		}

		const toolReg = await ctx.tool.transform((editor) => {
			editor.add({
				name: "orchestrate_build",
				description:
					"Execute an approved chunk plan in dependency waves with per-chunk failure escalation, then review executed chunks and auto-fix blockers (cap 2). Returns structured findings {perChunk, clean, concerns, unresolvedBlockers, nits, skipped, unassigned, filesChanged} for the calling skill to gate on.",
				input: {
					type: "object",
					properties: {
						description: { type: "string", description: "the user's feature description" },
						plan: { type: "string", description: "the agreed implementation plan (markdown)" },
						testsRequired: { type: "boolean", description: "whether the project requires tests to pass" },
						waves: {
							type: "array",
							description: "dependency-ordered waves; chunks within a wave run in parallel, waves run serially",
							items: { type: "array", items: { type: "object" } },
						},
					},
					required: ["description", "plan", "testsRequired", "waves"],
					additionalProperties: false,
				},
				execute: async (input: unknown) => {
					const args = normalizeArgs(input)
					const allChunks = args.waves.flat()
					const findChunk = (id: string) => allChunks.find((c) => c.id === id)

					// --- Execute: waves serially, chunks in parallel (capped) ---
					const execByChunk = new Map<string, ExecAttempt>()
					const skipped: { chunkId: string; reason: string }[] = []
					const notOk = new Set<string>()
					const priorIds: string[] = []
					for (let w = 0; w < args.waves.length; w++) {
						const wave = args.waves[w]
						const plan = planWave(w, wave, priorIds, notOk)
						for (const s of plan.skipped) notOk.add(s.chunkId)
						skipped.push(...plan.skipped)
						const results = await semaphore(CONCURRENCY, plan.runnable.map((chunk) => () => executeChunk(args, chunk)))
						for (const r of results) {
							execByChunk.set(r.chunkId, r)
							if (!r.ok) notOk.add(r.chunkId)
						}
						for (const c of wave) priorIds.push(c.id)
					}

					// --- Review + blocker auto-fix loop (cap 2) ---
					const allUnassigned: Finding[] = []
					const reviewChunks = async (ids: string[]): Promise<Finding[]> => {
						const warranted = ids.filter((id) => findChunk(id)?.opusReview)
						const tasks: (() => Promise<Finding[]>)[] = ids.map((id) => async () => {
							const exec = execByChunk.get(id)
							const parsed = validateReview(
								await runChild(
									`review:${id}`,
									"sonnet",
									reviewPrompt(args, findChunk, (rid) => (rid === id ? { summary: exec?.result?.summary, ok: exec?.ok, attempts: exec?.attempts } : undefined), id),
								),
							)
							return (parsed ?? []).map((f) => ({ ...f, chunkId: id })) // reviewer is scoped to one chunk
						})
						if (warranted.length) {
							tasks.push(async () => {
								const parsed = validateReview(await runChild("review:opus", "opus", opusReviewPrompt(args, findChunk, warranted)))
								return parsed ?? []
							})
						}
						const merged = (await semaphore(CONCURRENCY, tasks)).flat()
						// Findings naming an unknown chunk id cannot be re-dispatched;
						// set them aside and surface them in the result (workflow parity).
						const split = splitFindings(merged, ids)
						allUnassigned.push(...split.unassigned)
						return split.assigned
					}

					let findings = await reviewChunks([...execByChunk.keys()])

					let iteration = 0
					while (findings.some((f) => f.severity === "blocker") && iteration < MAX_REVIEW_ITERS) {
						iteration++
						const blockerIds = [...new Set(findings.filter((f) => f.severity === "blocker").map((f) => f.chunkId))].filter((id) => findChunk(id))
						await semaphore(
							CONCURRENCY,
							blockerIds.map((id) => async () => {
								const chunk = findChunk(id)!
								const fb = findings
									.filter((f) => f.chunkId === id && f.severity === "blocker")
									.map((f) => `- ${f.title}${f.detail ? ": " + f.detail : ""}${f.file ? " (" + f.file + ")" : ""}`)
									.join("\n")
								const r = await executeChunk(args, chunk, `A reviewer flagged blocking issues with your earlier implementation:\n${fb}\nFix these specifically.`)
								execByChunk.set(r.chunkId, r)
							}),
						)
						// Re-review ONLY the re-dispatched chunks; clean chunks' findings stand.
						const reFindings = await reviewChunks(blockerIds)
						findings = findings.filter((f) => !blockerIds.includes(f.chunkId)).concat(reFindings)
					}

					const blockers = findings.filter((f) => f.severity === "blocker")
					const concerns = findings.filter((f) => f.severity === "concern")
					const nits = findings.filter((f) => f.severity === "nit")
					const filesChanged = [...new Set([...execByChunk.values()].flatMap((r) => r.result?.filesChanged ?? []))]
					const flaggedIds = new Set(findings.map((f) => f.chunkId))

					return {
						content: JSON.stringify(
							{
								iterations: iteration,
								hitReviewCap: blockers.length > 0,
								perChunk: [...execByChunk.values()].map((r) => ({
									chunkId: r.chunkId,
									ok: r.ok,
									attempts: r.attempts,
									model: r.model,
									summary: r.result?.summary ?? null,
									testsPassed: r.result?.testsPassed,
									blocker: r.ok ? undefined : r.blocker,
								})),
								skipped,
								unassigned: allUnassigned,
								filesChanged,
								clean: [...execByChunk.keys()].filter((id) => !flaggedIds.has(id)),
								unresolvedBlockers: blockers,
								concerns,
								nits,
							},
							null,
							2,
						),
					}
				},
			})
		})

		// Slash doors for the session skills (OpenCode skills take no slash
		// arguments; the command forwards them through the prompt).
		const doors = ["session-start", "session-issue", "session-end", "session-orchestrate", "session-summarize"]
		const commandReg = await ctx.command.transform((editor) => {
			for (const skill of doors) {
				editor.add({
					name: skill,
					description: `Run the ${skill} workflow`,
					execute: async ({ sessionID, prompt, delivery }) => {
						await ctx.session.prompt({
							...prompt,
							sessionID,
							delivery,
							text:
								`Load the \`${skill}\` skill with the skill tool and follow it exactly.\n\n` +
								`Invocation arguments (may be empty):\n${prompt.text || "(none)"}`,
						})
					},
				})
			}
		})

		return () => {
			void toolReg.dispose()
			void commandReg.dispose()
		}
	},
})
