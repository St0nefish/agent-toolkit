---
name: grocery-cart
description: "Build a grocery cart from the active meal plan by driving a logged-in Instacart session in the browser. Use when the user has a plan and wants the shopping done, asks to build or fill a cart, or wants to order groceries for a planned cycle. Resolves canonical shopping names to store products, runs the pantry top-off prompts, resolves and records new product mappings, surfaces items that must be sourced elsewhere, and stops at checkout — it never places the order."
---

# grocery-cart

Reads the active plan, resolves its shopping lines to store products, and adds
them to a cart in a logged-in browser session.

**It never places the order.** The skill ends by handing a verified cart back for
checkout. This is not a hedge to relax once the cart looks complete — the user
tops off with their own items and reviews substitutions before paying, every time.

## Where personalization lives

This skill contains no retailer name, no vendor names, no product names, and no
pantry contents. All of that lives in the knowledge base. The skill carries method;
the KB carries facts.

Instacart is named and is a hard dependency — it is the platform this skill
automates, not a household fact. The **retailer** behind it is a household fact and
stays in the KB.

## Preflight

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts or shopping line format. Authoritative over this file.
2. **Read every document in its *Profile documents* index** — Preferences,
   Restrictions, Staples, Product mapping. Preferences is authoritative over any
   default this skill would otherwise apply.
3. **Read the active plan.** Find it by scoping a search to the plans directory
   with a path prefix, **no query**, and a filter of `status: active` — not by
   relevance. Exactly one plan is `active`. It is a complete
   serialization by contract, so work from it rather than from any planning
   conversation, which may not exist in this session. If no plan is active, say so
   and offer to run `/meal-planning:meal-plan`; do not assemble a cart from scratch.
4. **Before driving the browser**, read
   `${CLAUDE_PLUGIN_ROOT}/skills/grocery-cart/references/instacart-automation.md`.
   It carries the click technique, the verification signal, and the failure modes
   that cost the most time to rediscover. (Installed standalone rather than as a
   plugin, the same file is at `references/instacart-automation.md` relative to
   this one.)

## Resolving a canonical to a product

The mapping is the join key for the whole system. Match on what the mapping says —
**brand and size** — not on what the search ranks first.

- **Search rank is not evidence.** A store-brand mapping entry has resolved to a
  premium different-brand product at more than twice the price simply because it
  ranked first. If the top result isn't the mapped brand, keep looking.
- **Size is part of the key.** Stores sell distinct products under identical names
  at different sizes and wildly different prices. A name-only match is ambiguous;
  resolve size too, and if you can't, surface it rather than picking.
- **Never silently substitute a different brand.** If the mapped product isn't
  available, that is a substitution and needs approval.

**A product the search surfaced is not evidence the mapping is wrong.** Before
editing a mapping entry, check it against order history — a "correction" made from
a search result has already replaced a correct entry with a wrong one.

**Pick pack format from the plan's computed draw**, not from a static preference.
A format that suits a heavy single-cook draw is the wrong choice for a slow
teaspoon-at-a-time draw, and the reverse. Where the KB states a format preference,
read it as the answer to a past question rather than a law — and if a stated rule
and the shelf make an item unbuyable, that collision is the finding. Say so; don't
force one of them.

## Resolving a canonical with no mapping

Finding new products is normal and expected. It is a designed path, not an error
path — and the mapping only grows through it.

The goal is **hands-off with exactly one human decision:**

1. **Detect, don't interrupt.** Any canonical in the plan with no mapping entry
   goes into a resolve queue. Don't stop the run, and don't ask about them one at a
   time as they surface.
2. **Search unattended.** For each, search the store in the already-open session.
   Prefer the store brand and the size matching the recipe's purchase unit. Gather
   the top candidates with product string, size, and price.
3. **Ask once, in a batch.** Present the queue together near the end of the run —
   one line per canonical, recommended product plus alternatives. Batching is the
   point: the interruption cost is per-prompt, not per-item.
4. **The user approves the choice.** This is the only required human step and it is
   not optional. Never select silently, and never cart an unapproved substitute.
5. **Persist immediately.** On approval, write the canonical → product string into
   the mapping document, in the right section, with size and any consolidation
   behaviour. An approved choice that isn't written down is worthless next cycle.
6. **Report** which canonicals were newly resolved.

Two outcomes are findings, not failures:

- **Not carried by the store.** Reclassify as home-sourced with a fallback shape,
  say which planned meal it affects, and record it so no future cycle re-searches
  it.
- **Never deliverable** — anything that legally or practically can't be delivered.
  These produce pre-shop reminders and **must never enter the resolve queue.**

## The pantry prompt — three buckets, in this order

The order is deliberate and each bucket asks a different question:

1. **Required and not stocked — cart silently.** The meal does not happen without
   these. Asking converts a requirement into an option and invites a "no" that
   quietly kills a planned batch.
2. **Stocked staples this plan draws on — ask, and show the draw.** "Soy sauce —
   3 of 6 batches this cycle" is answerable; "soy sauce?" is not. Order by **plan
   draw, heaviest first** — that is the ranking signal you can actually compute.
   Where the KB marks an item as one the user usually keeps a spare of, drop it
   down the list; otherwise default a multi-batch draw to **included**, because a
   redundant jar is a couple of dollars and a missing one ends a batch-cook night.

   Do not attempt a finer-grained depletion estimate. Per-item reserve levels are
   deliberately not tracked — they would go stale faster than they could be
   maintained, and a confident-looking estimate built on stale data is worse than
   an honest "how are you doing on this?"
3. **Stocked with no draw — one "anything else?"** No draw to show and nothing to
   rank; just list them.

Then non-food household items as a single on-demand prompt.

**Always ask, every run.** Answers are never stored in the plan, even if the plan
was written minutes ago. Classification is a property of the plan and stays true;
"yes, I need it" is a fact about the pantry on the day it's asked.

## Items the store can't supply

Home-sourced lines split by whether a fallback exists:

- **A fallback product exists** — ask a single binary availability question, and
  only when the plan actually calls for it. No planned batch, no question.
- **No fallback is possible** — a legal restriction on delivery, a specialty vendor,
  or a product the store doesn't carry. These **must** appear in the final output as
  a pre-shop to-do, and must never become a cart line.

Do not skip the second group. A cart can look complete while a planned batch is
missing an ingredient that was never sourceable, and the failure surfaces at the
stove on the night it was planned for.

## Audit the cart before reporting

**Do not report what you believe you added.** Adds fail silently, brands resolve
wrong, and decrement loops overshoot — all three happened on the first real run,
and every one would have been caught here.

Read the actual cart contents, diff them against the plan's shopping list, and
report any mismatch: missing lines, unexpected lines, wrong quantities. It is one
read at the end of the run, and it is the only thing standing between a confident
summary and a wrong cart.

## Completion

End by reporting:

- **Expected cart contents, grouped by why each item is there** — required for a
  batch, pantry top-off, standing item. The grouping is the point: it lets the user
  audit the reasoning, not just the list.
- **Audit result** — anything the cart/plan diff turned up.
- **Newly resolved canonicals** and what was written to the mapping.
- **Unresolved items** and which batches they affect.
- **Pre-shop reminders** — everything sourced outside the store.

Then prompt the user to verify the cart and check out themselves. Say each caveat
once; repeating an acknowledged warning is unwelcome.

## Invariant — restrictions were already applied

Recipes in the KB are already correct: dietary restrictions were resolved upstream
in `/meal-planning:add-recipe`. This skill never applies a substitution and never
re-checks an ingredient against a restriction. If you find yourself reasoning about
whether an ingredient is allowed, something upstream failed — report it rather than
fixing it here.
