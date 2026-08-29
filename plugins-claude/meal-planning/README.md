# meal-planning

Recipe authoring, cycle planning, grocery cart building, and dinner lookup — four
skills that share one schema contract stored in a knowledge base.

| Skill | Does |
|---|---|
| `add-recipe` | Authors a recipe into the KB, or retrofits an existing one to the schema. Resolves dietary restrictions and substitutions **once**, here. |
| `meal-plan` | Converges conversationally on a set of batches for a cycle, ordered by perishability. Writes the plan to the KB. |
| `grocery-cart` | Reads the active plan, resolves canonical names to store products, drives a logged-in browser session to fill a cart. Never places the order. |
| `whats-for-dinner` | Answers single-meal questions from the active plan. Reads only — plans nothing, writes nothing. |

Workflow: `meal-plan` → `add-recipe` (only if the plan wants something new) →
`grocery-cart`.

`whats-for-dinner` sits outside that chain. It's the cheap lookup — "what should I
make tonight" — kept separate so a one-meal question can't trigger a full planning
session, which is what a single over-broad description would have caused.

## The personalization seam

**These skills carry no personal data.** No dietary facts, no retailer or vendor
names, no product names, no pantry contents, no recipes, no target numbers. This
repository is public; all of that lives in a knowledge base reached over an MCP
server. Method lives in the skill, facts live in the KB.

Instacart is the one named service, and it is a hard dependency — `grocery-cart`
exists to automate it. Naming the platform is scope, not disclosure; the
**retailer** behind it is a household fact and lives only in the KB.

`allowed-tools` is deliberately left unset on all four skills, unlike most skills
in this repo. These depend on MCP tools whose names vary with how the user has
registered their KB server, and an `allowed-tools` list that omitted them would
block the dependency the whole design rests on.

The skills locate **one** document by relevance search — the meal-planning
contracts doc — and reach everything else through the *Profile documents* index
inside it:

| Role | Carries |
|---|---|
| Contracts | Schema, line formats, derived formulas, the batch ordering chain, plan-doc structure. Authoritative over the skills. |
| Preferences | Household constants — cadence, cycle length, batch sizing, freezing, cycle rhythm, tone. Authoritative over any skill default. |
| Restrictions | Hard exclusions and substitutions, applied at authoring time only |
| Staples | What's stocked, home-sourced, and never stocked |
| Product mapping | Canonical vocabulary → store products; the cart join key |

Consequences worth knowing before editing:

- **The contracts document wins.** Where a skill and the contracts disagree, the
  contracts are right and the skill needs updating.
- **Two query modes, and mixing them up is the recurring bug.** A search *with* a
  query is relevance-ranked and returns scored chunks — right for the one
  find-by-meaning the chain does, resolving the contracts doc. A search with a path
  prefix and **no** query enumerates: one row per document, stable order, exact
  total, explicit more-results flag. Anything needing a *complete* set — every
  recipe, the active plan, retrofit candidates — uses the second, filtered on
  frontmatter. Using relevance for a complete set is how a plan silently gets built
  from three-quarters of the collection.
- **Frontmatter rules cascade per directory** and are validated against the
  destination, so ask the server for a directory's schema before writing there. The
  recipe collection's own rules are what make `type: recipe` the enumerable marker
  and keep protein, cuisine, and method in typed `planning` fields rather than in
  tags.
- **Plans carry an order, not a calendar.** Batches are ranked and given a rough
  week at most — never a cook date, never named nights. Real life reorders the
  chain constantly, and a dated plan turns an ordinary slip into a plan that reads
  as broken and an agent that argues with the user about what they ate. Cycle
  length comes from Preferences.
- **Whether anything tracks what was actually cooked is a preference.** The skills
  work with a cook log or without one and enforce neither; a household that wants
  the history says so in Preferences, and one that finds the bookkeeping unwelcome
  says nothing. Absent a stated preference the skills assume no tracking, because
  listing a week's batches works either way while inferring a position from a
  record nobody maintains does not.
- **A preference hardcoded in a skill can't be edited by the person whose
  preference it is.** Anything that looks like a household constant — a target, a
  cadence, a sizing rule — belongs in the Preferences document, not in a skill file.
- **Restrictions are resolved upstream, once.** Only `add-recipe` applies
  substitutions. If `meal-plan` or `grocery-cart` is reasoning about whether an
  ingredient is allowed, something upstream failed.
- **Moving the KB corpus** — a dedicated instance, a re-partitioned domain, extra
  stores — means editing the index table in the contracts doc. The skills don't
  change.

## Install

**Claude Code:**

```bash
claude plugin marketplace add St0nefish/agent-toolkit
claude plugin install meal-planning@agent-toolkit
```

**Claude Desktop (Cowork):** Cowork tab → *Customize* → *Plugins* → *Personal
plugins* → **+** → *Add from a repository* → the repo URL. Cowork clones from the
default branch server-side, so changes must be merged to `master` before they
appear, and the marketplace may need a refresh.

Both stores are needed and they do not sync — Claude Code reads the repo locally,
Cowork loads from the claude.ai account.

`grocery-cart` needs browser control, so it runs from Desktop or Claude Code, not
from mobile.

> **Unverified:** whether plugin-provided skills reach the claude.ai mobile app.
> Plugins install to the account rather than to a device, so they may — but this
> hasn't been confirmed. If they don't, a zip upload of the individual skill is the
> known route to mobile, at the cost of maintaining a second copy.

## Operational notes

- **KB duplicate detection refuses creates** when a dish is discussed anywhere in
  the corpus — a cuisine guide mentioning it is enough. Expected, not an error:
  confirm no recipe document exists, then retry forcing a new document.
- **`get_document` has timed out in Desktop** where it worked in Claude Code,
  likely payload size through the HTTP wrapper. A client restart cleared it.
- `grocery-cart` keeps its browser-automation findings in
  `skills/grocery-cart/references/instacart-automation.md` — read it before
  driving the store, and update it when the site changes.
