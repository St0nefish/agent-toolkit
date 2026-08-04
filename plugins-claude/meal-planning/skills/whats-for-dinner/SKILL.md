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
   not current. Check that today falls inside its cycle window — the window is the
   only date the plan carries.
3. **Work out which rough week the cycle is in** — today against `cycle_start`.
   That is the only date arithmetic this skill does, and it stops there. The plan
   carries an order and a rough week, never cook dates or named nights.
4. **List that week's batches in chain order and let the user say which.** Give
   them with whatever makes the choice easy — the binding ingredient, a thaw lead,
   a timed carrier — and stop there. If the week is nearly done or the list is
   thin, include the neighbouring week's batches too.
5. **If the plan carries a record of what's been cooked, use it** to lead with the
   likeliest batch — while still showing the rest of the week, because the record
   lags reality and this skill never writes to it. Whether such a record exists at
   all is a preference; see below.

Keep the answer short. This is a question asked while standing in the kitchen, not
a request for a briefing.

## Tracking is a preference

**Do not enforce a position in either direction.** Whether the household tracks
what actually got cooked lives in Preferences, and it changes what this skill can
lean on:

- **Tracking on** — the plan carries a record. Read it, lead with what it implies,
  and stay correctable.
- **Tracking off** — there is nothing to read. List the week's batches and let the
  user pick.

**Absent a stated preference, assume nothing is tracked.** Listing the week works
either way; inferring a position from a record that doesn't exist does not.

Either way, **never assert what the user cooked or ate**, and don't interrogate
them to reconstruct it. They can see the fridge in one glance and will say. If they
contradict the plan or the record, they're right.

## What to surface without being asked

- **Anything with a short window.** If a later batch is pinned by something that's
  about to turn, say so — that's a reason to reorder, and reordering is routine,
  not a re-plan. Name the binding ingredient, not a deadline date.
- **A timed carrier.** If the batch has one, say so up front, because it changes
  when cooking has to start. The recipe's step zero covers the rest.
- **A thaw lead.** If a batch coming up this week needs its protein moved to the
  fridge ~48 hours ahead, that has to be said tonight, not the night it's cooked.
- **An attached side**, if the batch has one.

## When there's no usable plan

If no plan is `active`, or the active plan's window has already passed, say so
plainly and **offer to run `/meal-planning:meal-plan`**. Wait for an answer.

Do not improvise a meal from the recipe collection, and do not quietly start
planning a cycle. An unplanned suggestion means shopping that didn't happen, so a
recipe picked at random is likely to be missing an ingredient — which is worse than
saying there's no plan.

## Staying in scope

- **Never write to the plan.** Not to record a batch as cooked, not to adjust the
  order. If the user says they cooked something or wants the order changed, tell
  them what would need to change and let them direct it.
- **Never argue about what the user has eaten or cooked.** They know; you don't.
  If they say a batch is done, it's done — answer from what's left. The plan is a
  proposed order, not a record of events.
- **Never apply a dietary substitution.** Recipes in the KB are already correct.
- **Don't re-plan the cycle** because a batch looks unappealing tonight. Offer
  another batch already in the plan, or flex — the plan deliberately covers fewer
  nights than the cycle has days, and flex meals are a feature.
