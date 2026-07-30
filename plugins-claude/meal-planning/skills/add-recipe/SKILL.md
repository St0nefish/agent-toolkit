---
name: add-recipe
description: "Author a new recipe into the cooking knowledge base, or retrofit an existing one to the meal-planning schema. Use when the user wants to add, import, or write up a recipe; when a meal-planning conversation lands on a dish the KB doesn't have; or when asked to retrofit, backfill, or fix a recipe's frontmatter or shopping list. Applies the household dietary profile and substitutions at authoring time, writes planning metadata, and produces a canonical shopping list that joins to the store product mapping."
---

# add-recipe

Authors recipes into the knowledge base so `meal-plan` can schedule them and
`grocery-cart` can source them. This is the keystone skill: the dietary profile
and its substitutions are resolved **here, once, at authoring time**, so nothing
downstream has to know about them.

## Where personalization lives

This skill contains **no** dietary facts, no store name, and no pantry contents —
by design. All of that lives in the knowledge base, reachable over the KB MCP
server. The skill carries method; the KB carries facts. Never inline a
restriction, a brand, or a product name into this file.

## Preflight — resolve the profile documents

Do not work from memory, and do not proceed on a partial read.

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts, recipe planning frontmatter, or shopping line format.
2. **Read it.** Its *Profile documents* table indexes the other three roles —
   restrictions, staples, and product mapping — and names the active store.
3. **Read all three in full** before writing anything.

The contracts document is the only thing this skill locates by search, and it is
authoritative over this file wherever the two disagree. Everything else is
reached through its index, so the KB can move or re-partition its kitchen corpus
without touching this skill.

Failure modes, in order of likelihood:

- **Several plausible contracts documents** — ask which is authoritative. Guessing
  wrong corrupts every recipe written afterward.
- **No *Profile documents* index in the contracts doc** — fall back to searching
  for each role directly (dietary restrictions and substitutions; pantry staples
  and do-not-stock; canonical grocery vocabulary mapped to store products), and
  report that the index is missing so it can be added.
- **A role can't be resolved** — stop. Say which role is unresolved and what it
  was needed for, and offer to create it. Never substitute your own defaults for a
  missing restrictions or staples document: a recipe authored against assumed
  restrictions is worse than no recipe, because it looks finished.

Resolve once per session and reuse the paths. Don't re-search per recipe.

## Workflow

### 1. Get the recipe

Source can be the user's own notes, a URL, a photo, or research. If researching,
prefer one good source over a synthesis of several — recipes assembled from
fragments carry contradictory ratios.

### 2. Conform it to the profile — silently

This is the step that makes everything downstream simple. Apply the restrictions
document and the do-not-stock section of the staples document, then rewrite the
recipe so it is **already correct**.

How to apply them:

- Restrictions are constraints, not preferences. Never frame an excluded
  ingredient as "optional", never list it as a garnish, never mention it as
  something the user could add back.
- Substitute at the level of **flavour role**, not ingredient identity — the
  substitution tables in the restrictions doc exist for this. Match what the
  original ingredient was doing in the dish.
- Prefer subtraction when no substitute does the job. A dish is better without a
  component than with a bad stand-in for it.
- Do **not** annotate swaps in the finished document unless the swap changes
  technique or timing. The recipe should read as though it were always written
  this way.
- If the restrictions can't be satisfied without changing what the dish *is*,
  say so plainly and stop. Offer the nearest dish that does work. Shipping a
  hollowed-out recipe wastes a cook session to discover it.

### 3. Write the planning frontmatter

The contracts document owns the field list, the value vocabularies, and the
derived formulas — including how usable nights are capped, how carrier slack is
computed, and what makes a recipe non-scalable. Follow it; do not restate it
here and do not recompute it from memory.

What the contracts can't tell you, and you have to get right:

- **Ask for durable facts, not derived ones.** Ask how many pieces make a meal;
  the nights follow from that and from pack size. Asking "how many nights?" pushes
  arithmetic onto the user and produces a number that stops being true when the
  store changes pack size.
- **Untested recipes:** if the user hasn't cooked it, mark it untested and leave
  the rating absent. Don't ask for yield-in-nights on something unproven — it's
  unknowable and asking wastes their time.
- **Estimate openly.** Where a value is a guess (prep and cook minutes usually
  are, until cooked once), use your best estimate and list it in the closing
  report as estimated. Silent guesses become facts nobody audits.

### 4. Step zero for timed carriers

If the recipe has a timed carrier, the method **must open with starting the
carrier** — a numbered step zero, before prep. Not a serving note, not a tip at
the bottom.

This is not a style preference. Improvised cooking with no defined start is a
known, repeating failure mode; the written anchor is the fix.

### 5. Generate the shopping list

The line format and the sourcing classes are defined in the contracts document.
Two rules govern the work:

**Purchase units only.** The cooking-unit ingredient list and the purchase-unit
shopping list are separate representations of the same recipe, and they stay
separate. Never merge them, and never make a downstream skill convert
tablespoons into bottles.

**Every canonical name must join to the product mapping.** For any that doesn't:

1. Check the store for the product to confirm it exists and capture its exact
   product string. Use the browser or whatever store connector is available.
2. If it genuinely isn't carried, classify it as home-sourced with a note. That's
   a real finding worth surfacing, not a gap to paper over — it tells the user a
   planned meal has an unsourceable ingredient before they plan around it.
3. Collect every new canonical and report it at the end so the mapping document
   can be updated. The mapping is the join key for the whole system; letting it
   drift silently breaks cart building later.

### 6. Write to the KB

Path convention: the recipes directory under the kitchen area of the KB, one
document per recipe, slug-named.

- Frontmatter needs the KB's own required fields. `type` is a closed vocabulary —
  use the closest allowed value and carry the enumerable marker as a **tag**
  instead. Check the KB's schema rather than assuming a `recipe` type exists.
- Tags carry protein, cuisine, method, and equipment so `meal-plan` can filter at
  search time instead of loading every document. Tag equipment only when it's
  actually used, and don't use the domain name as a tag.
- **Duplicate detection will refuse the create** when the dish is discussed
  anywhere else in the KB — a cuisine guide mentioning the dish is enough. This is
  expected, not an error. Confirm no actual recipe document exists, then retry
  forcing a new document.

## Shopping-list-only entries

Some dishes are cooked constantly and deliberately undocumented. For these, mark
the recipe as needing no method, write the planning block and shopping list, and
skip the method entirely. If the carrier is timed, the step-zero instruction
still goes in — that's often the only reason the entry exists at all.

## Retrofit mode

Same skill, applied to a recipe already in the KB. Skip step 2 — those recipes
already went through the user. Otherwise identical: add the planning block,
convert the shopping list to canonical format, fix the tags.

Watch for restriction violations that predate the schema. Retrofits routinely
surface excluded ingredients and do-not-stock items that were written in before
the profile was documented. Fix them in place while you're there, and report what
you changed — an unannounced edit to a recipe the user has cooked before is
confusing at the stove.

## What to report at the end

- New canonical names needing product-mapping entries
- Ingredients the store doesn't carry, and which meals they block
- Home-sourced items and their fallback shape
- Fields you estimated rather than knew, so the user can correct them
- For retrofits: restriction violations found and fixed
