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

## Do this

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts. It gives the plan location, frontmatter, and section structure.
2. **Find the active plan.** Exactly one plan should be `active`. Check that today
   falls inside its cycle window.
3. **Answer from the plan.** Prefer the plan's own batch ordering — it is sequenced
   by perishability, so the next unmade batch is usually the right answer. Say which
   batch, and why it's next.

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
