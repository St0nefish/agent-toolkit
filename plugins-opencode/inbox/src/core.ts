// Core inbox access: everything here is harness-free (no @opencode/plugin
// imports) so it can be unit-tested directly with node. The server part wires
// this to RPC; the TUI never touches the filesystem (it may be attached to a
// remote server) and goes through RPC instead.
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import { fileURLToPath } from "node:url"
import path from "node:path"
import os from "node:os"

const exec = promisify(execFile)

// Vendored from utils/inbox by utils/sync.sh — same CLI the Claude plugin
// uses, so both harnesses share one state file and the CLI's dedupe/locking
// stays the single source of truth.
export function inboxCliPath(): string {
	return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "scripts", "inbox")
}

export function inboxStateDir(): string {
	const xdg = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state")
	return process.env.INBOX_STATE_DIR || path.join(xdg, "claude-inbox")
}

export type InboxItem = {
	id: number
	title: string
	context?: string
	options?: string[]
	recommendation?: string
	chosen?: string
	blocking?: boolean
	added?: number
	[k: string]: unknown
}

export type Counts = {
	questions: number
	decisions: number
	followups: number
	blocking: number
}

export type Snapshot = {
	counts: Counts
	items: { questions: InboxItem[]; decisions: InboxItem[]; followups: InboxItem[] }
}

export const EMPTY_COUNTS: Counts = { questions: 0, decisions: 0, followups: 0, blocking: 0 }

export function countsOf(items: Snapshot["items"]): Counts {
	return {
		questions: items.questions.length,
		decisions: items.decisions.length,
		followups: items.followups.length,
		blocking: items.questions.filter((q) => q.blocking === true).length,
	}
}

// The CLI is the state machine: dedupe, locking, and the schema all live
// there. A missing state file is an empty inbox (the CLI prints empty arrays).
export async function readSnapshot(sessionID: string, cli = inboxCliPath()): Promise<Snapshot> {
	const { stdout } = await exec("bash", [cli, "--session", sessionID, "list", "--json"])
	const parsed = JSON.parse(stdout) as Partial<Snapshot["items"]>
	const items = {
		questions: parsed.questions ?? [],
		decisions: parsed.decisions ?? [],
		followups: parsed.followups ?? [],
	}
	return { counts: countsOf(items), items }
}

export type TriageAction = "answer" | "resolve" | "done"

const TRIAGE_VERBS: Record<TriageAction, string> = { answer: "answered", resolve: "resolved", done: "completed" }

// Run a triage action through the CLI (source of truth), then re-read.
export async function runTriage(
	sessionID: string,
	action: TriageAction,
	id: string,
	note?: string,
	cli = inboxCliPath(),
): Promise<Snapshot> {
	const args = ["--session", sessionID, action, id]
	if (note) args.push("--note", note)
	await exec("bash", [cli, ...args])
	return readSnapshot(sessionID, cli)
}

// Feedback text fed back into the session after an answer, so the parked
// agent (or the next step boundary) learns the user's reply.
export function answerFeedback(id: string, note: string): string {
	return `The user answered inbox question ${id}: ${note}. Take this as settled and proceed accordingly; record any resulting choice as a decision if you deviate from the stated assumption.`
}

export { TRIAGE_VERBS }
