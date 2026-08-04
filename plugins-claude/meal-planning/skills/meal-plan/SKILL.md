---
name: meal-plan
description: "Plan a cooking cycle — converge conversationally on a set of batches, then write a complete plan document. Use when the user wants to plan a cooking cycle, start a grocery cycle, or rework an existing cycle plan. This is a periodic planning session covering weeks, NOT a single-meal question: 'what should I make tonight' is answered from the existing plan and must not trigger a new planning run. Reads recipes and household planning rules from the knowledge base, orders batches into a serial chain, and hands off to grocery-cart for sourcing."
---

# meal-plan

Converges on a set of batches for a cooking cycle and writes a plan document that
`/meal-planning:grocery-cart` sources from and that the cooking sessions run from.

Workflow position: **meal-plan** → `/meal-planning:add-recipe` (only if the
conversation wants something the KB doesn't have) → `/meal-planning:grocery-cart`.

## Where personalization lives

This skill contains no recipes, no dietary facts, no store name, and no household
constants — not even the cooked-nights target. All of that lives in the knowledge
base. The skill carries method; the KB carries facts.

**A preference hardcoded here cannot be edited by the person whose preference it
is.** If you are about to write a number, a cadence, or a habit into this file, it
belongs in the Preferences document instead.

## Preflight

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts, recipe planning frontmatter, or shopping line format. It is the
   single entry point and is authoritative over this file.
2. **Read every document in its *Profile documents* index** — Preferences,
   Restrictions, Staples, Product mapping. Not a skim, and not just the ones that
   look relevant.

   **Preferences is authoritative over anything this skill would otherwise
   default to** — cadence, batch sizing, freezing, cycle rhythm, ranking, tone.
   Where it and your instincts disagree, it wins.
3. **Enumerate the recipe collection** by searching for the `recipe` **tag**, not
   by `type` — `type` is a closed vocabulary that rejects `recipe`.

   **Enumeration is unreliable and you must account for it.** KB search is
   relevance-ranked and returns chunks rather than documents, with a result cap and
   no total count, so one query silently comes back short — in practice it has
   dropped the single most-cooked dish in the collection. Run several queries with
   differing wording, deduplicate by document path, and **state how many distinct
   recipes you found.** A stated count lets the user notice a shortfall; a silent
   one means a recipe was never a candidate and nobody knows.

If the contracts document can't be resolved, or its index is missing, stop and say
so rather than planning against assumed rules.

## Never invent a constraint

This is the most damaging way this skill fails, because it is silent and it
contaminates the KB.

A guess and a recorded preference look identical once written in prose. An
invented constraint gets recorded in the plan as design rationale, carried forward
into profile documents as though it were stated, and survives review because it
sounds reasonable — while quietly producing a worse schedule.

- **Ask when the KB doesn't answer a scheduling question.** One question is cheap.
- **Any assumption about work, sleep, travel, or availability is fabricated** —
  none of that is in the KB unless Preferences says it. Do not reason from what is
  typical.
- **When a constraint is doing real work in the plan, cite where it came from.**
  If it can't be cited, it is a question, not a constraint.
- **Never write an unverified assumption into the plan document.** Plans are inputs
  to the next run; a guess recorded there is laundered into fact.

## Run it as a conversation, not a form

The user talks about what they want; you converge. Don't open with an
interrogation, don't present a numbered questionnaire, and don't demand a cycle
length before offering anything. Propose, react, adjust.

Keep the prose lean and say things once — Preferences covers tone, and repeating a
caveat that was already acknowledged is actively unwelcome.

## Order the chain, don't date it

Batches run **serially** — cook one, eat it until it's gone, then cook the next.
The output is an **order**, not a calendar. The contracts document owns the
computation and Preferences §1 owns the rule; both are authoritative over this
file.

**Do not assign cook dates or named nights to batches, ever.** A batch is cooked
when the one before it runs out, which is not a date anyone commits to in advance.
Real life reorders the chain routinely — that is what flex nights are for, and a
plan that dates its batches turns an ordinary slip into a plan that reads as
broken. It also invites arguing with the user about what they ate on a given day,
which you have no way to know and no business asserting.

What the plan carries instead:

- **A rank per batch** — first, second, third. This is the load-bearing part: it
  puts perishable batches ahead of durable ones.
- **A rough week**, if the cycle spans more than one. Week 1 / week 2 is the
  finest date resolution wanted. Never a day.
- **Relative deadlines where an ingredient forces one** — "cook this one early,
  the mushrooms are what binds it." That is a real constraint and belongs in the
  plan; a calendar date is not.

And in particular:

- **Size the cycle, don't schedule it.** `usable_nights` still decides how many
  batches a cycle needs and whether the coverage target is met — it just never
  resolves to named nights. The cycle length itself comes from Preferences; don't
  assume a fortnight.
- **Derive each batch's window from its ingredients**, per the contracts: the
  minimum across the `required` and `home` lines, where anything freezable or
  shelf-stable doesn't bind. A recipe is not one ingredient — a braise whose beef
  freezes fine is still pinned by the fresh thing in it.
- **Check that derived window against the batch's position in the chain**, not
  against the cycle start — that check is the whole reason the ordering exists. A
  batch placed in week 2 needs ingredients that survive into week 2.
- **Name the binding ingredient** next to the rank. "Second — the mushrooms are
  what binds it" tells the user what to substitute if the slot is inconvenient,
  and makes mid-cycle reordering cheap when something starts to turn.
- **State thaw leads relatively** — "move it to the fridge ~48 hours before you
  cook it" — never as a calendar date. Permission to freeze is not a plan step;
  the lead is.
- **Run the contracts' validity checks before showing anything.** Never three cook
  sessions back to back still holds; without dates it constrains how many batches
  the cycle carries, not a calendar.
- **Report `cook_sessions`.** It is the efficiency metric that matters under serial
  consumption; cooked nights alone will make a bad plan look fine.

**Reordering mid-cycle is not a re-plan.** If the user says a batch moved, or an
ingredient is turning, swap the ranks and move on. Don't rebuild the cycle and
don't ask for preconditions first.

## Selection

Preferences owns the targets, the ranking rules, and the cadence. Do not restate
them here and do not substitute your own. What this skill has to get right:

- **Don't let untested recipes anchor the plan.** Absent `tested` means untested.
  Trying something new is fine as a surfaced, deliberate choice — but its yield is
  a guess, so it shouldn't be the batch the cycle leans on.
- **Attach sides, don't schedule them.** A `role: side` recipe is never a batch;
  check whether a chosen main needs one.
- **Flag timed carriers**, so the cooking session knows a second timed process is
  in play.
- **When the user's chosen batches overrun the target**, follow the contracts: trim
  nights within a batch before dropping a batch they asked for, least-certain yield
  first. If trimming can't close the gap, ask rather than deciding.

## Branching to add-recipe

If the conversation lands on a dish the KB doesn't have, invoke
`/meal-planning:add-recipe`, let it finish, then continue with the new recipe
available. Don't inline a half-specified recipe into the plan — the plan has no
place to carry a method, and the cart can't source a shopping list that was never
written.

## Output

**Write the plan to the KB.** The contracts document defines the path, the
frontmatter, and the sections. Follow it exactly — it carries required fields that
the server rejects the document without.

- **Close the previous cycle first.** Archive the outgoing plan and record its
  outcome *before* the new one goes active. Two plans reading `active` breaks
  `/meal-planning:whats-for-dinner`, which resolves "tonight" by finding the
  active plan.
- **Record thaw leads, not just thaw facts.** A batch that needs its protein moved
  to the fridge needs the lead time — "~48 hours before cooking" — attached to the
  batch, so a cold read knows when to act without a date to miss.
- **Whether the plan records what was actually cooked is a preference, not a rule
  this skill owns.** Some households want a cook log and the history it gives;
  others find being asked to account for what they ate actively unwelcome. Read
  Preferences and do what it says — emit a log in the shape it asks for, or emit
  none. **Absent a stated preference, don't emit one and don't ask for one**: a
  plan with no log still works, whereas a log nobody maintains makes every later
  read confidently wrong about what happened.

**Complete serialization is load-bearing.** A cold read on a different device with
zero conversation context is the *normal* case. Everything the cart step and the
cooking sessions need must be in the document. If a decision exists only in this
conversation, it is lost.

Record the store the plan was built against.

## Invariant — restrictions were already applied

Recipes in the KB are already correct: dietary restrictions and substitutions were
resolved once, upstream, in `/meal-planning:add-recipe`. This skill must never
apply a substitution, re-check an ingredient against a restriction, or annotate a
recipe as adapted. If you find yourself reasoning about whether an ingredient is
allowed, something upstream failed — say so rather than patching it here, because a
fix applied at plan time never reaches the recipe the user cooks from.
