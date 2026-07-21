"""wwcut - turn a parts list into sourcing options and a cutting plan.

A cut list says "I need a 610mm shelf". A *cut plan* says "buy three 8ft 1x10s,
and out of board #1 cut 610, 610, 610, 430, with 118 left over". The second one
is the thing you take to the lumberyard and the saw. This module does that.

The model that feeds this declares a part's *material type* — "framing lumber",
"hardwood", "birch-ply" — never a stock size. Turning a type into a buy is this
module's job, and there is usually more than one way to do it: a 3.5"-wide frame
strip is a 2x4 bought as-is, *or* two clean strips ripped from a 2x10. So the
planner emits a small ranked list of **sourcing options** per material group and
lets the shopper choose at the yard. It never picks the material *type* — the
human did that in the model — so cost and quality only ever compete *within* a
type (which framing nominal, how wide a hardwood board).

Two low-level packing engines do the geometry, both greedy (first-fit-decreasing,
multi-start). Optimal bin packing is NP-hard and pointless here: with a dozen
parts FFD lands within a board or two of optimal, and the saw is not that precise.

  * linear   - boards. Parts have one meaningful dimension (length); they pack
               into stock lengths (8ft, 10ft, ...).
  * sheet    - plywood/MDF, *and* ripping strips from a wide board. Parts are 2D;
               they pack into a rectangle using a shelf/guillotine layout,
               because that is how you cut a sheet (or rip a board): make the
               long rips first, then crosscut each strip.

Three things a raw bin-packer does not know but a woodworker cares about: grain
runs the length of a sheet (so rotation is OFF by default); every cut eats a
kerf; and stock is not dead square, so a margin is trimmed off each end/edge
before anything is packed into the usable region.

Transport is deliberately NOT modelled as a constraint. Whether a 12ft board or
a full 4x8 gets home is the shopper's call (rent a truck, pay for delivery, have
the store cut it) — the planner nests onto full stock and merely *annotates*
("could be store-cut in half"). Only genuine impossibility — a part bigger than
every stocked sheet, wider than every nominal — is flagged.

An optional stronger sheet packer (`rectpack`, Apache-2.0) is used when it is
importable; otherwise the built-in shelf packer runs. A rectpack layout that does
not reduce to clean rips is rejected in favour of the shelf plan.
"""

IN = 25.4
FT = 304.8

# --- defaults: the shop's habits. Override per project or per call. ----------

# Board stock lengths a yard will sell (framing default; each material may carry
# its own ladder).
BOARD_LENGTHS = [8 * FT, 10 * FT, 12 * FT, 16 * FT]
STOCK_LENGTHS = BOARD_LENGTHS  # backwards-compatible alias

# Sheet stock sizes, as (grain, cross, name); first dim is the grain direction.
# Only used as plan_sheets' default; real sheet sourcing comes from MATERIALS.
SHEET_SIZES = [
    (8 * FT, 4 * FT, "4x8"),
    (5 * FT, 5 * FT, "5x5"),
]
SHEET = SHEET_SIZES[0][:2]  # (8ft, 4ft) — backwards-compatible default

KERF = 3.2       # a thin-kerf blade, ~1/8"
END_TRIM = 1 * IN     # squared off each board END before use (snipe / square-up)
EDGE_TRIM = 0.5 * IN  # trimmed off each sheet EDGE before use (factory edge)

# Parts are cut oversize and trimmed to final, to align edges and clean tearout.
# Grows each part's footprint per dimension (independent of KERF, the blade width
# *between* parts, and of the trims, which square the stock).
OVERSIZE = IN / 8.0   # 1/8" bigger per dimension, then trimmed to final

# What tools the shop has, as the allowance each takes off. `0` means "don't have
# it" — the planner then leans on the table saw instead. `edge_cleanup` is how
# much a squared-up rip edge costs per edge (a table-saw rip pass with no jointer)
# and is what a rip-from-wider plan spends to turn a factory edge into a clean one.
TOOLING = {
    "edge_cleanup": 0.25 * IN,  # squared off each ripped edge (table-saw clean-up)
    "jointer": 0.0,             # jointer pass allowance; 0 = no jointer
    "planer": 0.0,              # planer pass allowance; 0 = no planer
    "saw_rip": KERF,            # a rip cut's kerf
}


# --- the material catalog ----------------------------------------------------
# Each entry describes how a material *type* is sold, so the option generator can
# reason about it. Three families; add species, grades, sizes freely.

def dimensional(thick, widths, lengths, tier="$"):
    """Softwood dimensional lumber: fixed thickness, a ladder of nominal widths,
    stock lengths, sold by the board."""
    return {"family": "dimensional", "thick": thick, "widths": sorted(widths),
            "lengths": sorted(lengths), "tier": tier}


def solidwood(thicknesses, lengths, tier="$$"):
    """Hardwood: thickness families (4/4, 5/4, ...), random width and length,
    sold by the board-foot. The planner rips profiles across a board's width."""
    return {"family": "solidwood", "thicknesses": list(thicknesses),
            "lengths": sorted(lengths), "tier": tier}


def sheet(sizes, grain, thicknesses, tier="$", quality=1):
    """Sheet goods of one quality: its own sheet sizes as (grain, cross, name),
    a grain rule, a set of thickness labels, a cost tier and a quality rank."""
    return {"family": "sheet", "sizes": list(sizes), "grain": bool(grain),
            "thicknesses": list(thicknesses), "tier": tier, "quality": quality}


MATERIALS = {
    # dimensional softwood — 2x nominal (actual 1.5" thick)
    "framing": dimensional(
        1.5 * IN, [3.5 * IN, 5.5 * IN, 7.25 * IN, 9.25 * IN, 11.25 * IN],
        [8 * FT, 10 * FT, 12 * FT, 16 * FT], tier="$"),
    # dimensional softwood — 1x nominal (actual 0.75" thick)
    "softwood-1x": dimensional(
        0.75 * IN, [1.5 * IN, 2.5 * IN, 3.5 * IN, 5.5 * IN, 7.25 * IN,
                    9.25 * IN, 11.25 * IN],
        [8 * FT, 10 * FT, 12 * FT], tier="$"),
    # hardwood, S3S, priced by the board-foot on nominal quarter thickness
    "hardwood": solidwood(
        ["4/4", "5/4", "6/4", "8/4"], [8 * FT, 10 * FT, 12 * FT], tier="$$"),
    # sheet qualities. Baltic birch is 5x5 and premium; the rest are 4x8.
    "mdf": sheet([(8 * FT, 4 * FT, "4x8")], grain=False,
                 thicknesses=["1/4", "1/2", "3/4"], tier="$", quality=1),
    "pine-ply": sheet([(8 * FT, 4 * FT, "4x8")], grain=True,
                      thicknesses=["1/2", "3/4"], tier="$", quality=2),
    "birch-ply": sheet([(5 * FT, 5 * FT, "5x5")], grain=True,
                       thicknesses=["1/2", "3/4"], tier="$$$", quality=4),
    "solid-core": sheet([(8 * FT, 4 * FT, "4x8")], grain=True,
                        thicknesses=["1/2", "3/4"], tier="$$", quality=3),
    # plastic laminate (Formica): a facing sheet, no grain worth respecting
    "laminate": sheet([(8 * FT, 4 * FT, "4x8")], grain=False,
                      thicknesses=["1.2mm"], tier="$", quality=1),
}


# --- boards (1D) -------------------------------------------------------------

class Board:
    """One physical board bought, and the parts cut from it.

    `length` is the nominal stock you buy (and pay for and carry). `usable` is
    what is left to cut into after end-trim; parts are packed against it.
    """

    def __init__(self, length, usable=None):
        self.length = length
        self.usable = length if usable is None else usable
        self.cuts = []      # [(name, length)]
        self.used = 0.0     # material consumed, kerf included

    def fits(self, length, kerf):
        need = length + (kerf if self.cuts else 0.0)
        return self.used + need <= self.usable + 1e-6

    def place(self, name, length, kerf):
        self.used += length + (kerf if self.cuts else 0.0)
        self.cuts.append((name, length))

    @property
    def offcut(self):
        return self.usable - self.used


_LINEAR_ORDERS = (
    lambda p: -p[1],            # longest first (classic FFD)
    lambda p: p[1],             # shortest first
    lambda p: (round(-p[1]), p[0]),  # longest, ties by name (stable variety)
)


def _pack_linear(items, stock_len, usable, kerf):
    boards = []
    for name, length in items:
        for b in boards:
            if b.fits(length, kerf):
                b.place(name, length, kerf)
                break
        else:
            b = Board(stock_len, usable)
            b.place(name, length, kerf)
            boards.append(b)
    return boards


def plan_linear(parts, board_lengths=None, kerf=KERF, end_trim=0.0, oversize=0.0):
    """Pack (name, length) parts into stock boards of one chosen length.

    Returns a list of Board, or None if the longest part will not fit any stock
    length (after end-trim) — the caller decides how to flag that. Tries each
    usable stock length on its own, and a few sort orders, and keeps whichever
    buys the least material: a single length is what you actually want at the
    yard, and multi-start FFD beats a single greedy pass often enough to be worth
    the pennies of compute. `end_trim` is squared off *each* end before packing;
    `oversize` grows each part (cut rough, trim to final).
    """
    board_lengths = board_lengths or BOARD_LENGTHS
    items = [(n, l + oversize) for n, l in parts] if oversize else list(parts)
    if not items:
        return []

    longest = max(l for _, l in items)
    usable_lengths = [s for s in board_lengths
                      if s - 2.0 * end_trim >= longest - 1e-6]
    if not usable_lengths:
        return None

    best = None
    for stock_len in usable_lengths:
        stock_cap = stock_len - 2.0 * end_trim
        for order in _LINEAR_ORDERS:
            boards = _pack_linear(sorted(items, key=order), stock_len,
                                  stock_cap, kerf)
            # Least material first; on a tie (48ft is 6x8 or 3x16 alike) prefer
            # the SHORTER stock — more standard, easier to get home — then fewer
            # boards. Transport is not a hard limit, but the sane default is 8ft.
            rank = (round(sum(b.length for b in boards)), stock_len,
                    len(boards))
            if best is None or rank < best[0]:
                best = (rank, boards)
    return best[1]


# --- sheets (2D) -------------------------------------------------------------

class Sheet:
    """One sheet (or one wide board being ripped), packed into horizontal strips
    (rip, then crosscut)."""

    def __init__(self, length, width):
        self.length = length
        self.width = width
        self.strips = []   # [{"depth":, "y":, "x":, "parts":[(name,l,w)]}]
        self.used_w = 0.0

    def place(self, name, pl, pw, kerf):
        # A part longer than the sheet cannot go in any strip, new or open.
        if pl > self.length + 1e-6:
            return False
        # Try an open strip first (a rip already made). Cuts within a strip are
        # separated by one kerf each (n parts -> n-1 kerfs).
        for s in self.strips:
            if pw <= s["depth"] + 1e-6 and s["x"] + kerf + pl <= self.length + 1e-6:
                s["parts"].append((name, pl, pw))
                s["x"] += kerf + pl
                return True
        # Otherwise open a new strip, if there is width left to rip one. The rip
        # separating it from the strip below eats a kerf; the first strip sits
        # against the factory edge and does not.
        gap = kerf if self.strips else 0.0
        if self.used_w + gap + pw <= self.width + 1e-6:
            y = self.used_w + gap
            self.strips.append(
                {"depth": pw, "y": y, "x": pl, "parts": [(name, pl, pw)]}
            )
            self.used_w = y + pw
            return True
        return False

    @property
    def area_used(self):
        return sum(pl * pw for s in self.strips for _, pl, pw in s["parts"])

    @property
    def area(self):
        return self.length * self.width


def _fits(part, piece, allow_rotate):
    """Does (name, l, w) fit an (already edge-trimmed) piece, grain respected?"""
    _n, l, w = part
    pl, pw = piece
    if l <= pl + 1e-6 and w <= pw + 1e-6:
        return True
    if allow_rotate and w <= pl + 1e-6 and l <= pw + 1e-6:
        return True
    return False


def _usable(piece, edge_trim):
    return (piece[0] - 2.0 * edge_trim, piece[1] - 2.0 * edge_trim)


_SHEET_ORDERS = (
    lambda p: (-p[2], -p[1]),   # widest strip first (classic)
    lambda p: (-p[1], -p[2]),   # longest first
    lambda p: -(p[1] * p[2]),   # biggest area first
)


def _pack_shelf(items, sl, sw, kerf, allow_rotate):
    sheets = []
    for name, pl, pw in items:
        placed = False
        for s in sheets:
            if s.place(name, pl, pw, kerf):
                placed = True
                break
            if allow_rotate and s.place(name, pw, pl, kerf):
                placed = True
                break
        if placed:
            continue

        s = Sheet(sl, sw)
        if not s.place(name, pl, pw, kerf):
            if not (allow_rotate and s.place(name, pw, pl, kerf)):
                raise ValueError(
                    "%s (%.0f x %.0f) does not fit a %.0f x %.0f piece"
                    % (name, pl, pw, sl, sw)
                )
        sheets.append(s)
    return sheets


def plan_sheets(parts, sheet=SHEET, kerf=KERF, allow_rotate=False, edge_trim=0.0,
                oversize=0.0):
    """Pack (name, length, width) parts into rectangles of one size. Returns
    [Sheet]. Raises ValueError if a part does not fit even one empty rectangle.

    `edge_trim` is knocked off each edge before packing; `oversize` grows each
    part in both dimensions (cut rough, trim to final). Multi-start: tries a few
    sort orders and keeps whichever needs the fewest sheets.
    """
    if oversize:
        parts = [(n, l + oversize, w + oversize) for n, l, w in parts]
    sl, sw = _usable(sheet, edge_trim)

    best = None
    for order in _SHEET_ORDERS:
        packed = _pack_shelf(sorted(parts, key=order), sl, sw, kerf, allow_rotate)
        if best is None or len(packed) < len(best):
            best = packed
    return best


def _bands_from_placements(placements, sl, sw, eps=1.0):
    """Reconstruct rip strips from free (rid, x, y, w, h) placements.

    A shelf-cuttable layout is a stack of horizontal bands: within a band the
    parts sit side by side along x; the bands stack along y. This groups
    placements into such bands and *validates* they really are disjoint
    horizontal strips that fit the sheet. Returns the ordered bands, or None if
    the layout does not reduce to clean rips (so the caller can reject it).
    """
    bands = []  # each: {"y", "depth", "items":[(rid,x,w,h)]}
    for rid, x, y, w, h in placements:
        band = None
        for b in bands:
            if abs(b["y"] - y) <= eps:
                band = b
                break
        if band is None:
            band = {"y": y, "depth": h, "items": []}
            bands.append(band)
        band["depth"] = max(band["depth"], h)
        band["items"].append((rid, x, w, h))

    bands.sort(key=lambda b: b["y"])

    # Bands must not overlap in y, and must fit the sheet height.
    for i in range(len(bands) - 1):
        if bands[i]["y"] + bands[i]["depth"] > bands[i + 1]["y"] + eps:
            return None
    if bands and bands[-1]["y"] + bands[-1]["depth"] > sw + eps:
        return None

    # Within a band, parts must not overlap in x, and must fit the sheet length.
    for b in bands:
        b["items"].sort(key=lambda it: it[1])
        cursor = 0.0
        for _rid, x, w, _h in b["items"]:
            if x + eps < cursor:
                return None
            if x + w > sl + eps:
                return None
            cursor = x + w
    return bands


def _pack_sheet_rectpack(parts, sheet, kerf, allow_rotate, edge_trim=0.0):
    """Pack with `rectpack` if it is importable. Returns [Sheet] or None.

    None means "not available or not cleanly cuttable" — the caller falls back to
    the shelf packer. Kerf is handled by inflating each part (and the bin) by one
    blade width; grain by disabling rotation. The free-form placement is reduced
    back to rip strips and rejected if it does not form clean horizontal bands.
    """
    try:
        import rectpack
    except Exception:
        return None

    sl, sw = _usable(sheet, edge_trim)
    if not parts:
        return []

    packer = rectpack.newPacker(rotation=bool(allow_rotate))
    for i, (_name, pl, pw) in enumerate(parts):
        if pl + kerf > sl + 1e-6 or pw + kerf > sw + 1e-6:
            if not (allow_rotate and pw + kerf <= sl + 1e-6
                    and pl + kerf <= sw + 1e-6):
                return None  # a part does not fit even one bin — let shelf raise
        packer.add_rect(pl + kerf, pw + kerf, rid=i)
    packer.add_bin(sl + kerf, sw + kerf, count=max(1, len(parts)))
    packer.pack()

    placed = set()
    sheets = []
    for abin in packer:
        pls = []
        for rect in abin:
            pls.append((rect.rid, rect.x, rect.y,
                        rect.width - kerf, rect.height - kerf))
            placed.add(rect.rid)
        if not pls:
            continue
        bands = _bands_from_placements(pls, sl, sw)
        if bands is None:
            return None
        s = Sheet(sheet[0], sheet[1])
        for b in bands:
            s.strips.append({
                "depth": b["depth"],
                "y": b["y"],
                "x": sum(w + kerf for (_rid, _x, w, _h) in b["items"]),
                "parts": [(parts[rid][0], w, h) for (rid, _x, w, h) in b["items"]],
            })
        s.used_w = sum(b["depth"] for b in bands)
        sheets.append(s)

    if len(placed) != len(parts):
        return None
    return sheets


def _pack_one_size(parts, sheet, kerf, allow_rotate, edge_trim, packer):
    """Pack parts into one sheet size with the requested engine.

    Returns (sheets, engine). "auto"/"rectpack" prefer rectpack when it is
    importable and its layout reduces to clean rips; otherwise the shelf packer
    runs and is reported as the engine used.
    """
    if packer in ("auto", "rectpack"):
        rp = _pack_sheet_rectpack(parts, sheet, kerf, allow_rotate, edge_trim)
        if rp is not None:
            return rp, "rectpack"
    return plan_sheets(parts, sheet, kerf, allow_rotate, edge_trim), "shelf"


def board_feet(stock_t, stock_w, length):
    """Board feet — how lumber is actually priced."""
    return (stock_t / IN) * (stock_w / IN) * (length / IN) / 144.0


# --- sourcing options --------------------------------------------------------

_TIER_NUM = {"$": 1, "$$": 2, "$$$": 3}


def _tier_num(tier):
    return _TIER_NUM.get(tier, len(tier))


def _bump_tier(tier):
    """A cleaner grade / wider stock is usually a step up in price."""
    return {"$": "$$", "$$": "$$$", "$$$": "$$$"}.get(tier, tier)


def _nom_inch(mm):
    """Actual mm -> the nominal inch a woodworker names it by (3.5" -> 4)."""
    return int(round(mm / IN + 0.5))


def _nominal_name(thick, width):
    """(thick_mm, width_mm) -> "2x10"."""
    return "%dx%d" % (_nom_inch(thick), _nom_inch(width))


def _quarter_inch(label):
    """A hardwood thickness label -> nominal inches for board-foot ("6/4" -> 1.5)."""
    if "/" in label:
        num, den = label.split("/")
        return float(num) / float(den)
    return float(label)


class SourcingOption:
    """One way to buy and break down a material group.

    `layout` is the concrete cut plan; `layout_kind` says how to read it:
      "boards" -> [Board], each a stick with crosscuts;
      "sheets" -> [Sheet], each a sheet/board ripped into strips then crosscut.
    `buy` is the shopping line(s) as dicts (count + nominal + length + min_width),
    left unformatted so the caller can render in the shop's own units.
    """

    def __init__(self, label, buy, layout, layout_kind, tier, quality,
                 board_feet=None, sheet_count=None, tradeoffs=None,
                 annotations=None, engine=None):
        self.label = label
        self.buy = buy                    # [{count, nominal, length?, min_width?}]
        self.layout = layout
        self.layout_kind = layout_kind    # "boards" | "sheets"
        self.tier = tier
        self.quality = quality
        self.board_feet = board_feet
        self.sheet_count = sheet_count
        self.tradeoffs = tradeoffs or []
        self.annotations = annotations or []
        self.engine = engine
        self.recommended = False

    @property
    def amount(self):
        return self.board_feet if self.board_feet is not None else self.sheet_count


class OptionSet:
    """Every sourcing option for one (material, thickness) group, ranked."""

    def __init__(self, material, thickness, options, flagged, notes):
        self.material = material
        self.thickness = thickness
        self.options = options          # [SourcingOption], best first
        self.flagged = flagged          # [(name, reason)]
        self.notes = notes              # [str]

    @property
    def recommended(self):
        return self.options[0] if self.options else None

    @property
    def alternatives(self):
        return self.options[1:]


def _rank_key(o, prefer):
    t = _tier_num(o.tier)
    amt = o.amount if o.amount is not None else 0
    if prefer == "cost":
        return (t, amt)
    if prefer == "quality":
        return (-o.quality, t, amt)
    # value (default): trade tier against quality, then least material, then the
    # cheaper tier as a final tie-break.
    return (t - o.quality, amt, t)


def _rank(options, prefer):
    options.sort(key=lambda o: _rank_key(o, prefer))
    if options:
        options[0].recommended = True
    return options


def source_options(parts, material, thickness=None, kerf=KERF, end_trim=END_TRIM,
                   edge_trim=EDGE_TRIM, oversize=OVERSIZE, prefer="value",
                   tooling=None, packer="auto"):
    """Ranked ways to buy one material group. Returns an OptionSet.

    `parts` are finished sizes as (name, length, width) — length the longest
    dimension, width the next (thickness is the material's own and is not packed).
    `material` keys into MATERIALS; `thickness` is its label where the family
    needs one (hardwood quarters, sheet-good thickness). `prefer` is value /
    cost / quality. The tool never chooses the material type, so ranking only
    orders options *within* this type.
    """
    tooling = TOOLING if tooling is None else tooling
    spec = MATERIALS[material]
    fam = spec["family"]
    if not parts:
        return OptionSet(material, thickness, [], [], [])

    if fam == "dimensional":
        opts, flagged, notes = _options_dimensional(
            parts, spec, kerf, end_trim, oversize, tooling)
    elif fam == "solidwood":
        opts, flagged, notes = _options_hardwood(
            parts, spec, thickness, kerf, end_trim, oversize, tooling)
    elif fam == "sheet":
        opts, flagged, notes = _options_sheet(
            parts, spec, kerf, edge_trim, oversize, packer)
    else:
        raise ValueError("unknown material family %r" % fam)

    _rank(opts, prefer)
    return OptionSet(material, thickness, opts, flagged, notes)


def _options_dimensional(parts, spec, kerf, end_trim, oversize, tooling):
    """Dimensional lumber: an exact-nominal buy used as-is, plus rip-from-wider
    options for any nominal that yields two or more clean strips."""
    widths = spec["widths"]
    lengths = spec["lengths"]
    thick = spec["thick"]
    cleanup = tooling["edge_cleanup"]

    flagged, plan_parts = [], []
    max_usable_len = max(lengths) - 2.0 * end_trim
    for n, l, w in parts:
        if w > widths[-1] + 1e-6:
            flagged.append((n, "wider (%.0f) than any stocked nominal" % w))
        elif l + oversize > max_usable_len + 1e-6:
            flagged.append((n, "longer (%.0f) than the longest stocked board" % l))
        else:
            plan_parts.append((n, l, w))
    if not plan_parts:
        return [], flagged, []

    maxW = max(w for _, _, w in plan_parts)
    options = []

    # 1. exact-nominal: the narrowest nominal that holds the widest strip, bought
    #    as-is (factory-eased edges), planned 1-D by length.
    exact = next((w for w in widths if w >= maxW - 1e-6), None)
    if exact is not None:
        boards = plan_linear([(n, l) for n, l, _ in plan_parts], lengths,
                             kerf, end_trim, oversize)
        if boards:
            bf = sum(board_feet(thick, exact, b.length) for b in boards)
            options.append(SourcingOption(
                label="%s, as-is" % _nominal_name(thick, exact),
                buy=[{"count": len(boards),
                      "nominal": _nominal_name(thick, exact),
                      "length": boards[0].length}],
                layout=boards, layout_kind="boards", tier=spec["tier"], quality=1,
                board_feet=bf, tradeoffs=["factory (eased) edges", "no ripping"]))

    # 2. rip-from-wider: any wider nominal that yields >= 2 clean strips. One
    #    clean strip is no gain over buying the exact nominal — that is the "2x8
    #    trap". Ripping is a 2-D nest onto a narrow "sheet" of (length, nominal).
    for w in widths:
        if exact is not None and w <= exact + 1e-6:
            continue
        lanes = int((w - 2.0 * cleanup + kerf) // (maxW + kerf))
        if lanes < 2:
            continue
        best = None
        for L in lengths:
            try:
                sheets = plan_sheets([(n, l, pw) for n, l, pw in plan_parts],
                                     sheet=(L, w), kerf=kerf, allow_rotate=False,
                                     edge_trim=cleanup, oversize=oversize)
            except ValueError:
                continue
            # Least material (board count x length), then the shorter stock.
            rank = (round(len(sheets) * L), L)
            if best is None or rank < best[0]:
                best = (rank, sheets, L)
        if best is None:
            continue
        _, sheets, L = best
        bf = len(sheets) * board_feet(thick, w, L)
        options.append(SourcingOption(
            label="rip from %s" % _nominal_name(thick, w),
            buy=[{"count": len(sheets), "nominal": _nominal_name(thick, w),
                  "length": L}],
            layout=sheets, layout_kind="sheets", tier=_bump_tier(spec["tier"]),
            quality=2, board_feet=bf,
            tradeoffs=["%d clean strips/board" % lanes, "all-square edges",
                       "clearer grade"]))

    return options, flagged, []


def _options_hardwood(parts, spec, thickness, kerf, end_trim, oversize, tooling):
    """Hardwood: nest the rip profiles across a board's width. Random-width stock,
    so options are phrased "buy >= N boards >= W wide x L": a wide-board option
    that stacks every profile onto few boards, and a narrow-board option, one
    board width per distinct profile."""
    thickness = thickness or spec["thicknesses"][0]
    nom_thick = _quarter_inch(thickness) * IN
    lengths = spec["lengths"]
    cleanup = tooling["edge_cleanup"]

    flagged, plan_parts = [], []
    max_usable_len = max(lengths) - 2.0 * end_trim
    for n, l, w in parts:
        if l + oversize > max_usable_len + 1e-6:
            flagged.append((n, "longer (%.0f) than the longest stocked board" % l))
        else:
            plan_parts.append((n, l, w))
    if not plan_parts:
        return [], flagged, []

    widths = sorted({round(w, 1) for _, _, w in plan_parts})
    options = []

    def nest(group, board_w):
        best = None
        for L in lengths:
            try:
                sheets = plan_sheets(group, sheet=(L, board_w), kerf=kerf,
                                     allow_rotate=False, edge_trim=cleanup,
                                     oversize=oversize)
            except ValueError:
                continue
            rank = (round(len(sheets) * L), L)
            if best is None or rank < best[0]:
                best = (rank, sheets, L)
        return best

    # wide-board option: one board carries a lane per distinct profile width.
    # Each lane is packed at (profile width + oversize); the board must hold the
    # lanes, the rip kerfs between them, and the cleaned-up edges.
    lane = lambda w: w + oversize
    wide_w = (sum(lane(w) for w in widths) + kerf * max(0, len(widths) - 1)
              + 2.0 * cleanup + 2.0)
    wide = nest(plan_parts, wide_w)
    if wide:
        _, sheets, L = wide
        bf = len(sheets) * board_feet(nom_thick, wide_w, L)
        options.append(SourcingOption(
            label="wide boards",
            buy=[{"count": len(sheets), "nominal": thickness,
                  "min_width": wide_w, "length": L}],
            layout=sheets, layout_kind="sheets", tier=spec["tier"], quality=1,
            board_feet=bf,
            tradeoffs=["fewest boards", "%d rip profiles/board" % len(widths)],
            annotations=["random-width stock: real boards run wider; "
                         "extra width is offcut"]))

    # narrow-board option: a separate run per distinct profile width. Only worth
    # showing when there is more than one profile (else it equals the wide one).
    if len(widths) > 1:
        buys, all_sheets, total_bf = [], [], 0.0
        ok = True
        for w in widths:
            grp = [(n, l, pw) for n, l, pw in plan_parts if round(pw, 1) == w]
            board_w = lane(w) + 2.0 * cleanup + 2.0
            res = nest(grp, board_w)
            if res is None:
                ok = False
                break
            _, sheets, L = res
            buys.append({"count": len(sheets), "nominal": thickness,
                         "min_width": board_w, "length": L})
            all_sheets.extend(sheets)
            total_bf += len(sheets) * board_feet(nom_thick, w + 2.0 * cleanup, L)
        if ok:
            options.append(SourcingOption(
                label="narrow boards",
                buy=buys, layout=all_sheets, layout_kind="sheets",
                tier=spec["tier"], quality=1, board_feet=total_bf,
                tradeoffs=["one board width per profile", "more boards"],
                annotations=["random-width stock: real boards run wider; "
                             "extra width is offcut"]))

    return options, flagged, []


def _options_sheet(parts, spec, kerf, edge_trim, oversize, packer):
    """Sheet goods: nest onto each of the quality's sheet sizes that holds every
    part, one option per size. Transport is annotated, never forced."""
    allow_rotate = not spec["grain"]
    sizes = spec["sizes"]

    # Flag parts bigger than every stocked size (grain respected).
    flagged, plan_parts = [], []
    for part in parts:
        if any(_fits(part, _usable(s[:2], edge_trim), allow_rotate)
               for s in sizes):
            plan_parts.append(part)
        else:
            biggest = max(sizes, key=lambda s: s[0] * s[1])
            u = _usable(biggest[:2], edge_trim)
            flagged.append((part[0], "bigger than any stocked sheet "
                            "(largest usable %.0f x %.0f) - split it"
                            % (u[0], u[1])))
    if not plan_parts:
        return [], flagged, []

    options = []
    for (grain, cross, name) in sizes:
        if not all(_fits(p, _usable((grain, cross), edge_trim), allow_rotate)
                   for p in plan_parts):
            continue
        sheets, engine = _pack_one_size(plan_parts, (grain, cross), kerf,
                                        allow_rotate, edge_trim, packer)
        annotations = []
        # Transport is informational: a full 4x8 you could have the store rip.
        if grain >= 8 * FT - 1e-6 and cross >= 4 * FT - 1e-6:
            annotations.append("full %s - each could be store-cut in half" % name)
        options.append(SourcingOption(
            label=name,
            buy=[{"count": len(sheets), "nominal": name}],
            layout=sheets, layout_kind="sheets", tier=spec["tier"],
            quality=spec["quality"], sheet_count=len(sheets),
            tradeoffs=["grain respected" if spec["grain"] else "no grain"],
            annotations=annotations, engine=engine))

    return options, flagged, []
