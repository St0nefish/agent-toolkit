---
name: meal-plan
description: "Plan a cooking cycle — converge conversationally on a set of batches, then emit a complete plan document. Use when the user wants to plan a cooking cycle, start a grocery cycle, or rework an existing cycle plan. This is a periodic planning session covering weeks, NOT a single-meal question: 'what should I make tonight' is answered from the existing plan and must not trigger a new planning run. Reads recipes and household planning rules from the knowledge base, sequences batches by perishability, and hands off to grocery-cart for sourcing."
---

# meal-plan

Converges on a set of batches for a cooking cycle and emits a plan document that
`grocery-cart` can source from and that the user can cook from on another device.

Workflow position: **meal-plan** → `/meal-planning:add-recipe` (only if the
conversation wants something the KB doesn't have) → `/meal-planning:grocery-cart`.

## Where personalization lives

This skill contains no recipes, no dietary facts, no store name, and no target
numbers. All of that lives in the knowledge base. The skill carries method; the KB
carries facts. Never inline a recipe name, a brand, or a household constant here.

## Preflight

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts, recipe planning frontmatter, or shopping line format. It is the
   single entry point and is authoritative over this file wherever they disagree.
2. **Follow its *Profile documents* index** to the staples and product-mapping
   documents. Read them.
3. **Enumerate the recipe collection** by searching for the `recipe` **tag**, not
   by `type` — `type` is a closed vocabulary that rejects `recipe`. Read the
   planning frontmatter of each candidate; you don't need full methods to plan.

   **Enumeration is not reliable yet, and you must account for it.** KB search is
   relevance-ranked and returns chunks rather than documents, with a result cap and
   no total count — so a single tag query can silently come back short, and one
   recipe can consume several result slots. Run more than one query with differing
   wording, deduplicate by document path, and **tell the user how many distinct
   recipes you found.** A stated count lets them notice an obvious shortfall; a
   silent one means a recipe was never a candidate and nobody knows.

If the contracts document can't be resolved, or its index is missing, stop and say
so. Do not plan against assumed rules — see the fallback in `add-recipe`.

## Run it as a conversation, not a form

The user talks about what they want; you converge. Don't open with an
interrogation, don't present a numbered questionnaire, and don't demand a cycle
length before offering anything. Propose, react, adjust.

## Selection rules

The contracts document owns the numbers — the cooked-nights target, the fridge-life
cap, the slack thresholds. Follow them; don't restate or recompute them here, and
don't substitute your own defaults. What follows is the judgment that surrounds
them, including several rules that run **against** default model behaviour:

- **Plan for fewer cooked nights than the cycle has days.** Flex meals absorb the
  remainder by design, and that's a feature, not a gap to close. Under-planning is
  cheap — a gap gets filled by something the user would happily eat. Over-planning
  is expensive — perishables bought for a dinner that never got cooked rot. The
  contracts document gives the actual target. Round nights **up** and bias toward
  fewer batches.
- **Repetition is a feature. Do not inject variety.** Do not decay ratings by
  recency, do not penalise cooking the same thing twice in a cycle, do not
  "balance" cuisines or proteins. A plan that is three batches of favourites is a
  good plan. This is the rule most likely to be violated by reflex — variety feels
  like good planning and here it is not.
- **Sequence ascending by `cook_by_days`.** Week one burns the perishables, later
  weeks run on freezer and shelf-stable stock. This ordering is what lets a single
  grocery order cover a long cycle, so it is not cosmetic.
- **Buy to the meal count.** `portions_per_meal` is the durable fact; nights fall
  out of pack size. The plan tells the cart how much to buy — never infer the
  quantity from a recipe pretending to know pack sizes.
- **Don't let untested recipes anchor the plan.** A recipe the user has never
  cooked has guessed yield and unproven results. Trying something new is a fine
  deliberate choice — surface it as one, rather than quietly seating it as a
  load-bearing batch.
- **Attach sides, don't schedule them.** Recipes marked `role: side` are never
  scheduled alone; attach them to a main. This is what makes protein-only recipes
  into complete meals, so check whether a chosen main needs one.
- **Flag timed carriers.** Mark batches whose recipe has a timed carrier, so the
  cooking session knows a second timed process is in play.

## Branching to add-recipe

If the conversation lands on a dish the KB doesn't have, invoke
`/meal-planning:add-recipe`, let
it finish, then continue planning with the new recipe available. Don't inline a
half-specified recipe into the plan — the plan doc has no place to carry a method,
and the cart can't source a shopping list that was never written.

## Output

**Write the plan to the KB.** The contracts document defines the path, the
frontmatter, and the sections; follow it. Set the new plan `active`, and mark any
previously active plan whose window has passed as complete — exactly one plan is
active at a time, because `whats-for-dinner` resolves "tonight" by reading it.

**Complete serialization is load-bearing.** A cold read on a different device with
zero conversation context is the *normal* case, not the edge case. Everything the
cart step and the cooking sessions need must be in the document. If a decision
only exists in this conversation, it is lost.

Record the store the plan was built against, so a later store change doesn't
silently invalidate it.

## Invariant — restrictions were already applied

Recipes in the KB are already correct: dietary restrictions and substitutions were
resolved once, upstream, in `add-recipe`. This skill must never apply a
substitution, never re-check an ingredient against a restriction, and never
annotate a recipe as adapted. If you find yourself reasoning about whether an
ingredient is allowed, something upstream failed — say so rather than patching it
here, because a fix applied at plan time doesn't reach the recipe the user cooks
from.
