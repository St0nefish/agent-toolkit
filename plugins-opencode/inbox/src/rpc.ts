import { Rpc } from "@opencode/plugin/rpc"

// Shared contract between the server part, the TUI part, and any external
// client. The server implements it over the vendored `scripts/inbox` CLI so
// every harness shares one state file; the TUI only ever talks RPC (it may be
// attached to a remote server and must not read local files).
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
      output: {
        type: "object",
        properties: {
          counts: {
            type: "object",
            properties: {
              questions: { type: "number" },
              decisions: { type: "number" },
              followups: { type: "number" },
              blocking: { type: "number" },
            },
            required: ["questions", "decisions", "followups", "blocking"],
            additionalProperties: false,
          },
          items: {
            type: "object",
            properties: {
              questions: { type: "array", items: { type: "object" } },
              decisions: { type: "array", items: { type: "object" } },
              followups: { type: "array", items: { type: "object" } },
            },
            required: ["questions", "decisions", "followups"],
            additionalProperties: false,
          },
        },
        required: ["counts", "items"],
        additionalProperties: false,
      },
    },
  },
  events: {
    changed: {
      schema: {
        type: "object",
        properties: {
          sessionID: { type: "string" },
          counts: {
            type: "object",
            properties: {
              questions: { type: "number" },
              decisions: { type: "number" },
              followups: { type: "number" },
              blocking: { type: "number" },
            },
            required: ["questions", "decisions", "followups", "blocking"],
            additionalProperties: false,
          },
        },
        required: ["sessionID", "counts"],
        additionalProperties: false,
      },
    },
  },
})
