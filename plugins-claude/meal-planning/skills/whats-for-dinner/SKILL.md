---
name: whats-for-dinner
description: "Answer what to cook right now from the active meal plan. Use for single-meal questions — what should I make tonight, what's for dinner, what am I cooking, what's left this week, what needs using up. This is a lookup against an existing plan, not a planning session: it reads the active plan and answers from it, and offers to plan a new cycle only when none is active."
---

# whats-for-dinner

Answers "what am I cooking" by reading the active meal plan. **It plans nothing and
writes nothing.**

This skill exists because two questions look alike and cost wildly different
amounts. "What should I make tonight" is a lookup. Planning a cycle is a long
session that ends in a grocery order. Answering the first by starting the second is
the failure this split prevents — so keep it cheap and don't drift into planning.

## Where personalization lives

No recipes, no dietary facts, no household constants. All of it is in the knowledge
base. The skill carries method; the KB carries facts.

The contracts document's *Profile documents* index includes a Preferences
document. Read it — it governs tone as well as planning, and this skill's whole job
is a short spoken-aloud answer. Say things once; a caveat repeated after it's been
acknowledged is unwelcome.

**Never invent a constraint.** If something about tonight isn't in the plan or the
profile documents — whether there's time, whether a thaw happened — ask instead of
assuming. A guess stated as fact is the failure mode this chain is most prone to.

## Do this

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts. It gives the plan location, frontmatter, and section structure.
2. **Find the active plan.** Exactly one plan is `active`; anything `archived` is
   not current, whatever its dates say. Check that today falls inside its cycle
   window.
3. **Answer from the plan's own schedule.** The plan records each batch's cook date
   and the specific nights it covers — read them. Do **not** recompute the chain,
   and do not infer dates from night counts; the plan was written so a cold read
   wouldn't have to. Say which batch and which night you're reading.
4. **Read the cook log** before answering. It records what was actually cooked
   against what was scheduled, so a batch that slipped changes what tonight is.
   The schedule is the plan; the log is what happened.

Keep the answer short. This is a question asked while standing in the kitchen, not
a request for a briefing.

## What to surface without being asked

- **Anything with a short window.** If a batch is near the end of its cook-by
  window, lead with that — it's the one decision that gets expensive if deferred.
- **A timed carrier.** If the batch has one, say so up front, because it changes
  when cooking has to start. The recipe's step zero covers the rest.
- **An attached side**, if the batch has one.

## When there's no usable plan

If no plan is `active`, or the active plan's window has already passed, say so
plainly and **offer to run `/meal-planning:meal-plan`**. Wait for an answer.

Do not improvise a meal from the recipe collection, and do not quietly start
planning a cycle. An unplanned suggestion means shopping that didn't happen, so a
recipe picked at random is likely to be missing an ingredient — which is worse than
saying there's no plan.

## Staying in scope

- **Never write to the plan.** Not to mark a batch cooked, not to adjust an order.
  If the user says they cooked something or wants the plan changed, tell them what
  would need to change and let them direct it.
- **Never apply a dietary substitution.** Recipes in the KB are already correct.
- **Don't re-plan the cycle** because a batch looks unappealing tonight. Offer
  another batch already in the plan, or flex — the plan deliberately covers fewer
  nights than the cycle has days, and flex meals are a feature.
