export type Git = {
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

declare module 'claude-code' {
  interface PluginState {
    'statusline-mod': { git: Git | null; snap: Snap | null; now: number; who: Who | null }
  }
}
