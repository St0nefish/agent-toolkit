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

Loose produce may support ordering **by weight** instead of by count. Check the
item for a non-null `quantityAttributesWeight` in the extracted cache — when
present, weight ordering is available, often in fractional-pound increments.

Prefer weight mode for loose produce when it's offered. Count mode on a
variable-size item means the delivered weight swings widely between orders for the
same requested quantity, which breaks recipe quantities in both directions.

This is a **per-item** property, not a category rule. Check each item; don't
generalise from one produce item to the next.
