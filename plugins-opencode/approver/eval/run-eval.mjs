// run-eval.mjs — replay eval/cases.json through the approver's real decision
// code (pre-filter, subagent rule, prompt layering, judge input, verdict
// parsing) and report agreement with the expected verdicts.
//
// Only one hop differs from production: the model call goes straight to the
// OpenAI-compatible endpoint named in your OpenCode config instead of through
// OpenCode's generate.text. That makes it fast (no session, no server) and lets
// you A/B judge models, variants and prompts. Needs node >= 23.
//
// Usage: approver-eval [--cases FILE] [--config FILE] [--model SPEC]
//        [--prompt-file FILE] [--samples N] [--temperature T] [--only id,id]
//        [--concurrency N] [--timeout-ms N] [--json] [--list] [--verbose]
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { parseArgs } from "node:util"

const here = import.meta.dirname
const core = await import(path.join(here, "../src/approver-core.ts"))

const { values: a } = parseArgs({
	options: {
		cases: { type: "string" },
		config: { type: "string" },
		model: { type: "string" },
		"prompt-file": { type: "string" },
		samples: { type: "string", default: "1" },
		temperature: { type: "string", default: "0" },
		only: { type: "string" },
		concurrency: { type: "string", default: "2" },
		"timeout-ms": { type: "string", default: "60000" },
		json: { type: "boolean", default: false },
		list: { type: "boolean", default: false },
		verbose: { type: "boolean", default: false },
		help: { type: "boolean", short: "h", default: false },
	},
})

if (a.help) {
	console.log(
		fs
			.readFileSync(import.meta.filename, "utf8")
			.split("\n")
			.slice(0, 12)
			.join("\n")
			.replace(/^\/\/ ?/gm, ""),
	)
	process.exit(0)
}

const die = (msg) => {
	console.error(`approver-eval: ${msg}`)
	process.exit(2)
}

// --- load config -------------------------------------------------------------------------

const readJsonc = (file) => {
	const text = fs
		.readFileSync(file, "utf8")
		.replace(/^\s*\/\/.*$/gm, "")
		.replace(/,(\s*[}\]])/g, "$1")
	return JSON.parse(text)
}

const configPath =
	a.config ??
	[process.env.OPENCODE_CONFIG, path.join(os.homedir(), ".config/opencode/opencode.json"), path.join(os.homedir(), ".config/opencode/opencode.jsonc")].find(
		(p) => p && fs.existsSync(p),
	)
if (!configPath) die("no OpenCode config found (use --config)")
const config = readJsonc(configPath)

const pluginEntry = (config.plugins ?? []).find((p) => typeof p === "object" && /approver/.test(p.package ?? ""))
const rawOptions = pluginEntry?.options ?? {}
const options = core.normalizeOptions({ ...rawOptions, timeoutMs: Number(a["timeout-ms"]) })

// --- resolve the judge model against the config's providers -----------------------------------

const providers = config.providers ?? {}
const listModels = async () => Object.entries(providers).flatMap(([providerID, p]) => Object.keys(p.models ?? {}).map((id) => ({ providerID, id })))

const spec = a.model ?? options.model
const ref = await core.resolveModel(spec, options.modelTiers, listModels)
if (!ref) die(`cannot resolve judge model "${spec}"`)
const provider = providers[ref.providerID]
const modelCfg = provider?.models?.[ref.id]
if (!provider || !modelCfg) die(`model ${core.modelLabel(ref)} is not defined under "providers" in ${configPath}`)
const baseURL = provider.settings?.baseURL
if (!baseURL) die(`provider ${ref.providerID} has no settings.baseURL`)
if (!/openai-compatible/.test(provider.package ?? "")) die(`provider ${ref.providerID} is not openai-compatible; approver-eval only speaks /chat/completions`)
const variantBody = ref.variant ? modelCfg.variants?.find((v) => v.id === ref.variant)?.body : undefined
if (ref.variant && !variantBody) die(`variant "${ref.variant}" is not defined on ${ref.providerID}/${ref.id}`)
const wireModel = modelCfg.modelID ?? ref.id
const headers = { "content-type": "application/json", ...(provider.settings?.apiKey ? { authorization: `Bearer ${provider.settings.apiKey}` } : {}) }
const temperature = Number(a.temperature)

// --- policy prompt --------------------------------------------------------------------------------

const prompt = a["prompt-file"]
	? { text: fs.readFileSync(a["prompt-file"], "utf8").trim(), source: `file:${a["prompt-file"]}` }
	: core.resolvePrompt({ directory: process.cwd(), optionPrompt: options.prompt })

// --- cases ------------------------------------------------------------------------------------------

const casesPath = a.cases ?? path.join(here, "cases.json")
let cases = JSON.parse(fs.readFileSync(casesPath, "utf8"))
if (a.only) {
	const want = new Set(a.only.split(","))
	cases = cases.filter((c) => want.has(c.id))
}
if (a.list) {
	for (const c of cases) console.log(`${c.id.padEnd(30)} expect=${c.expect}  ${c.desc ?? ""}`)
	process.exit(0)
}
if (!cases.length) die("no cases selected")

// --- judge --------------------------------------------------------------------------------------------

let judgeCalls = 0
const judge = async ({ text }) => {
	judgeCalls++
	const res = await fetch(`${baseURL.replace(/\/$/, "")}/chat/completions`, {
		method: "POST",
		headers,
		body: JSON.stringify({
			model: wireModel,
			messages: [{ role: "user", content: `${text}\n\n${core.TEXT_VERDICT_INSTRUCTIONS}` }],
			temperature,
			max_tokens: 3000,
			...(variantBody ?? {}),
		}),
	})
	if (!res.ok) throw new Error(`judge HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`)
	const body = await res.json()
	const content = body.choices?.[0]?.message?.content ?? ""
	const v = core.parseTextVerdict(content)
	return { approve: v.approve, reason: v.reason, model: core.modelLabel(ref) }
}

const runOne = async (c) => {
	// Per-case flag: a shared counter would be bumped by concurrent cases.
	let judgedHere = false
	const event = { sessionID: "eval", agent: c.agent, action: c.action, resources: c.resources ?? [], effect: c.effect ?? "allow" }
	const deps = {
		options,
		allow: core.compilePatterns(options.allow),
		ask: core.compilePatterns(options.ask),
		prompt,
		judge: (args) => {
			judgedHere = true
			return judge(args)
		},
		userMessages: async () => (c.userMessages ?? []).slice(-options.messageWindow).map((m) => core.truncate(m, options.messageChars)),
		isSubagent: async () => Boolean(c.subagent),
	}
	const t0 = performance.now()
	const out = await core.decide(event, deps)
	const ms = Math.round(performance.now() - t0)
	return { effect: out.effect, source: out.entry.source, reason: out.entry.reason, ms, judged: judgedHere }
}

// --- run (small pool) -------------------------------------------------------------------------------------

const samples = Math.max(1, Number(a.samples) || 1)
const jobs = cases.flatMap((c) => Array.from({ length: samples }, (_, i) => ({ c, i })))
const results = new Map(cases.map((c) => [c.id, []]))
let next = 0
const worker = async () => {
	while (next < jobs.length) {
		const { c } = jobs[next++]
		results.get(c.id).push(await runOne(c))
	}
}
await Promise.all(Array.from({ length: Math.max(1, Number(a.concurrency) || 1) }, worker))

// --- report ---------------------------------------------------------------------------------------------------

const pct = (xs, p) => (xs.length ? [...xs].sort((x, y) => x - y)[Math.min(xs.length - 1, Math.floor((p / 100) * xs.length))] : 0)
const rows = cases.map((c) => {
	const rs = results.get(c.id)
	const good = rs.filter((r) => r.effect === c.expect && (!c.expectSource || r.source === c.expectSource))
	const judgedMs = rs.filter((r) => r.judged).map((r) => r.ms)
	const noModelOk = c.expectSource?.startsWith("prefilter") || c.expectSource === "subagent" ? rs.every((r) => !r.judged) : true
	const ok = good.length === rs.length && noModelOk
	return {
		id: c.id,
		expect: c.expect,
		soft: Boolean(c.soft),
		pass: ok,
		agree: `${good.length}/${rs.length}`,
		got: [...new Set(rs.map((r) => `${r.effect}(${r.source})`))].join(","),
		judgeMs: judgedMs.length ? pct(judgedMs, 50) : null,
		reason: (rs.find((r) => r.effect !== c.expect)?.reason ?? rs[0]?.reason ?? "").slice(0, 90),
	}
})

const allJudged = [...results.values()]
	.flat()
	.filter((r) => r.judged)
	.map((r) => r.ms)
const failed = rows.filter((r) => !r.pass && !r.soft)

if (a.json) {
	console.log(
		JSON.stringify(
			{ model: core.modelLabel(ref), prompt: prompt.source, samples, temperature, judgeCalls, rows, p50: pct(allJudged, 50), p95: pct(allJudged, 95) },
			null,
			2,
		),
	)
} else {
	console.log(`judge: ${core.modelLabel(ref)}  prompt: ${prompt.source}  samples/case: ${samples}  temperature: ${temperature}`)
	console.log("")
	for (const r of rows) {
		const mark = r.pass ? "✓" : r.soft ? "~" : "✗"
		const line = `${mark} ${r.id.padEnd(30)} want=${r.expect.padEnd(5)} ${r.agree.padEnd(5)} ${r.got.padEnd(30)} ${r.judgeMs == null ? "      -" : `${String(r.judgeMs).padStart(5)}ms`}`
		console.log(a.verbose || !r.pass ? `${line}\n    ${r.reason}` : line)
	}
	console.log("")
	console.log(
		`cases: ${rows.length - failed.length}/${rows.length} agree  judge calls: ${judgeCalls}  judge p50: ${pct(allJudged, 50)}ms  p95: ${pct(allJudged, 95)}ms`,
	)
}
process.exit(failed.length ? 1 : 0)
