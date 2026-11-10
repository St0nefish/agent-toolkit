import { Plugin } from "@opencode/plugin"
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import { fileURLToPath } from "node:url"
import path from "node:path"
import { Inbox } from "./rpc.js"

const exec = promisify(execFile)

// Vendored from utils/inbox by utils/sync.sh — same CLI the Claude plugin
// uses, so both harnesses share one state file and the CLI's dedupe/locking
// stays the single source of truth.
const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const INBOX_CLI = path.resolve(scriptDir, "..", "scripts", "inbox")

type Counts = { questions: number; decisions: number; followups: number; blocking: number }

type InboxItem = { id?: string; title?: string; blocking?: boolean; [k: string]: unknown }

type Snapshot = { counts: Counts; items: { questions: InboxItem[]; decisions: InboxItem[]; followups: InboxItem[] } }

export async function readSnapshot(sessionID: string): Promise<Snapshot> {
  const { stdout } = await exec(INBOX_CLI, ["--session", sessionID, "list", "--json"])
  const parsed = JSON.parse(stdout) as {
    questions: InboxItem[]
    decisions: InboxItem[]
    followups: InboxItem[]
  }
  const items = {
    questions: parsed.questions ?? [],
    decisions: parsed.decisions ?? [],
    followups: parsed.followups ?? [],
  }
  return {
    counts: {
      questions: items.questions.length,
      decisions: items.decisions.length,
      followups: items.followups.length,
      blocking: items.questions.filter((q) => q.blocking === true).length,
    },
    items,
  }
}

export default Plugin.define({
  id: "agent-toolkit.inbox",
  async setup(ctx) {
    const registration = await ctx.rpc.register(Inbox, {
      snapshot: async (input) => {
        const { sessionID } = input as { sessionID: string }
        return readSnapshot(sessionID)
      },
    })
    return () => void registration.dispose()
  },
})
