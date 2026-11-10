import { Rpc } from "@opencode/plugin/rpc"

// Shared contract between the server part, the TUI part, and any external
// client. The server implements it over the vendored `scripts/inbox` CLI so
// every harness shares one state file; the TUI only ever talks RPC (it may be
// attached to a remote server and must not read local files).
const countsSchema = {
	type: "object",
	properties: {
		questions: { type: "number" },
		decisions: { type: "number" },
		followups: { type: "number" },
		blocking: { type: "number" },
	},
	required: ["questions", "decisions", "followups", "blocking"],
	additionalProperties: false,
} as const

const itemsSchema = {
	type: "object",
	properties: {
		questions: { type: "array", items: { type: "object" } },
		decisions: { type: "array", items: { type: "object" } },
		followups: { type: "array", items: { type: "object" } },
	},
	required: ["questions", "decisions", "followups"],
	additionalProperties: false,
} as const

const snapshotSchema = {
	type: "object",
	properties: { counts: countsSchema, items: itemsSchema },
	required: ["counts", "items"],
	additionalProperties: false,
} as const

export const Inbox = Rpc.define({
	id: "agent-toolkit.inbox",
	methods: {
		snapshot: {
			input: {
				type: "object",
				properties: { sessionID: { type: "string" } },
				required: ["sessionID"],
				additionalProperties: false,
			},
			output: snapshotSchema,
		},
		// Triage from the TUI panel: answer Q<n> / resolve D<n> / done F<n>.
		// `resume: true` on an answer pushes a synthetic message so a parked
		// session continues now; otherwise the answer lands as a session
		// instruction entry applied at the next step boundary.
		triage: {
			input: {
				type: "object",
				properties: {
					sessionID: { type: "string" },
					action: { type: "string", enum: ["answer", "resolve", "done"] },
					// ref shape (Q1/D2/F3) is validated by the CLI itself;
					// JSON Schema `pattern` is disabled in RPC validation.
					id: { type: "string" },
					note: { type: "string" },
					resume: { type: "boolean" },
				},
				required: ["sessionID", "action", "id"],
				additionalProperties: false,
			},
			output: snapshotSchema,
			errors: {
				cli_failed: {
					type: "object",
					properties: { message: { type: "string" } },
					required: ["message"],
					additionalProperties: false,
				},
			},
		},
	},
	events: {
		changed: {
			schema: {
				type: "object",
				properties: { sessionID: { type: "string" }, counts: countsSchema },
				required: ["sessionID", "counts"],
				additionalProperties: false,
			},
		},
	},
})
