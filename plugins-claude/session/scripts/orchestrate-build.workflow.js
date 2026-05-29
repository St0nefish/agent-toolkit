export const meta = {
  name: 'session-orchestrate-build',
  description:
    'Execute an approved chunk plan in dependency waves with per-chunk failure escalation, then review executed chunks and auto-fix blockers (cap 2). Returns structured findings {perChunk, clean, concerns, unresolvedBlockers, nits, filesChanged} for the calling skill to gate on.',
  phases: [
    { title: 'Execute', detail: 'dispatch chunks in dependency waves, escalating failures (3 attempts, tier bump)' },
    { title: 'Review', detail: 'review executed chunks; auto-fix blockers and re-review (cap 2)' },
  ],
}

// ---------------------------------------------------------------------------
// session-orchestrate-build — Phase 5 (Execute) + Phase 6 (Review/auto-fix).
//
// This is the HEADLESS half of the session-orchestrate workflow. The skill
// runs the interactive halves (explore, refine gate, divide, execute gate,
// concerns gate, hand-off) and calls this script after the user approves the
// chunk plan. Blockers are objective (tests/lint/spec), so the auto-fix loop
// is safe to run without a human; CONCERNS are deliberately NOT auto-fixed —
// they are returned for the skill's interactive gate.
//
// args contract (constructed by the skill from the approved chunk plan):
//   {
//     description:   string,   // the user's feature description
//     plan:          string,   // the agreed implementation plan (markdown)
//     testsRequired: boolean,  // from Phase 4 test-infra detection
//     waves: [                 // dependency-ordered; waves run serially
//       [ chunk, chunk, ... ], // wave 0 — chunks here have no intra-wave deps
//       [ chunk, ... ],        // wave 1 — may depend on completed wave 0
//     ],
//   }
// chunk:
//   {
//     id:         string,                       // stable identifier, e.g. "c1"
//     scope:      string,                        // one-line description
//     files:      string[],                      // paths this chunk owns
//     model:      'haiku' | 'sonnet' | 'opus',   // tier from the chunk plan
//     tests:      boolean,                        // write/update tests here?
//     testScope?: string,                         // optional test guidance
//     opusReview?: boolean,                       // include in Opus review pass
//   }
// ---------------------------------------------------------------------------

if (!args || !Array.isArray(args.waves) || args.waves.length === 0) {
  throw new Error('orchestrate-build: args.waves must be a non-empty array of chunk arrays')
}

const TIERS = ['haiku', 'sonnet', 'opus']
const bump = (m) => TIERS[Math.min(TIERS.indexOf(m) + 1, TIERS.length - 1)]

const allChunks = args.waves.flat()
const findChunk = (id) => allChunks.find((c) => c.id === id)

const EXEC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['status', 'summary'],
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string', description: 'Concise description of what was changed' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsPassed: {
      type: 'boolean',
      description: 'true if tests were run and passed, false if run and failed; omit if not applicable',
    },
    blocker: { type: 'string', description: 'If status=blocked, describe the blocker precisely' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['chunkId', 'severity', 'title'],
        properties: {
          chunkId: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'concern', 'nit'] },
          title: { type: 'string' },
          detail: { type: 'string' },
          file: { type: 'string' },
        },
      },
    },
  },
}

const execPrompt = (chunk, extra) =>
  [
    `You are implementing ONE chunk of an approved feature plan. Stay strictly within this chunk's scope.`,
    ``,
    `## Feature`,
    args.description,
    ``,
    `## Agreed plan (context — do not re-litigate)`,
    args.plan,
    ``,
    `## Your chunk: ${chunk.id}`,
    `Scope: ${chunk.scope}`,
    `Files you own: ${(chunk.files || []).join(', ') || '(determine from scope; touch nothing owned by other chunks)'}`,
    chunk.tests
      ? `Tests: write/update tests for this chunk. ${chunk.testScope || ''}`.trim()
      : args.testsRequired
        ? `Tests: ensure existing tests still pass; you need not add new ones.`
        : `Tests: this project has no test suite requirement.`,
    ``,
    `## Rules`,
    `- Implement only this chunk. Do NOT modify files owned by other chunks.`,
    `- Follow existing codebase conventions: naming, file layout, imports, idioms.`,
    args.testsRequired ? `- Run the relevant tests/lint before reporting status="done".` : null,
    `- If you cannot complete it, set status="blocked" and describe the blocker precisely — do not guess or fake completion.`,
    extra ? `\n## Context for this attempt\n${extra}` : null,
  ]
    .filter((l) => l !== null)
    .join('\n')

// Execute one chunk with failure escalation (cap 3):
//   attempt 1 — original model + base prompt
//   attempt 2 — original model + prompt refined from the failure
//   attempt 3 — bumped tier + refined prompt
async function executeChunk(chunk, seedContext) {
  const baseModel = chunk.model || 'sonnet'
  let extra = seedContext || ''
  let last = null
  for (let attempt = 1; attempt <= 3; attempt++) {
    const useModel = attempt === 3 ? bump(baseModel) : baseModel
    const res = await agent(execPrompt(chunk, extra), {
      label: `exec:${chunk.id}#${attempt}`,
      phase: 'Execute',
      model: useModel,
      agentType: 'general-purpose',
      schema: EXEC_SCHEMA,
    })
    last = res
    if (res && res.status === 'done') {
      return { chunkId: chunk.id, ok: true, attempts: attempt, model: useModel, result: res }
    }
    const why = res ? res.blocker || res.summary : 'agent returned no result'
    extra = `Attempt ${attempt} did not complete. Reported blocker: ${why}\nClarify the success criteria and address this blocker directly.`
  }
  return {
    chunkId: chunk.id,
    ok: false,
    attempts: 3,
    model: bump(baseModel),
    result: last,
    blocker: last ? last.blocker || last.summary : 'no result after 3 attempts',
  }
}

const reviewPrompt = (id) => {
  const chunk = findChunk(id)
  const exec = execByChunk.get(id)
  return [
    `Review the implementation of ONE chunk for correctness, convention compliance, and spec adherence. You may read files and run tests/lint. Do NOT modify code.`,
    ``,
    `## Feature`,
    args.description,
    ``,
    `## Chunk under review: ${id}`,
    `Scope: ${chunk.scope}`,
    `Files: ${(chunk.files || []).join(', ')}`,
    `Implementer reported: ${exec && exec.result ? exec.result.summary : '(no summary)'}`,
    exec && !exec.ok ? `NOTE: the implementer reported this chunk as BLOCKED/incomplete after ${exec.attempts} attempts.` : null,
    ``,
    `## Check`,
    `- Codebase conventions: naming, file layout, imports, idioms`,
    args.testsRequired ? `- Tests pass; lint/type checks are clean` : `- (no test suite required for this project)`,
    `- Spec compliance: does it implement what the chunk asked for?`,
    `- Pitfalls: error paths, null/empty handling, dead code, stale TODOs, leftover debug output`,
    `- No regressions in unrelated code`,
    ``,
    `Tag each finding's severity: "blocker" (broken/wrong/tests fail — must fix), "concern" (should consider), "nit" (trivial). Set chunkId="${id}" on every finding. Return an empty findings array if clean.`,
  ]
    .filter((l) => l !== null)
    .join('\n')
}

const opusReviewPrompt = (ids) =>
  [
    `Senior correctness/security review of the following chunks ONLY. Read the code and reason hard about edge cases, concurrency, data integrity, auth, and security. Do NOT modify code.`,
    ``,
    `## Feature`,
    args.description,
    ``,
    `## Chunks in scope`,
    ...ids.map((id) => {
      const c = findChunk(id)
      return `- ${id}: ${c.scope} [${(c.files || []).join(', ')}]`
    }),
    ``,
    `Tag findings blocker/concern/nit and set chunkId to the relevant chunk. Empty findings array if clean.`,
  ].join('\n')

// Review a set of chunk ids: one Sonnet reviewer per chunk plus a single Opus
// reviewer over the warranted subset, all dispatched concurrently. Returns a
// deduped, flattened findings array.
async function reviewChunks(ids) {
  const warranted = ids.filter((id) => findChunk(id) && findChunk(id).opusReview)
  const thunks = ids.map((id) => () =>
    agent(reviewPrompt(id), {
      label: `review:${id}`,
      phase: 'Review',
      model: 'sonnet',
      agentType: 'general-purpose',
      schema: REVIEW_SCHEMA,
    }).then((r) => (r && r.findings) || []),
  )
  if (warranted.length) {
    thunks.push(() =>
      agent(opusReviewPrompt(warranted), {
        label: 'review:opus',
        phase: 'Review',
        model: 'opus',
        agentType: 'general-purpose',
        schema: REVIEW_SCHEMA,
      }).then((r) => (r && r.findings) || []),
    )
  }
  const results = await parallel(thunks)
  const merged = results.filter(Boolean).flat()
  const seen = new Set()
  const deduped = []
  for (const f of merged) {
    const key = `${f.chunkId}|${f.severity}|${(f.title || '').toLowerCase().slice(0, 60)}`
    if (seen.has(key)) continue
    seen.add(key)
    deduped.push(f)
  }
  return deduped
}

// --- Phase 5: Execute waves serially; chunks within a wave run in parallel.
// The barrier between waves is intentional — later waves may depend on earlier
// ones, so each wave must fully complete before the next dispatches.
phase('Execute')
const execByChunk = new Map()
for (let w = 0; w < args.waves.length; w++) {
  const wave = args.waves[w]
  log(`Wave ${w + 1}/${args.waves.length}: ${wave.length} chunk(s) — ${wave.map((c) => c.id).join(', ')}`)
  const results = await parallel(wave.map((chunk) => () => executeChunk(chunk)))
  results.filter(Boolean).forEach((r) => execByChunk.set(r.chunkId, r))
}

// --- Phase 6: Review + blocker auto-fix loop (cap 2 iterations).
phase('Review')
let findings = await reviewChunks([...execByChunk.keys()])
let iteration = 0
const MAX_ITERS = 2
while (findings.some((f) => f.severity === 'blocker') && iteration < MAX_ITERS) {
  iteration++
  const blockerIds = [...new Set(findings.filter((f) => f.severity === 'blocker').map((f) => f.chunkId))]
  log(`Review iteration ${iteration}: ${blockerIds.length} chunk(s) with blockers — re-dispatching with reviewer feedback`)
  await parallel(
    blockerIds.map((id) => () => {
      const chunk = findChunk(id)
      const fb = findings
        .filter((f) => f.chunkId === id && f.severity === 'blocker')
        .map((f) => `- ${f.title}${f.detail ? ': ' + f.detail : ''}${f.file ? ' (' + f.file + ')' : ''}`)
        .join('\n')
      return executeChunk(chunk, `A reviewer flagged blocking issues with your earlier implementation:\n${fb}\nFix these specifically.`).then(
        (r) => execByChunk.set(r.chunkId, r),
      )
    }),
  )
  // Re-review ONLY the re-dispatched chunks; keep clean chunks' findings as-is.
  const reFindings = await reviewChunks(blockerIds)
  findings = findings.filter((f) => !blockerIds.includes(f.chunkId)).concat(reFindings)
}

const blockers = findings.filter((f) => f.severity === 'blocker')
const concerns = findings.filter((f) => f.severity === 'concern')
const nits = findings.filter((f) => f.severity === 'nit')
const filesChanged = [...new Set([...execByChunk.values()].flatMap((r) => (r.result && r.result.filesChanged) || []))]
const flaggedIds = new Set(findings.map((f) => f.chunkId))

return {
  iterations: iteration,
  hitReviewCap: blockers.length > 0,
  perChunk: [...execByChunk.values()].map((r) => ({
    chunkId: r.chunkId,
    ok: r.ok,
    attempts: r.attempts,
    model: r.model,
    summary: r.result ? r.result.summary : null,
    testsPassed: r.result ? r.result.testsPassed : undefined,
    blocker: r.ok ? undefined : r.blocker,
  })),
  filesChanged,
  clean: [...execByChunk.keys()].filter((id) => !flaggedIds.has(id)),
  unresolvedBlockers: blockers, // non-empty only if the cap was hit — surface to user
  concerns, // skill gates on these (address now / defer)
  nits,
}
