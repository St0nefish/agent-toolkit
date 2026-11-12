// The ONLY file that touches ctx.permission.hook. When opencode lands
// `experimental.review` (anomalyco/opencode#61824) migrating means rewriting
// registerPermissionHook here and nothing else: approver-core.ts takes plain
// data and returns an Outcome.
import fs from "node:fs"
import path from "node:path"
import {
	APPROVE_QUESTION,
	applyOutcome,
	compilePatterns,
	decide,
	lastUserMessages,
	logPath,
	normalizeOptions,
	resolveModel,
	resolvePrompt,
	type Deps,
	type EvalEvent,
	type LogEntry,
	type Outcome,
} from "./approver-core.js"

function appendLog(file: string, entry: LogEntry): void {
	try {
		fs.mkdirSync(path.dirname(file), { recursive: true })
		fs.appendFileSync(file, `${JSON.stringify(entry)}\n`)
	} catch {
		/* auditing must never break a permission decision */
	}
}

export async function registerPermissionHook(ctx: any): Promise<{ dispose: () => Promise<void> }> {
	const options = normalizeOptions(ctx.options)
	const prompt = resolvePrompt({
		directory: ctx.location?.directory ?? process.cwd(),
		optionPrompt: options.prompt,
	})
	const file = logPath(options.log)

	// Resolved once, lazily, so a model list that is not ready at setup time
	// does not wedge the plugin; failures re-try on the next judged action.
	let modelPromise: ReturnType<typeof resolveModel> | undefined
	const model = () =>
		(modelPromise ??= resolveModel(options.model, options.modelTiers, () => ctx.model.list()).then((m) => (m ? m : ((modelPromise = undefined), undefined))))

	const deps: Deps = {
		options,
		allow: compilePatterns(options.allow),
		ask: compilePatterns(options.ask),
		prompt,
		async judge({ text }) {
			const m = await model()
			if (!m) throw new Error(`cannot resolve judge model "${options.model}"`)
			const { answers } = await ctx.experimental.generate.decisions({
				model: { providerID: m.providerID, id: m.id },
				input: [{ type: "text", text }],
				questions: [APPROVE_QUESTION],
			})
			const a = (answers as any[]).find((x) => x.name === APPROVE_QUESTION.name)
			if (!a) throw new Error("judge returned no answer")
			if (a.type === "error") throw new Error(`judge error: ${a.message ?? a.reason}`)
			return {
				approve: a.type === "predicate" && a.probability >= options.threshold,
				reason: a.reason,
				model: `${m.providerID}/${m.id}`,
			}
		},
		async userMessages(sessionID) {
			return lastUserMessages((await ctx.session.context({ sessionID })) as readonly unknown[], options.messageWindow, options.messageChars)
		},
		async isSubagent(sessionID) {
			const s = await ctx.session.get({ sessionID })
			return Boolean(s?.parentID ?? s?.data?.parentID)
		},
	}

	return ctx.permission.hook("evaluate", async (event: EvalEvent) => {
		let outcome: Outcome
		try {
			outcome = await decide(event, deps)
		} catch (err) {
			// decide() should not throw; if it does, fail closed.
			outcome = {
				effect: "ask",
				message: options.askMessage,
				entry: {
					sessionID: event.sessionID,
					agent: event.agent,
					action: event.action,
					resources: event.resources,
					source: "error",
					verdict: "ask",
					reason: String(err),
					latencyMs: 0,
				},
			}
		}
		appendLog(file, {
			ts: new Date().toISOString(),
			shadow: options.shadow,
			...outcome.entry,
		})
		applyOutcome(event, outcome, options.shadow)
	})
}
