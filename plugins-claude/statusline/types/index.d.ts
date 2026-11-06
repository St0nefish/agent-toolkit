export type Git = {
  inRepo: boolean
  branch: string
  staged: number
  unstaged: number
  untracked: number
  ahead: number
  behind: number
  isWorktree: boolean
  project: string
}
export type Limit = { kind: string; percentUsed: number; resetsAt?: string }
export type Snap = {
  model: string
  contextPercent: number | null
  limits: Limit[]
  costUsd: number | null
}
export type Who = { user: string; host: string | null; isRoot: boolean }
// Monthly extra credits, in dollars. capped: the monthly limit was hit; risingUntil: epoch ms until which
// the segment stays up because used credits recently went up (credits are being spent).
export type Extra = { used: number; limit: number; capped: boolean; risingUntil: number }

declare module 'claude-code' {
  interface PluginState {
    'statusline': {
      git: Git | null
      snap: Snap | null
      now: number
      who: Who | null
      extra: Extra | null
      questions: number
      decisions: number
    }
  }
}
