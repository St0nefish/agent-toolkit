import { Plugin } from "@opencode/plugin"
import fs from "node:fs"
import {
	readSnapshot,
	runTriage,
	inboxCliPath,
	inboxStateDir,
	answerFeedback,
	type TriageAction,
	type Snapshot,
} from "./core.js"
import { Inbox } from "./rpc.js"

const HINT_KEY = "agent-toolkit-inbox"
const WATCH_DEBOUNCE_MS = 200

const LIST_KINDS = {
	"inbox:questions": { kind: "question", header: "Open inbox questions for this session" },
	"inbox:decisions": { kind: "decision", header: "Open inbox decisions for this session" },
	"inbox:followups": { kind: "followup", header: "Open inbox followups for this session" },
	"inbox:show": { kind: "", header: "Full inbox for this session" },
} as const

export default Plugin.define({
	id: "agent-toolkit.inbox",
	async setup(ctx) {
		const cli = inboxCliPath()
		const stateDir = inboxStateDir()
		fs.mkdirSync(stateDir, { recursive: true })

		const registration = await ctx.rpc.register(Inbox, {
			snapshot: async (input) => {
				const { sessionID } = input as { sessionID: string }
				return (await readSnapshot(sessionID, cli)) as Snapshot
			},
			triage: async (input, context) => {
				const { sessionID, action, id, note, resume } = input as {
					sessionID: string
					action: TriageAction
					id: string
					note?: string
					resume?: boolean
				}
				let snap: Snapshot
				try {
					snap = await runTriage(sessionID, action, id, note, cli)
				} catch (err) {
					const message = String(err instanceof Error ? err.message : err)
					return context.error("cli_failed", message, { message })
				}
				// Feed the answer back so the parked agent learns it. Default:
				// instruction entry applied at the next step boundary (stay
				// parked). resume: true → synthetic message, continue now.
				// Best-effort: the state change already landed; a dead session
				// must not turn a successful triage into an RPC error.
				if (action === "answer" && note) {
					const text = answerFeedback(id, note)
					try {
						if (resume) await ctx.session.synthetic({ sessionID, text })
						else await ctx.session.instructions.entry.put({ sessionID, key: `${HINT_KEY}:answer:${id}`, value: text })
					} catch {
						/* session gone or not promptable; the answer is still recorded */
					}
				}
				await registration.events.emit("changed", { sessionID, counts: snap.counts })
				return snap
			},
		})

		// --- state dir watch → changed events ---------------------------------
		// The CLI is the writer (any harness); fs.watch keeps every connected
		// TUI current without polling. Debounced per session; a failed read is
		// just a missed beat — the next event or a fresh snapshot() recovers.
		const timers = new Map<string, NodeJS.Timeout>()
		const watcher = fs.watch(stateDir, (_event, filename) => {
			if (!filename || !filename.endsWith(".json")) return
			const sessionID = filename.slice(0, -".json".length)
			const existing = timers.get(sessionID)
			if (existing) clearTimeout(existing)
			timers.set(
				sessionID,
				setTimeout(async () => {
					timers.delete(sessionID)
					try {
						const snap = await readSnapshot(sessionID, cli)
						await registration.events.emit("changed", { sessionID, counts: snap.counts })
					} catch {
						/* transient write race; next event retries */
					}
				}, WATCH_DEBOUNCE_MS),
			)
		})

		// --- session hint (replaces Claude's SessionStart hook) ---------------
		// One keyed instruction entry per session: survives compaction, applies
		// at the next step boundary, costs no extra model turn. Subscribes to
		// execution.started too (not just created) so sessions that predate the
		// plugin install still learn the CLI path on their next run; the keyed
		// put is idempotent, so repeat events are free.
		const controller = new AbortController()
		void (async () => {
			try {
				for await (const event of ctx.event.subscribe({
					types: ["session.created", "session.execution.started"],
					signal: controller.signal,
				})) {
					const data = event.data as { id?: string; sessionID?: string; session?: { id?: string } }
					const sessionID = data.session?.id ?? data.id ?? data.sessionID
					if (!sessionID) continue
					await ctx.session.instructions
						.entry.put({
							sessionID,
							key: HINT_KEY,
							value:
								`Inbox tracker is active for this session. Record blockers, decisions, and followups with: ` +
								`bash ${cli} --session ${sessionID} add question|decision|followup --title T [--context C] [--option O]... ` +
								`Questions are NON-BLOCKING by default: park the question, state your assumption as a decision if needed, and keep working. ` +
								`Pass --blocking only when you genuinely cannot proceed without the user. ` +
								`Never poll or ask the user to check the inbox; the user reviews it from the sidebar/panel.`,
						})
						.catch(() => {
							/* session may already be gone */
						})
				}
			} catch {
				/* stream ended (dispose/abort) or transport error; hint seeding stops */
			}
		})()

		// --- read commands (parity with the Claude inbox skills) --------------
		// Claude ran the CLI through `!` blocks in skill bodies; OpenCode skills
		// can't, and command files can't resolve plugin-relative paths — so the
		// plugin registers the commands and shells out itself.
		const commandReg = await ctx.command.transform((editor) => {
			for (const [name, { kind, header }] of Object.entries(LIST_KINDS)) {
				editor.add({
					name,
					description: `Show ${name.split(":")[1]} from the session inbox`,
					execute: async ({ sessionID, prompt, delivery }) => {
						const args = ["--session", sessionID, "list", "--format", "text"]
						if (kind) args.push("--kind", kind)
						const { execFile } = await import("node:child_process")
						const { promisify } = await import("node:util")
						const output = await promisify(execFile)("bash", [cli, ...args]).then((r) => r.stdout.trim())
						await ctx.session.prompt({
							...prompt,
							sessionID,
							delivery,
							text: `${header} (present the list to the user as-is; do not act on it unless they ask):\n\n${output || "(inbox empty)"}`,
						})
					},
				})
			}
		})

		return () => {
			controller.abort()
			watcher.close()
			for (const t of timers.values()) clearTimeout(t)
			timers.clear()
			void commandReg.dispose()
			void registration.dispose()
		}
	},
})
