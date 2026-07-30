---
name: grocery-cart
description: "Build a grocery cart from a meal plan by driving a logged-in store session in the browser. Use when the user has a plan and wants the shopping done, asks to build or fill a cart, or wants to order groceries for a planned cycle. Resolves canonical shopping names to store products, runs the pantry top-off prompts, surfaces items that must be sourced elsewhere, and stops at checkout — it never places the order."
---

# grocery-cart

Reads a plan document, resolves its shopping lines to store products, and adds
them to a cart in a logged-in browser session.

**It never places the order.** The skill ends by handing a verified cart back to
the user for checkout. This is not a safety hedge to be relaxed when the cart
looks complete — the user tops off with their own items and reviews substitutions
before paying, every time.

## Where personalization lives

This skill contains no retailer name, no vendor names, no product names, and no
pantry contents. All of that lives in the knowledge base. The skill carries method;
the KB carries facts.

Instacart is named, and is a hard dependency — it is the platform this skill
automates, not a household fact. The **retailer** behind it is a household fact and
stays in the KB.

## Preflight

1. **Resolve the contracts document** by searching the KB for meal planning schema
   contracts or shopping line format. Authoritative over this file.
2. **Follow its *Profile documents* index** to the product-mapping and staples
   documents, and note the active store. Read them.
3. **Read the active plan** from the KB — the contracts document gives its location
   and frontmatter, and exactly one plan is `active` at a time. It is a complete
   serialization by contract, so work from it rather than from any planning
   conversation, which may not exist in this session. If no plan is active, say so
   and offer to run `/meal-planning:meal-plan`; do not assemble a cart from scratch.
4. **Before driving the browser**, read
   `${CLAUDE_PLUGIN_ROOT}/skills/grocery-cart/references/instacart-automation.md`.
   It carries the extraction technique and the failure modes that cost the most
   time to rediscover. (If this skill was installed standalone rather than as part
   of the plugin, the same file is at `references/instacart-automation.md` relative
   to this one.)

## Sourcing

Every shopping line carries a canonical name and a sourcing class; the contracts
document defines the classes and the quantity arithmetic. Resolve each canonical
through the product mapping — that mapping is the join key for the whole system.

When a canonical has no mapping entry, don't guess a product. Search the store,
confirm the match, and report the new canonical at the end so the mapping can be
updated. An unreported guess corrupts the join for every future cycle.

## The pantry prompt — three buckets, in this order

The order is deliberate and each bucket asks a different question:

1. **Required and not stocked — cart silently.** The meal does not happen without
   these. Asking would convert a requirement into an option, which invites a "no"
   that quietly kills a planned batch.
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

Home-sourced lines split by whether a fallback exists, and the split matters:

- **A fallback product exists** — ask a single binary availability question, and
  only when the plan actually calls for it. No planned batch, no question.
- **No fallback is possible** — a legal restriction on delivery, a specialty vendor,
  or a product the store simply doesn't carry. These **must** appear in the final
  output as a pre-shop to-do, and must never become a cart line.

Do not skip the second group. A cart can look complete while a planned batch is
missing an ingredient that was never sourceable, and the failure surfaces at the
stove on the night it was planned for.

## Completion

End by reporting:

- **Expected cart contents, grouped by why each item is there** — required for a
  batch, pantry top-off, standing item. The grouping is the point: it lets the user
  audit the reasoning, not just the list.
- **Unresolved items** — canonicals with no confident product match, and which
  batches they affect.
- **Pre-shop reminders** — everything that must be sourced outside the store.
- **New canonicals** needing mapping entries.

Then prompt the user to verify the cart and check out themselves.

## Invariant — restrictions were already applied

Recipes in the KB are already correct: dietary restrictions were resolved upstream
in `add-recipe`. This skill never applies a substitution and never re-checks an
ingredient against a restriction. If you find yourself reasoning about whether an
ingredient is allowed, something upstream failed — report it rather than fixing it
here.
