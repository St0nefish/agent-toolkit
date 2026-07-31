# Instacart automation notes

Observed behaviour of a third-party site and of the browser tooling, recorded
because each of these cost real time to discover. Instacart's markup and internals
change without notice — if something here doesn't match what you observe, trust
what you observe and update this file.

## Session and profile

**Login is the user's job.** Don't attempt to authenticate. Cookies do not cross
Chrome profiles, so the profile the browser extension is attached to must be the
one already logged in. If the session isn't authenticated, stop and say so rather
than working through a logged-out view — a logged-out store renders prices and
availability that don't reflect the user's store or account.

## Reading order and product data

**Line items are client-rendered.** Fetching a page server-side returns roughly a
22KB application shell with no item data in it. The data lives in the Apollo
client cache after hydration.

**Read it out of the Apollo cache via a hidden same-origin iframe:**

```js
(async () => {
  const f = document.createElement('iframe');
  f.style.display = 'none';
  f.src = '/store/orders/<id>';
  document.body.appendChild(f);
  await new Promise(r => setTimeout(r, 3000));   // hydration
  const data = f.contentWindow.__APOLLO_CLIENT__.cache.extract();
  f.remove();
  return data;
})()
```

Why an iframe rather than navigation: hydration takes about three seconds, the
read is same-origin so the cache is reachable, and the current page's state
survives — no navigation, no losing where you were.

**Order detail lives at `/store/orders/<id>`**, not `/store/account/orders/<id>`.
The latter looks canonical and isn't.

## Adding items to the cart

There are three ways to trigger an Add button, in ascending order of observed
reliability. Use the third one by default.

- **Element-ref clicks** (clicking by accessibility-tree reference) report
  success and add nothing to the cart, silently, when they land right after a
  navigation. Three items were lost this way in a single run before the pattern
  was noticed — the tool call returned "ok" every time.
- **Coordinate clicks** computed from `getBoundingClientRect` work, but break
  when layout shifts between the measurement and the click. A late-rendering
  sponsored banner pushed a product card down about 64px between the two steps
  and the click landed on the wrong element.
- **Calling `button.click()` directly in page JS**, after polling for the
  button to exist, worked every time and is also the fastest of the three.
  Treat this as the default.

```js
(async () => {
  const deadline = Date.now() + 10000;
  let button;
  while (Date.now() < deadline) {
    button = document.querySelector('<add-button-selector>');
    if (button) break;
    await new Promise(r => setTimeout(r, 250));
  }
  if (!button) return { ok: false, reason: 'add button never appeared' };
  button.click();
  await new Promise(r => setTimeout(r, 500));
  return { ok: true, label: button.getAttribute('aria-label') };
})()
```

Poll for up to about 10 seconds, click in-page once the button exists, then
verify (see below) — don't trust the click itself as confirmation.

## Carting through a hidden iframe

The same hidden-iframe technique used to read the Apollo cache also works for
writing. Load a search URL in a hidden same-origin iframe, click the Add button
inside that frame, then discard the frame. The main page never navigates, so
none of its state is disturbed.

Because the main page doesn't navigate, a helper function defined once on
`window` survives for the rest of the session, and several items can be carted
per tool call instead of one — roughly 3x the throughput of navigating the
visible tab per item.

```js
(async () => {
  window.__cartAdd ??= async (url, matchText) => {
    const f = document.createElement('iframe');
    f.style.display = 'none';
    f.src = url;
    document.body.appendChild(f);
    await new Promise(r => setTimeout(r, 3000));   // hydration
    const doc = f.contentWindow.document;
    const deadline = Date.now() + 10000;
    let button;
    while (Date.now() < deadline) {
      button = [...doc.querySelectorAll('button[aria-label]')]
        .find(b => b.getAttribute('aria-label').includes(matchText));
      if (button) break;
      await new Promise(r => setTimeout(r, 250));
    }
    if (!button) { f.remove(); return { ok: false, reason: 'not found' }; }
    button.click();
    await new Promise(r => setTimeout(r, 500));
    const label = button.getAttribute('aria-label');
    f.remove();
    return { ok: true, label };
  };
  return window.__cartAdd('/store/search/<query>', '<match text>');
})()
```

## Verifying an add

**The cart badge is not a confirmation signal.** It lags the actual cart state,
and it counts distinct line items rather than units — bumping a quantity from
one to two doesn't move it at all. Don't poll the badge to confirm anything.

The reliable per-item signal is the Add button's own `aria-label`, which flips
from an add state (e.g. "Add item") to an increment state that includes the
current quantity (e.g. "Increase quantity to 1") once the click registers.
Read that label back after clicking, as in the snippets above, and treat a
label that still reads as an add state as a failed add.

## Cart panel vs. search-result labels

The quantity-bearing label described above is a property of **search-result**
buttons. The cart panel's increment/decrement buttons use a label that omits
the quantity entirely, so a loop that reads its stop condition from the label
in the cart panel never terminates — one item overshot on the way down during
a decrement loop and needed a correcting click back up.

In the cart panel, parse the quantity from the panel's rendered text instead of
the label. Watch for an ordering trap when doing this from a text dump: the
quantity string for a line **precedes** its product name in document order,
not follows it. Grabbing "the number next to this product name" by proximity
in a naive left-to-right scan pairs the quantity with the wrong item.

## Removing items and fixing quantities

An item can only be removed or decremented from a view that currently lists
it. If it isn't present in the active search results, there is no
remove/decrement control to act on, and the attempt does nothing — silently,
with no error. The cart panel reliably lists everything actually in the cart,
so treat "open the cart panel" as the standard place to make any quantity
correction or removal, rather than trying to do it from search results.

## Browser tool constraints

- **Top-level `await` is unsupported** in the JS evaluation tool. Wrap everything
  in an async IIFE, as above.
- **Batched browser calls failed consistently** with "No tab available". Use
  standalone calls.
- **Keep each JS call under about 45 seconds** or the CDP connection times out.
  Budget at most two or three iframe loads per call, and fewer when a lookup may
  not find anything — failed searches are the slow path.
- **Long numeric IDs can trip a base64 filter** on tool output and get mangled.
  Order IDs in particular are long digit strings. Read them out of anchor `href`s,
  grouped by path segment, rather than from rendered text.

## Weight mode vs count mode

Don't look for a weight-based ordering option on loose produce, and don't
prompt the user about one. On the one produce item this was checked against,
the item page sold by count only — "About N lb each, $X/lb, final cost by
weight" — with no weight selector anywhere on the page. A prior version of
this note claimed weight mode was commonly available for produce; that could
not be reproduced and appears to have been wrong. For produce, the size
variance between orders of the same requested count is a fact of the category,
not something a technique here can route around.

**Per-pound meat behaves differently, and correctly.** Those items add at a
default weight and then increment in fixed weight steps, so weight-based
ordering genuinely works for them.

The `quantityAttributesWeight` field in the extracted Apollo cache is still the
right way to tell which mode an item supports — just check it per item and
expect produce to come back empty.
