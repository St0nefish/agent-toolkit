import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Git, Limit, Snap, Who } from '../types'

const gitAtom = atom({ plugin: 'statusline-mod', key: 'git' } as const, null)
const snapAtom = atom({ plugin: 'statusline-mod', key: 'snap' } as const, null)
const nowAtom = atom({ plugin: 'statusline-mod', key: 'now' } as const, 0)
const whoAtom = atom({ plugin: 'statusline-mod', key: 'who' } as const, null)

const BAR_CELLS = 10
const COST_WARN = 5
const COST_ERROR = 20
// Reset countdowns stay out of the way until a window is worth watching.
const COUNTDOWN_FROM_PCT = 50

// Powerline glyphs (Nerd Font / Powerline-patched fonts), all sharp:
// solid arrows cap each band, thin arrows divide segments inside it.
const CAP_START = '' // <
const CAP_END = '' // >
const THIN_RIGHT = '' // inside a band that reads left to right
const THIN_LEFT = '' // inside a band that reads right to left

// Muted, p10k-like: one quiet background, colour carried by the text.
const BG = '#303030'
const RULE = '#6c6c6c'
const DIM = '#8a8a8a'
const TRACK = '#585858'
const YELLOW = '#d7af5f'
const BLUE = '#5fafd7'
const GREEN = '#87af87'
const RED = '#d75f5f'
const ORANGE = '#d7875f'
const SILVER = '#bcbcbc'

type Part = { t: string; fg: string; bold?: boolean }
// A segment is a run of coloured parts; `shrink` names the one part that may
// ellipsize when the band runs out of room (the branch name).
type Seg = { parts: Part[]; shrink?: number }

const P = (t: string, fg: string, bold?: boolean): Part => ({ t, fg, bold })

const levelColor = (pct: number) => (pct >= 80 ? RED : pct >= 50 ? YELLOW : GREEN)

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

const readGit = async ($: any): Promise<Git | null> => {
  const cwd: string = await $.session.cwd()
  const status = await $.process.run(['git', 'status', '--porcelain=v2', '--branch'], {
    cwd,
    timeoutMs: 3000,
  })
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

  const paths = await $.process.run(
    ['git', 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir', '--show-toplevel'],
    { cwd, timeoutMs: 3000 },
  )
  const [gitDir, common, top] = paths.stdout.trim().split('\n')
  const isWorktree = !!gitDir && !!common && gitDir !== common
  const mainRoot = common?.replace(/\/\.git\/?$/, '') ?? top ?? cwd
  const project = (isWorktree ? mainRoot : (top ?? cwd)).split('/').pop() ?? ''

  return { branch, staged, unstaged, untracked, ahead, behind, isWorktree, project }
}

const refreshGit = async ($: any) => {
  const git = await readGit($)
  await update($, gitAtom, () => git)
}

const readWho = async ($: any): Promise<Who> => {
  const user = (await $.process.run(['id', '-un'], { timeoutMs: 2000 })).stdout.trim()
  const uid = (await $.process.run(['id', '-u'], { timeoutMs: 2000 })).stdout.trim()
  const isRemote = !!(await $.env.get('SSH_CONNECTION'))
  const host = isRemote
    ? (await $.process.run(['hostname', '-s'], { timeoutMs: 2000 })).stdout.trim()
    : null
  return { user, host, isRoot: uid === '0' }
}

const refreshSnap = async (
  $: any,
  u: { context: { percent?: number }; rateLimits: Limit[]; cost?: { usd: number } },
) => {
  const snap: Snap = {
    model: friendlyModel(await $.session.model()),
    contextPercent: u.context.percent ?? null,
    limits: u.rateLimits,
    costUsd: u.cost?.usd ?? null,
  }
  await update($, snapAtom, () => snap)
  await update($, nowAtom, () => Date.now())
}

const buildSegs = (
  git: Git | null,
  snap: Snap,
  now: number,
  who: Who | null,
  cols: number,
): { left: Seg[]; right: Seg[] } => {
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
      ...(withCountdown && l.percentUsed >= COUNTDOWN_FROM_PCT
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
    const isDirty = git.staged + git.unstaged + git.untracked > 0
    const chips: Part[] = [
      git.staged > 0 ? P(` +${git.staged}`, GREEN) : null,
      git.unstaged > 0 ? P(` !${git.unstaged}`, YELLOW) : null,
      git.untracked > 0 ? P(` ?${git.untracked}`, BLUE) : null,
      git.ahead > 0 ? P(` ⇡${git.ahead}`, GREEN) : null,
      git.behind > 0 ? P(` ⇣${git.behind}`, RED) : null,
    ].filter((c): c is Part => c !== null)
    left.push({
      parts: [P(`\ue0a0 ${git.branch}`, isDirty ? YELLOW : GREEN), ...chips],
      shrink: 0,
    })
  }

  const right: Seg[] = [{ parts: [P(snap.model, ORANGE, true)] }]
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
  if (five) right.push(limitSeg('◷', five, isMedium))
  if (week && isMedium) right.push(limitSeg('▦', week, true))
  if (!five && snap.costUsd !== null && snap.costUsd > 0) {
    const color = snap.costUsd >= COST_ERROR ? RED : snap.costUsd >= COST_WARN ? YELLOW : GREEN
    right.push({ parts: [P(`$${snap.costUsd.toFixed(2)}`, color)] })
  }
  return { left, right }
}

export const register: Register = (on, options) => {
  // "powerline" draws one dark band with Nerd Font arrows; "plain" uses the
  // same coloured text with thin bars and needs no patched font.
  const isPowerline = options.style !== 'plain'

  on('session.start', async ($, e, next) => {
    await update($, whoAtom, () => null)
    const who = await readWho($)
    await update($, whoAtom, () => who)
    await refreshGit($)
    await refreshSnap($, await $.session.usage())
    $.ui.status(undefined) // clear anything a previous version pinned
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await refreshSnap($, e)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await refreshGit($)
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    try {
      await refreshGit($)
    } catch {
      // a failed git refresh must never lose the tool result
    }
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const git = await read($, gitAtom)
    const snap = await read($, snapAtom)
    const now = await read($, nowAtom)
    const who = await read($, whoAtom)
    if (e.props.hasSurvey || !snap) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    // Width tiers: the band sheds detail from least to most important.
    const { left, right } = buildSegs(git, snap, now, who, e.props.bodyColumns)

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
          ...(i > 0 ? [pad(`${tag}${i}-pre`), divider(thin, `${tag}${i}-div`), pad(`${tag}${i}-post`)] : []),
          ...s.parts.map((part, j) => text(part, `${tag}${i}-${j}`, s.shrink === j)),
        ])}
        {isPowerline ? pad(`${tag}-pad1`) : null}
        {cap(CAP_END, `${tag}-end`)}
      </Box>
    )

    return (
      <Box marginTop={1}>
        {left.length ? band(left, THIN_RIGHT, 'l') : null}
        <Box flexGrow={1} />
        {band(right, THIN_LEFT, 'r')}
      </Box>
    )
  })
}
