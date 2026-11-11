import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Extra, Git, Limit, Snap, Who } from '../types'

const gitAtom = atom({ plugin: 'statusline', key: 'git' } as const, null)
const snapAtom = atom({ plugin: 'statusline', key: 'snap' } as const, null)
const nowAtom = atom({ plugin: 'statusline', key: 'now' } as const, 0)
const whoAtom = atom({ plugin: 'statusline', key: 'who' } as const, null)
const extraAtom = atom({ plugin: 'statusline', key: 'extra' } as const, null)
const questionsAtom = atom({ plugin: 'statusline', key: 'questions' } as const, 0)
const decisionsAtom = atom({ plugin: 'statusline', key: 'decisions' } as const, 0)
const followupsAtom = atom({ plugin: 'statusline', key: 'followups' } as const, 0)

// Extra credits are not in session.measure, so they come from the same usage
// endpoint the old script polled, at most this often.
const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'
const EXTRA_TTL_MS = 300_000
// While spilling into extra credits the figure moves, so poll faster.
const EXTRA_ACTIVE_TTL_MS = 60_000
// How long a rise in used credits keeps the segment up after the last rise.
const EXTRA_RISING_HOLD_MS = 600_000

const BAR_CELLS = 10

// Powerline glyphs (Nerd Font / Powerline-patched fonts), all sharp:
// solid arrows cap each band, thin arrows divide segments inside it.
const CAP_START = '' // <
const CAP_END = '' // >
const THIN_RIGHT = '' // inside a band that reads left to right
const THIN_LEFT = '' // inside a band that reads right to left

// One quiet background with the colour carried by the text, as in the zsh
// Powerlevel10k prompt. Colours are names, not hex, so they follow the
// terminal palette and Claude Code's own theme instead of drifting from them.
// The band background is the one fixed value: p10k's 236, which no palette
// name stands in for.
const BG = '#303030'
const RULE = 'gray'
const DIM = 'inactive'
// Glyph for the pending-decisions segment; a one-line swap.
const DECISIONS_GLYPH = '✎'
// Glyph for the open-followups segment (an open checkbox); a one-line swap.
const FOLLOWUPS_GLYPH = '☐'
const TRACK = 'subtle'
const YELLOW = 'yellow'
const BLUE = 'blueBright'
const GREEN = 'green'
const RED = 'red'
const ORANGE = 'claude'
const SILVER = 'text'
// Severity follows Claude Code's own success / warning / error colours.
const OK = 'success'
const WARN = 'warning'
const BAD = 'error'

type Part = { t: string; fg: string; bold?: boolean }
// A segment is a run of coloured parts; `shrink` names the one part that may
// ellipsize when the band runs out of room (the branch name).
type Seg = { parts: Part[]; shrink?: number }

const P = (t: string, fg: string, bold?: boolean): Part => ({ t, fg, bold })

const levelColor = (pct: number) => (pct >= 80 ? BAD : pct >= 50 ? WARN : OK)

// "claude-sonnet-5-5" -> "Sonnet 5.5", "claude-3-5-haiku-20241022" -> "Haiku 3.5",
// "claude-opus-4-1[1m]" -> "Opus 4.1 (1M)".
const friendlyModel = (id: string) => {
  const ctx = /\[(\d+)m\]/i.exec(id)
  const parts = id
    .replace(/\[.*\]/, '')
    .replace(/^claude-/, '')
    .replace(/-\d{8}$/, '')
    .split('-')
  const family = parts.find(p => /^[a-z]/i.test(p))
  const version = parts.filter(p => /^\d+$/.test(p)).join('.')
  if (!family) return id
  const name = family.charAt(0).toUpperCase() + family.slice(1)
  return `${name}${version ? ` ${version}` : ''}${ctx ? ` (${ctx[1]}M)` : ''}`
}

const countdown = (iso: string | undefined, now: number) => {
  if (!iso) return ''
  const mins = Math.max(0, Math.round((Date.parse(iso) - now) / 60000))
  const d = Math.floor(mins / 1440)
  const h = Math.floor((mins % 1440) / 60)
  const m = mins % 60
  return d > 0 ? `${d}d${h}h` : h > 0 ? `${h}h${String(m).padStart(2, '0')}m` : `${m}m`
}

const layouts = new Map<string, { stdout: string }>()
let gitFailures = 0

const layoutOf = async ($: any, cwd: string) => {
  const known = layouts.get(cwd)
  if (known) return known
  const res = await $.process.run(
    ['git', 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir', '--show-toplevel'],
    { cwd, timeoutMs: 3000 },
  )
  // Only a successful answer is worth keeping: outside a repo it may become one.
  if (res.exitCode === 0) layouts.set(cwd, { stdout: res.stdout })
  return res
}

const queryGit = async ($: any, cwd: string) => {
  // --no-optional-locks: the poll must never take the index lock, or it makes the
  // user's own git commands fail (and its own status fail) while they overlap.
  const status = await $.process.run(
    ['git', '--no-optional-locks', 'status', '--porcelain=v2', '--branch'],
    { cwd, timeoutMs: 3000 },
  )
  if (status.exitCode !== 0) return null

  let branch = ''
  let ahead = 0
  let behind = 0
  let staged = 0
  let unstaged = 0
  let untracked = 0
  for (const line of status.stdout.split('\n')) {
    if (line.startsWith('# branch.head ')) branch = line.slice(14)
    else if (line.startsWith('# branch.ab ')) {
      const m = /\+(\d+) -(\d+)/.exec(line)
      if (m) [ahead, behind] = [Number(m[1]), Number(m[2])]
    } else if (line.startsWith('?')) untracked += 1
    else if (line.startsWith('1 ') || line.startsWith('2 ')) {
      const xy = line.split(' ')[1]
      if (xy[0] !== '.') staged += 1
      if (xy[1] !== '.') unstaged += 1
    }
  }
  return { branch, ahead, behind, staged, unstaged, untracked }
}

const readGit = async ($: any): Promise<Git> => {
  const cwd: string = await $.session.cwd()
  // The repo layout does not change under a running session, so ask once per
  // directory; the status query is the only call that must run each time.
  const [c, paths] = await Promise.all([queryGit($, cwd), layoutOf($, cwd)])
  // A directory already proven to be a repo whose status now fails (lock contention, a
  // timeout under load) is a hiccup, not "left the repo": throw so the caller keeps the
  // last good value instead of dropping the branch segment.
  // After a few failures in a row it is believed (a corrupt index, a removed .git).
  if (!c && layouts.has(cwd) && ++gitFailures < 5) throw new Error('git status failed in a known repo')
  if (c) gitFailures = 0
  // Outside a repo there is no branch, but the project marker must still show.
  if (!c) {
    return {
      inRepo: false,
      branch: '',
      staged: 0,
      unstaged: 0,
      untracked: 0,
      ahead: 0,
      behind: 0,
      isWorktree: false,
      project: cwd.split('/').filter(Boolean).pop() ?? cwd,
    }
  }
  const { branch, ahead, behind, staged, unstaged, untracked } = c

  const [gitDir, common, top] = paths.stdout.trim().split('\n')
  const isWorktree = !!gitDir && !!common && gitDir !== common
  const mainRoot = common?.replace(/\/\.git\/?$/, '') ?? top ?? cwd
  const project = (isWorktree ? mainRoot : (top ?? cwd)).split('/').pop() ?? ''

  return { inRepo: true, branch, staged, unstaged, untracked, ahead, behind, isWorktree, project }
}

let lastGit = ''
let lastNowAt = 0

// Returns whether anything the line shows moved, so a poll that found nothing new
// can leave the file and the screen alone.
const refreshGit = async ($: any): Promise<boolean> => {
  let git: Git
  try {
    git = await readGit($)
  } catch {
    return false // keep the last good value; the next poll tries again
  }
  const key = JSON.stringify(git)
  const changed = key !== lastGit
  if (changed) {
    lastGit = key
    await update($, gitAtom, () => git)
  }
  // Reset countdowns are measured against this: keep it fresh to the minute.
  const at = Date.now()
  if (changed || at - lastNowAt > 30_000) {
    lastNowAt = at
    await update($, nowAtom, () => at)
    return true
  }
  return false
}

let polling = false

// The idle poll: git can change with no event here (another terminal, a subagent),
// so look again and only redraw when something the line shows moved.
const pollGit = async ($: any, isBelow: boolean) => {
  if (polling) return // a slow status must not stack up behind itself
  polling = true
  try {
    const moved = await refreshGit($)
    // user@host is read once at start; if that read failed, retry until it lands.
    const whoFixed = await ensureWho($)
    if (isBelow) {
      if (moved || whoFixed) await publish($)
      else await healLine($)
    }
  } catch {
    // the next tick tries again
  } finally {
    polling = false
  }
}

// Open items parked by the `inbox` plugin. No plugin-root API reaches the mod, so read its
// state file directly: $XDG_STATE_HOME/claude-inbox/<session>.json, questions = length of
// .questions, decisions = length of .decisions, followups = length of .followups. A missing or unreadable file, or a missing
// key (older files have no decisions), means none.
const countOf = (v: unknown): number => (Array.isArray(v) ? v.length : 0)

type InboxCounts = { questions: number; decisions: number; followups: number }

// null: the file was unreadable right now (a half-written file, a timeout), which is not
// the same as "no items" and must not blink the flags off.
const countInbox = (json: string): InboxCounts | null => {
  try {
    const s = JSON.parse(json)
    return { questions: countOf(s?.questions), decisions: countOf(s?.decisions), followups: countOf(s?.followups) }
  } catch {
    return null
  }
}

// The `inbox` plugin is optional: a missing state file (plugin never installed, nothing
// parked yet) reads as "none". A failure to read at all reads as null: keep what we had.
const readInbox = async ($: any): Promise<InboxCounts | null> => {
  try {
    const base = (await $.env.get('XDG_STATE_HOME')) || `${await $.env.get('HOME')}/.local/state`
    const id = await $.session.id()
    const res = await $.process.run(['cat', `${base}/claude-inbox/${id}.json`], { timeoutMs: 2000 })
    if (res.exitCode === 0) return countInbox(res.stdout)
    // cat exits 1 for a missing file (nothing parked); anything else is a kill or timeout.
    return res.exitCode === 1 ? { questions: 0, decisions: 0, followups: 0 } : null
  } catch {
    return null
  }
}

// Returns whether either count moved.
const refreshInbox = async ($: any): Promise<boolean> => {
  const n = await readInbox($)
  if (!n) return false
  let changed = false
  await update($, questionsAtom, (prev: number) => {
    changed = changed || prev !== n.questions
    return n.questions
  })
  await update($, decisionsAtom, (prev: number) => {
    changed = changed || prev !== n.decisions
    return n.decisions
  })
  await update($, followupsAtom, (prev: number) => {
    changed = changed || prev !== n.followups
    return n.followups
  })
  return changed
}

let inboxPolling = false

const pollInbox = async ($: any, isBelow: boolean) => {
  if (inboxPolling) return
  inboxPolling = true
  try {
    if ((await refreshInbox($)) && isBelow) await publish($)
  } catch {
    // the next tick tries again
  } finally {
    inboxPolling = false
  }
}

// After a tool that can change the working tree: re-read git and redraw.
const afterTool = async ($: any, isBelow: boolean) => {
  try {
    await refreshGit($)
    if (isBelow) await publish($)
  } catch {
    // a failed git refresh must never lose the tool result
  }
}

const readWho = async ($: any): Promise<Who> => {
  const user = (await $.process.run(['id', '-un'], { timeoutMs: 2000 })).stdout.trim()
  const uid = (await $.process.run(['id', '-u'], { timeoutMs: 2000 })).stdout.trim()
  const isRemote = !!(await $.env.get('SSH_CONNECTION'))
  const host = isRemote
    ? (await $.process.run(['hostname', '-s'], { timeoutMs: 2000 })).stdout.trim()
    : null
  // An empty answer (a spawn that timed out under load) would draw "" or "@host".
  if (!user || (isRemote && !host)) throw new Error('incomplete user@host')
  return { user, host, isRoot: uid === '0' }
}

// Fill whoAtom if it is still empty. Returns whether it just landed.
let whoTriedAt = 0
const ensureWho = async ($: any): Promise<boolean> => {
  if (await read($, whoAtom)) return false
  // Retry at most every 30s: never gives up, but a host with no passwd entry does not
  // spawn two processes on every poll either.
  if (Date.now() - whoTriedAt < 30_000) return false
  whoTriedAt = Date.now()
  try {
    const who = await readWho($)
    await update($, whoAtom, () => who)
    return true
  } catch {
    return false // the next poll tries again
  }
}

const refreshSnap = async (
  $: any,
  u: { context: { percent?: number }; rateLimits: Limit[]; cost?: { usd: number } },
) => {
  // The rate-limit windows are empty until a response reports them (right after a
  // /clear or a restart). Keep the last known ones until their reset time passes
  // rather than dropping the segments for a while.
  const prev: Snap | null = await read($, snapAtom)
  const limits =
    u.rateLimits.length || !prev
      ? u.rateLimits
      : prev.limits.filter(l => !l.resetsAt || Date.parse(l.resetsAt) > Date.now())
  const snap: Snap = {
    model: friendlyModel(await $.session.model()),
    contextPercent: u.context.percent ?? null,
    limits,
    costUsd: u.cost?.usd ?? null,
  }
  await update($, snapAtom, () => snap)
  await update($, nowAtom, () => Date.now())
}

const loadSnap = async ($: any) => refreshSnap($, await $.session.usage())

// /model changes no usage figure, so session.measure never fires for it: re-read the
// model on the events that do fire around a switch, and report whether it moved.
const refreshModel = async ($: any) => {
  const model = friendlyModel(await $.session.model())
  let changed = false
  await update($, snapAtom, (s: Snap | null) => {
    if (!s || s.model === model) return s
    changed = true
    return { ...s, model }
  })
  return changed
}

const syncModel = async ($: any, isBelow: boolean) => {
  try {
    if ((await refreshModel($)) && isBelow) await publish($)
  } catch {
    // a failed model refresh must never block the prompt
  }
}

// Extra credits take over once an included limit is fully used, so they are "in
// play" when any reported limit is at 100%, the monthly cap has been hit, or the
// used amount has recently risen. Cumulative monthly spend alone does not count:
// it stays above zero for the rest of the month.
const limitExhausted = (snap: Snap): boolean => snap.limits.some(l => l.percentUsed >= 100)
const isSpilling = (extra: Extra, snap: Snap, now: number): boolean =>
  extra.capped || extra.risingUntil > now || limitExhausted(snap)

const buildSegs = (
  git: Git | null,
  snap: Snap,
  now: number,
  who: Who | null,
  extra: Extra | null,
  questions: number,
  decisions: number,
  followups: number,
  cols: number,
  // The git-branch glyph needs a Nerd Font; the plain style passes a standard one.
  branchIcon = '\ue725',
): { left: Seg[]; right: Seg[]; usage: Seg[] } => {
  const isWide = cols >= 110
  const isMedium = cols >= 80
  const barCells = isWide ? BAR_CELLS : isMedium ? 6 : 0

  const five = snap.limits.find(l => l.kind === 'five_hour')
  const week = snap.limits.find(l => l.kind === 'seven_day')
  const pct = snap.contextPercent

  const limitSeg = (icon: string, l: Limit, withCountdown: boolean): Seg => ({
    parts: [
      P(`${icon} `, DIM),
      P(`${Math.round(l.percentUsed)}%`, levelColor(l.percentUsed)),
      ...(withCountdown
        ? [P(` ${countdown(l.resetsAt, now)}`, DIM)]
        : []),
    ],
  })

  const left: Seg[] = []
  if (who && isWide) {
    left.push({
      parts: [P(`${who.user}${who.host ? `@${who.host}` : ''}`, who.isRoot ? RED : YELLOW)],
    })
  }
  if (git) {
    left.push({ parts: [P(`${git.isWorktree ? '⧉' : '⌂'} ${git.project}`, BLUE, true)] })
  }
  if (git?.inRepo) {
    // The same grammar as the zsh prompt: the branch is always green and the
    // chips carry the colour (behind/ahead green, +/! yellow, ? blue).
    const chips: Part[] = [
      git.behind > 0 ? P(` ⇣${git.behind}`, GREEN) : null,
      git.ahead > 0 ? P(` ⇡${git.ahead}`, GREEN) : null,
      git.staged > 0 ? P(` +${git.staged}`, YELLOW) : null,
      git.unstaged > 0 ? P(` !${git.unstaged}`, YELLOW) : null,
      git.untracked > 0 ? P(` ?${git.untracked}`, BLUE) : null,
    ].filter((c): c is Part => c !== null)
    left.push({
      parts: [P(`${branchIcon} ${git.branch}`, GREEN), ...chips],
      shrink: 0,
    })
  }

  // Parked questions lead the right band: it never shrinks, so the flag survives narrow terminals.
  const right: Seg[] = []
  if (questions > 0) right.push({ parts: [P(`🛑 ${questions}`, BAD, true)] })
  if (decisions > 0 && showDecisions) {
    right.push({ parts: [P(`${DECISIONS_GLYPH} ${decisions}`, DIM)] })
  }
  if (followups > 0 && showFollowups) {
    right.push({ parts: [P(`${FOLLOWUPS_GLYPH} ${followups}`, DIM)] })
  }
  right.push({ parts: [P(`✦ ${snap.model}`, ORANGE, true)] })
  if (pct !== null) {
    const filled = Math.round((Math.min(100, Math.max(0, pct)) / 100) * barCells)
    right.push({
      parts: [
        ...(barCells > 0
          ? [P('▰'.repeat(filled), levelColor(pct)), P('▱'.repeat(barCells - filled) + ' ', TRACK)]
          : []),
        P(`${Math.round(pct)}%`, levelColor(pct)),
      ],
    })
  }
  // What you have left to spend: kept apart from the model and context so a
  // style can draw it somewhere else (the below style appends it after them).
  const usage: Seg[] = []
  if (five) usage.push(limitSeg('◷', five, isMedium))
  if (week && isMedium) usage.push(limitSeg('▦', week, true))
  // Only while extra credits are in play (see isSpilling), as used/monthly limit.
  if (extra && isSpilling(extra, snap, now)) {
    const pct = extra.limit > 0 ? (extra.used / extra.limit) * 100 : 0
    usage.push({
      parts: [
        P('⊕ ', DIM),
        P(
          extra.limit > 0
            ? `$${extra.used.toFixed(2)}/$${extra.limit.toFixed(2)}`
            : `$${extra.used.toFixed(2)}`,
          extra.capped ? BAD : levelColor(pct),
        ),
      ],
    })
  }
  // Claude Code's own list-price estimate for this session: not billed on a
  // subscription, so it is dim and marked with ~ rather than coloured by size.
  if (snap.costUsd !== null && snap.costUsd > 0) {
    usage.push({ parts: [P(`~$${snap.costUsd.toFixed(2)}`, DIM)] })
  }
  return { left, right, usage }
}

// The "below" style: a mod cannot draw coloured text under the prompt, but the
// engine's own statusLine slot can. The mod renders the finished line here, as
// ANSI, into a per-session file and a one-line statusLine command prints it.
// Names map to the 16-colour palette (or Claude's brand colour), so the line
// still follows the terminal theme rather than fixed hex values.
const ESC = String.fromCharCode(27)
const SGR: Record<string, string> = {
  yellow: '33',
  green: '32',
  red: '31',
  blueBright: '94',
  gray: '90',
  success: '32',
  warning: '33',
  error: '31',
  inactive: '90',
  subtle: '2;90',
  text: '39',
  claude: '38;2;215;119;87',
}
const ansiPart = (part: Part) =>
  `${ESC}[${part.bold ? '1;' : ''}${SGR[part.fg] ?? '39'}m${part.t}${ESC}[0m`

let dirReady = false
let lastLine = ''
let segmentGap = 1
let leftPad = 2
let showDecisions = true
let showFollowups = true

// The id and text last written, so a /clear (new id, no session.start) can carry the
// line over to the new id's file before anything else has rendered for it.
let lastId = ''
let lastText = ''

// Writes are queued one at a time. Overlapping publishes (measure, the git poll, the
// inbox poll) shared one .tmp file, and a rename landing between another's truncate and
// write left an empty line file, which the stub prints as nothing: a blank status line.
let queue: Promise<void> = Promise.resolve()
const enqueue = ($: any, job: () => Promise<void>): Promise<void> => {
  // A job that hangs (a stalled filesystem) is abandoned after 5s so it cannot wedge
  // every later publish, nor the hooks that await one. A failed write is retried by the
  // next tick.
  const bounded = () =>
    Promise.race([job(), $.clock.sleep(5000).catch(() => {})])
  queue = queue.then(bounded).catch(() => {})
  return queue
}

const publish = ($: any): Promise<void> => enqueue($, () => publishNow($))

// Before the first usage reading lands (or if it failed) there is no snap; a line with
// just the model beats no line.
const snapOrFallback = async ($: any): Promise<Snap | null> => {
  const snap: Snap | null = await read($, snapAtom)
  if (snap) return snap
  try {
    return { model: friendlyModel(await $.session.model()), contextPercent: null, limits: [], costUsd: null }
  } catch {
    return null
  }
}

const publishNow = async ($: any) => {
  const snap = await snapOrFallback($)
  if (!snap) return
  const { left, right, usage } = buildSegs(
    await read($, gitAtom),
    snap,
    await read($, nowAtom),
    await read($, whoAtom),
    await read($, extraAtom),
    await read($, questionsAtom),
    await read($, decisionsAtom),
    await read($, followupsAtom),
    200,
  )
  const segs = [...left, ...right, ...usage]
  // The default two leading spaces line the text up with the footer hint line above it.
  const line = `${' '.repeat(leftPad)}${segs.map(s => s.parts.map(ansiPart).join('')).join(' '.repeat(segmentGap))}`
  const id = await $.session.id()
  if (lastLine === `${id}\n${line}`) return // the file already says this
  await writeLine($, id, line)
}

// Write beside the file and rename, so the stub never reads it half-written.
const writeLine = async ($: any, id: string, line: string) => {
  const dir = await cacheDir($)
  if (!dirReady) {
    await $.process.run(['mkdir', '-p', dir], { timeoutMs: 2000 })
    dirReady = true
  }
  const file = `${dir}/${id}`
  await $.fs.write(`${file}.tmp`, `${line}\n`)
  const moved = await $.process.run(['mv', '-f', `${file}.tmp`, file], { timeoutMs: 2000 })
  if (moved.exitCode !== 0) throw new Error('could not move the line file into place')
  lastLine = `${id}\n${line}`
  lastId = id
  lastText = line
}

// /clear starts a new session id in the same process and fires no session.start, so
// nothing would write the new id's file until the next poll or usage reading, and the
// stub prints nothing without it. Notice the new id within half a second and copy the
// last line across; the real one replaces it as soon as it renders.
const carryOver = async ($: any): Promise<void> => {
  try {
    // The common case (same id) costs one call and never touches the write queue.
    if (!lastId || (await $.session.id()) === lastId) return
    await enqueue($, async () => {
      const id = await $.session.id()
      if (!lastText || id === lastId) return
      await writeLine($, id, lastText)
    })
  } catch {
    // the next tick tries again
  }
}

// The line file can vanish under a live session (a stale-file purge, another process
// ending on the same id, a session switch). Each idle tick touches it, which also keeps
// its mtime fresh for the purge, and rewrites it when it is gone.
const healLine = async ($: any) => {
  const file = `${await cacheDir($)}/${await $.session.id()}`
  const res = await $.process.run(['sh', '-c', 'test -s "$1" && touch "$1"', 'sh', file], {
    timeoutMs: 2000,
  })
  if (res.exitCode === 0) return
  lastLine = ''
  dirReady = false // the whole directory may be what vanished
  await publish($)
}

// Where the per-session lines live; scripts/statusline.sh reads the same place.
const cacheDir = async ($: any) => {
  const base = (await $.env.get('XDG_CACHE_HOME')) || `${await $.env.get('HOME')}/.cache`
  return `${base}/claude-statusline`
}

// Extra credits (cents -> dollars) from the usage endpoint, spent with the
// session's own credential so no token is ever read. Null off a subscription
// or when extra usage is not enabled; a failed request throws and the caller
// keeps the last value.
const readExtra = async ($: any): Promise<Extra | null> => {
  const auth = await $.session.authorize()
  if (!auth) return null
  const res = await $.http.fetch(USAGE_URL, {
    auth: auth.handle,
    headers: { 'anthropic-beta': 'oauth-2025-04-20' },
  })
  if (!res.ok) throw new Error(`usage ${res.status}`)
  const extra = JSON.parse(res.text).extra_usage
  if (!extra?.is_enabled) return null
  return {
    used: (extra.used_credits ?? 0) / 100,
    limit: (extra.monthly_limit ?? 0) / 100,
    capped: extra.spend_limit_reached === true,
    risingUntil: 0,
  }
}

let lastExtraAt = 0
let lastUsed: number | null = null
let risingUntil = 0

const refreshExtra = async ($: any) => {
  const at = await $.clock.now()
  const prev: Extra | null = await read($, extraAtom)
  const snap: Snap | null = await read($, snapAtom)
  const hot = !!prev && (prev.risingUntil > Date.now() || prev.capped || (!!snap && limitExhausted(snap)))
  if (at - lastExtraAt < (hot ? EXTRA_ACTIVE_TTL_MS : EXTRA_TTL_MS)) return false
  lastExtraAt = at
  try {
    const fetched = await readExtra($)
    // A rise since the last poll means credits are being spent right now.
    // risingUntil is judged against Date.now() at render, so it is set from the same clock.
    if (fetched && lastUsed !== null && fetched.used > lastUsed) {
      risingUntil = Date.now() + EXTRA_RISING_HOLD_MS
    }
    lastUsed = fetched ? fetched.used : null
    if (!fetched) risingUntil = 0
    const extra = fetched && { ...fetched, risingUntil }
    await update($, extraAtom, () => extra)
    return true
  } catch {
    // offline or rate-limited: keep showing the last value
    return false
  }
}

// The fetch is slow and rare, so the line goes out first and again if it brought news.
const refreshExtraAndPublish = async ($: any, isBelow: boolean) => {
  if ((await refreshExtra($)) && isBelow) await publish($)
}

export const register: Register = (on, options) => {
  // Where and how the line is drawn:
  //   below      under the prompt, in the statusLine slot (default). The mod
  //              renders the line and scripts/statusline.sh prints it.
  //   flat-left  above the prompt, flat coloured text packed left; needs no
  //              statusLine setup
  //   powerline  above the prompt, one dark band with Nerd Font arrows
  //   plain      above the prompt, coloured text with thin bars, no patched font
  const style = typeof options.style === 'string' ? options.style : 'below'
  const isBelow = style === 'below'
  const isLeft = style === 'flat-left'
  const isPowerline = style === 'powerline'
  // Flat text separates segments with space alone, no divider glyph.
  const isFlat = isLeft
  // Seconds between idle git checks; 0 turns the poll off.
  const pollSeconds =
    typeof options.gitPollSeconds === 'number' && options.gitPollSeconds >= 0
      ? options.gitPollSeconds
      : 3
  // Spaces between segments; 1 packs tighter for narrow terminals.
  segmentGap =
    typeof options.segmentGap === 'number' && options.segmentGap >= 1
      ? Math.floor(options.segmentGap)
      : 1
  // Spaces before the first segment of the below style.
  leftPad =
    typeof options.leftPad === 'number' && options.leftPad >= 0 ? Math.floor(options.leftPad) : 2
  // Show the pending-decisions segment; false hides it.
  showDecisions = options.showDecisions !== false
  // Show the open-followups segment; false hides it.
  showFollowups = options.showFollowups !== false
  let pollTimer: { cancel: () => void } | undefined
  let inboxTimer: { cancel: () => void } | undefined
  let idTimer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    // This runs once per process and on a plugin reload, never on /clear (see carryOver).
    // Reset the caches so a reload redraws everything.
    lastGit = ''
    lastNowAt = 0
    lastLine = ''
    lastId = ''
    lastText = ''
    whoTriedAt = 0
    // Independent loads: one slow or failing read (a git timeout, a hung `id`) must not
    // skip the others, the publish, or the pollers registered below. A throw here used
    // to abort the handler before any timer started, leaving the line frozen until the
    // next event and user@host missing for good.
    const [who] = await Promise.allSettled([
      readWho($),
      refreshGit($),
      refreshInbox($),
      loadSnap($),
    ])
    if (who.status === 'fulfilled') await update($, whoAtom, () => who.value)
    $.ui.status(undefined) // clear anything a previous version pinned
    if (isBelow) await publish($)
    else {
      // Drop a line left by an earlier "below" run, which the stub would keep printing.
      const stale = `${await cacheDir($)}/${await $.session.id()}`
      await $.process.run(['rm', '-f', stale], { timeoutMs: 2000 })
    }
    pollTimer?.cancel()
    if (pollSeconds > 0) pollTimer = $.clock.every(pollSeconds * 1000, () => pollGit($, isBelow))
    inboxTimer?.cancel()
    inboxTimer = $.clock.every(2000, () => pollInbox($, isBelow))
    idTimer?.cancel()
    if (isBelow) idTimer = $.clock.every(500, () => carryOver($))
    await refreshExtraAndPublish($, isBelow)
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    try {
      await refreshSnap($, e)
      if (isBelow) await publish($)
      await refreshExtraAndPublish($, isBelow)
    } catch {
      // never let a failed redraw block the engine's own measurement
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    await syncModel($, isBelow)
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    await syncModel($, isBelow)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    try {
      await refreshGit($)
      await refreshInbox($)
      await ensureWho($)
      if (isBelow) await publish($)
    } catch {
      // the next event or poll redraws
    }
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    await afterTool($, isBelow)
    return result
  })

  // Edits change the dirty counts too; without these they lag until the turn ends.
  on('tool.call', { tool: 'Edit' }, async ($, e, next) => {
    const result = await next(e)
    await afterTool($, isBelow)
    return result
  })

  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const result = await next(e)
    await afterTool($, isBelow)
    return result
  })

  // Deliberately no cleanup on session.end: a /clear (or resume) continues in the same
  // process under a new id, and deleting files or stopping the pollers would blank the
  // line the stub is about to print. The line file is tiny; sync-install.sh purges ones
  // a week stale.

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const git = await read($, gitAtom)
    const snap = await read($, snapAtom)
    const now = await read($, nowAtom)
    const who = await read($, whoAtom)
    const extra = await read($, extraAtom)
    const questions = await read($, questionsAtom)
    const decisions = await read($, decisionsAtom)
    const followups = await read($, followupsAtom)
    if (isBelow || e.props.hasSurvey || !snap) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    // Width tiers: the band sheds detail from least to most important.
    const cols: number = e.props.bodyColumns
    const built = buildSegs(git, snap, now, who, extra, questions, decisions, followups, cols, style === 'plain' ? '⎇' : undefined)
    const left = built.left
    const right = [...built.right, ...built.usage]

    // ---- drawing ----------------------------------------------------------
    const bg = isPowerline ? BG : undefined

    const text = (part: Part, key: string, shrinks: boolean) => (
      <Box key={key} flexShrink={shrinks ? 1 : 0}>
        <Text
          color={part.fg}
          backgroundColor={bg}
          bold={part.bold}
          wrap={shrinks ? 'truncate-middle' : undefined}
        >
          {part.t}
        </Text>
      </Box>
    )

    const pad = (key: string) => text(P(' ', SILVER), key, false)

    const divider = (glyph: string, key: string) =>
      isPowerline ? (
        <Box key={key} flexShrink={0}>
          <Text color={RULE} backgroundColor={BG}>
            {glyph}
          </Text>
        </Box>
      ) : (
        <Box key={key} flexShrink={0}>
          <Text color={RULE}>│</Text>
        </Box>
      )

    const cap = (glyph: string, key: string) =>
      isPowerline ? (
        <Box key={key} flexShrink={0}>
          <Text color={BG}>{glyph}</Text>
        </Box>
      ) : null

    // One dark band per side: cap, segments split by thin arrows, cap. The
    // arrows on both sides point inward, towards the gap between them.
    const band = (segs: Seg[], thin: string, tag: string) => (
      <Box flexShrink={tag === 'l' ? 1 : 0}>
        {cap(CAP_START, `${tag}-start`)}
        {isPowerline ? pad(`${tag}-pad0`) : null}
        {segs.flatMap((s, i) => [
          ...(i > 0
            ? isFlat
              ? Array.from({ length: segmentGap }, (_, k) => pad(`${tag}${i}-gap${k}`))
              : [pad(`${tag}${i}-pre`), divider(thin, `${tag}${i}-div`), pad(`${tag}${i}-post`)]
            : []),
          ...s.parts.map((part, j) => text(part, `${tag}${i}-${j}`, s.shrink === j)),
        ])}
        {isPowerline ? pad(`${tag}-pad1`) : null}
        {cap(CAP_END, `${tag}-end`)}
      </Box>
    )

    if (isLeft) {
      const all = [...left, ...right]
      return <Box marginTop={1}>{band(all, THIN_RIGHT, 'l')}</Box>
    }

    return (
      <Box marginTop={1}>
        {left.length ? band(left, THIN_RIGHT, 'l') : null}
        <Box flexGrow={1} />
        {band(right, THIN_LEFT, 'r')}
      </Box>
    )
  })
}
