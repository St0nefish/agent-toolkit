/** @jsxImportSource @opentui/solid */
import { Plugin, usePlugin } from "@opencode/plugin/tui"
import type { PanelInput } from "@opencode/plugin/tui/context"
import { createSignal, createEffect, For, Show } from "solid-js"
import { Inbox } from "./rpc.js"
import type { Counts, InboxItem, Snapshot } from "./core.js"

const PANEL = "agent-toolkit.inbox"

const EMPTY: Counts = { questions: 0, decisions: 0, followups: 0, blocking: 0 }

// Client-side store of snapshots, seeded by RPC (the TUI may be attached to a
// remote server — never read the state dir here). RPC events are live-only,
// so every consumer pulls a snapshot on mount and patches from then on.
function useInboxStore(context: { client: { rpc: (def: typeof Inbox) => any } }) {
	const rpc = context.client.rpc(Inbox)
	const [store, setStore] = createSignal<Record<string, Snapshot>>({})
	const inflight = new Set<string>()

	async function refresh(sessionID: string) {
		if (inflight.has(sessionID)) return
		inflight.add(sessionID)
		try {
			const snap = (await rpc.snapshot({ sessionID })) as unknown as Snapshot
			setStore((s) => ({ ...s, [sessionID]: snap }))
		} catch {
			/* server unreachable or session gone; next event or mount retries */
		} finally {
			inflight.delete(sessionID)
		}
	}

	const stop = rpc.events.on("changed", (event: { data: { sessionID: string } }) => {
		const { sessionID } = event.data
		void refresh(sessionID)
	})

	return { rpc, store, refresh, stop, counts: (id: string): Counts => store()[id]?.counts ?? EMPTY }
}

type Store = ReturnType<typeof useInboxStore>

// --- triage panel -------------------------------------------------------------

function InboxPanel(props: { panel: PanelInput }) {
	const context = usePlugin()
	const store = (context as unknown as { __inbox: Store }).__inbox
	const sessionID = () => props.panel.sessionID

	type Row = { ref: string; kind: "question" | "decision" | "followup"; title: string; blocking: boolean }
	const rows = (): Row[] => {
		const snap = store.store()[sessionID()]
		if (!snap) return []
		const map = (items: InboxItem[], kind: Row["kind"], pfx: string): Row[] =>
			items.map((it) => ({
				ref: `${pfx}${it.id}`,
				kind,
				title: it.title,
				blocking: kind === "question" && it.blocking === true,
			}))
		return [
			...map(snap.items.questions, "question", "Q"),
			...map(snap.items.decisions, "decision", "D"),
			...map(snap.items.followups, "followup", "F"),
		]
	}

	const [sel, setSel] = createSignal(0)
	const [err, setErr] = createSignal<string | undefined>(undefined)
	createEffect(() => void store.refresh(sessionID()))
	context.keymap.layer(() => {
		const n = rows().length
		const clamp = (i: number) => (n === 0 ? 0 : Math.max(0, Math.min(n - 1, i)))
		return {
			commands: [
				{ id: "inbox.down", title: "Next item", bind: "down", run: () => { setSel((i) => clamp(i + 1)) } },
				{ id: "inbox.up", title: "Previous item", bind: "up", run: () => { setSel((i) => clamp(i - 1)) } },
				{
					id: "inbox.answer",
					title: "Answer question",
					bind: "a",
					run: async () => {
						const row = rows()[sel()]
						if (!row || row.kind !== "question") return
						const note = await context.ui.dialog.prompt({
							title: `Answer ${row.ref}`,
							placeholder: "Your answer…",
						})
						if (note === undefined) return
						try {
							await store.rpc.triage({ sessionID: sessionID(), action: "answer", id: row.ref, note, resume: true })
							setErr(undefined)
						} catch (e) {
							setErr(`triage failed: ${e instanceof Error ? e.message : String(e)}`)
						}
					},
				},
				{
					id: "inbox.resolve",
					title: "Acknowledge decision/followup",
					bind: "d",
					run: async () => {
						const row = rows()[sel()]
						if (!row || row.kind === "question") return
						try {
							await store.rpc.triage({ sessionID: sessionID(), action: row.kind === "decision" ? "resolve" : "done", id: row.ref })
							setErr(undefined)
						} catch (e) {
							setErr(`triage failed: ${e instanceof Error ? e.message : String(e)}`)
						}
					},
				},
				{ id: "inbox.refresh", title: "Refresh", bind: "r", run: () => store.refresh(sessionID()) },
			],
		}
	})

	const kindLabel = { question: "🛑 question", decision: "✎ decision", followup: "☐ followup" } as const
	return (
		<box>
			<text fg={context.theme.text.base}>Inbox — {sessionID()}</text>
			<Show when={rows().length === 0}>
				<text fg={context.theme.text.muted}>Nothing open. </text>
			</Show>
			<For each={rows()}>
				{(row, i) => (
					<text fg={i() === sel() ? context.theme.background.base : context.theme.text.muted} bg={i() === sel() ? context.theme.text.base : undefined}>
						{`${row.blocking ? "🛑" : kindLabel[row.kind].slice(0, 1)} ${row.ref}  ${row.title}`}
					</text>
				)}
			</For>
			<Show when={err()}>
				<text fg={context.theme.text.base}>{err()}</text>
			</Show>
			<text fg={context.theme.text.muted}>↑/↓ move · a answer · d acknowledge · r refresh</text>
		</box>
	)
}

// --- plugin -------------------------------------------------------------------

export default Plugin.define({
	id: "agent-toolkit.inbox.tui",
	setup(context) {
		const store = useInboxStore(context)
		// The panel component needs the store; usePlugin() hands it the context.
		;(context as unknown as { __inbox: Store }).__inbox = store

		// Footer flag for the current session (home screen has no session, so
		// resolve the most recently updated one and re-render on switch).
		const currentSession = (): string | undefined => {
			const sessions = context.data.session.list() as Array<{ id: string; time?: { updated?: number } }>
			if (!sessions?.length) return undefined
			return sessions.toSorted((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0))[0]?.id
		}
		const unFooter = context.ui.slot({
			append: "home.footer.status",
			render: () => {
				const id = currentSession()
				// Seed the store: RPC events are live-only, so without this the
				// footer stays empty until the next inbox write anywhere.
				createEffect(() => {
					const sid = currentSession()
					if (sid) void store.refresh(sid)
				})
				if (!id) return null
				const c = store.counts(id)
				if (c.questions + c.decisions + c.followups === 0) return null
				return <text>{`🛑 ${c.questions} · ✎ ${c.decisions} · ☐ ${c.followups}`}</text>
			},
		})

		// Sidebar: open questions for the session being rendered.
		const unSidebar = context.ui.slot({
			append: "sidebar.content",
			render: ({ sessionID }: { sessionID: string }) => {
				createEffect(() => void store.refresh(sessionID))
				const snap = () => store.store()[sessionID]
				return (
					<Show when={(snap()?.items.questions.length ?? 0) > 0}>
						<text fg={context.theme.text.base}>Inbox</text>
						<For each={snap()?.items.questions ?? []}>
							{(q) => <text fg={context.theme.text.muted}>{`${q.blocking ? "🛑" : "·"} ${q.title}`}</text>}
						</For>
					</Show>
				)
			},
		})

		// Triage panel + /inbox door.
		const unPanel = context.ui.slot({
			append: "session.panel",
			render: (panel: PanelInput) => (
				<Show when={panel.name === PANEL}>
					<InboxPanel panel={panel} />
				</Show>
			),
		})
		context.keymap.layer(() => ({
			mode: "global",
			priority: 10,
			commands: [
				{
					id: "agent-toolkit.inbox.open",
					title: "Open inbox",
					group: "Inbox",
					palette: true,
					slash: { name: "inbox" },
					run: () => {
						context.ui.panel.open(PANEL)
					},
				},
			],
			bindings: [],
		}))

		// Attention: ping only on genuine stop signals — a blocking question
		// when a run ends, or the native question-tool form / permission ask.
		// Open non-blocking items stay passive (sidebar/footer only).
		const ping = (message: string) =>
			context.attention
				.notify({ title: "agent-toolkit inbox", message, notification: { when: "blurred" }, sound: { name: "done", volume: 0.5, when: "always" } })
				.catch(() => {})
		// Only ping for the session the user is actually looking at; a form or
		// permission ask in some background session is not "waiting for you".
		// Events without a sessionID (older servers) ping conservatively.
		const forCurrent = (data: unknown) => {
			const sid = (data as { sessionID?: string })?.sessionID
			return !sid || sid === currentSession()
		}
		const offs = [
			context.data.on("session.execution.succeeded", (event) => {
				const sid = (event.data as { sessionID?: string })?.sessionID
				if (!sid) return
				void (async () => {
					await store.refresh(sid)
					if (store.counts(sid).blocking > 0 && sid === currentSession()) void ping("A blocking question needs you")
				})()
			}),
			context.data.on("form.created", (event) => {
				if (forCurrent(event.data)) void ping("The agent is waiting for your answer")
			}),
			context.data.on("permission.asked", (event) => {
				if (forCurrent(event.data)) void ping("The agent needs permission")
			}),
		]

		return () => {
			store.stop()
			unFooter()
			unSidebar()
			unPanel()
			for (const off of offs) off()
		}
	},
})
