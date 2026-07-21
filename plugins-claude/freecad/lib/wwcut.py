"""wwcut - turn a parts list into a cutting plan and a shopping list.

A cut list says "I need a 610mm shelf". A *cut plan* says "buy three 8ft 1x10s,
and out of board #1 cut 610, 610, 610, 430, with 118 left over". The second one
is the thing you take to the lumberyard and the saw. This module does that.

Two packing problems, both solved greedily (first-fit-decreasing, multi-start).
Optimal bin packing is NP-hard and pointless here: with a dozen parts, FFD lands
within a board or two of optimal, and the saw is not that precise anyway.

  * linear   - boards. Parts have one meaningful dimension (length); they get
               packed into stock lengths (6ft, 8ft, ...).
  * sheet    - plywood/MDF. Parts are 2D; they get packed into sheets, using a
               shelf/guillotine layout because that is how you actually cut a
               sheet: rip it into strips, then crosscut each strip.

Three things a raw bin-packer does not know but a woodworker cares about:

  * Grain runs the length of a sheet. Rotating a part 90 degrees to squeeze it in
    turns the grain the wrong way, so rotation is OFF by default for sheet goods
    - a plan that saves half a sheet by cross-graining your cabinet sides is not
    a saving. Pass allow_rotate=True if the material has no grain (MDF).
  * Kerf. Every cut eats a saw-blade's width; the plan accounts for it.
  * Trim. Stock does not arrive dead square. `end_trim`/`edge_trim` knock a
    margin off each end/edge before anything is packed into the usable region.

Nothing here is hard-coded policy. The catalog - board lengths, sheet sizes and
their grain axis - is configurable, and the transport limit and preferred cut are
*preferences*: the planner honours them when it can, quietly upgrades a part to a
bigger piece when the preferred one is too small (with a note), and **flags** any
part that simply cannot meet the limits (bigger than any stocked sheet, or longer
than the truck) instead of failing or - worse - lying about an impossible cut.

An optional stronger sheet packer (`rectpack`, Apache-2.0) is used when it is
importable; otherwise the built-in shelf packer runs. Either way the result is a
set of rip strips you can actually cut, and a rectpack layout that does not
reduce to clean rips is rejected in favour of the shelf plan.
"""

IN = 25.4
FT = 304.8

# --- the catalog: what the yard actually sells. Override per project. --------

# Board stock lengths.
BOARD_LENGTHS = [6 * FT, 8 * FT, 10 * FT, 12 * FT, 16 * FT]
STOCK_LENGTHS = BOARD_LENGTHS  # backwards-compatible alias

# Sheet stock sizes, as (grain, cross, name). The first dimension is the grain
# direction. 4x8 is the everything sheet; 5x5 is Baltic-birch ply; add project
# panels or precut sizes here.
SHEET_SIZES = [
    (8 * FT, 4 * FT, "4x8"),
    (5 * FT, 5 * FT, "5x5"),
]
SHEET = SHEET_SIZES[0][:2]  # (8ft, 4ft) — backwards-compatible default

KERF = 3.2       # a thin-kerf blade, ~1/8"
END_TRIM = 1 * IN     # squared off each board END before use (snipe / square-up)
EDGE_TRIM = 0.5 * IN  # trimmed off each sheet EDGE before use (factory edge)

# Parts are cut oversize and trimmed to final, to align edges and clean tearout.
# This grows each part's footprint in each dimension (independent of KERF, which
# is the blade width *between* parts, and of the trims, which square the stock).
OVERSIZE = IN / 8.0   # 1/8" bigger per dimension, then trimmed to final

# How a bought sheet gets cut down for the truck, as fractions of the sheet it
# came from. You always *buy* the full sheet; the store's panel saw turns it into
# something that fits in the bed.
#
# A crosscut half and a ripped half are not interchangeable: crosscutting a 4x8
# gives two 4x4s whose grain runs along a 4ft axis, while ripping gives two 2x8s
# whose grain still runs the full 8ft. Same area, different material.
#
#   name          (grain_frac, cross_frac, pieces_per_full)
SHEET_PIECES = {
    "full": (1.0, 1.0, 1),
    "half": (0.5, 1.0, 2),      # crosscut in half — the usual "half sheet"
    "half-rip": (1.0, 0.5, 2),  # ripped in half — stays long and narrow
}


# --- boards (1D) -------------------------------------------------------------

class Board:
    """One physical board bought, and the parts cut from it.

    `length` is the nominal stock you buy (and pay for and carry). `usable` is
    what is left to cut into after end-trim; it is what parts are packed against.
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


class LinearPlan:
    """The boards to buy, plus the parts that could not be planned."""

    def __init__(self, boards, flagged):
        self.boards = boards          # [Board]
        self.flagged = flagged        # [(name, length, reason)]

    def __iter__(self):               # so `for b in plan` still walks the boards
        return iter(self.boards)

    def __len__(self):
        return len(self.boards)

    def __getitem__(self, i):
        return self.boards[i]


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


def plan_linear(parts, board_lengths=None, kerf=KERF, max_length=None,
                end_trim=0.0, oversize=0.0):
    """Pack (name, length) parts into stock boards. Returns a LinearPlan.

    Tries each stock length on its own, and a few sort orders for each, and keeps
    whichever buys the least material — a single length is what you actually want
    at the yard, and multi-start FFD beats a single greedy pass often enough to
    be worth the pennies of compute.

    `max_length` is a transport limit: the longest board you can actually get
    home. `end_trim` is squared off *each* end before parts are packed, so a
    nominal 8ft board only holds (8ft - 2*end_trim) of parts. `oversize` grows
    each part before packing — parts are cut rough and trimmed to final — so the
    lengths in the plan are the rough sizes you actually crosscut.

    Parts that cannot meet the limits — longer than the transport limit, or
    longer than the longest usable stock after end-trim — are not forced into an
    impossible plan; they are returned in `.flagged` with a reason, and the rest
    are still planned.
    """
    board_lengths = board_lengths or BOARD_LENGTHS
    items = [(n, l + oversize) for n, l in parts] if oversize else list(parts)

    carriable = ([s for s in board_lengths if s <= max_length + 1e-6]
                 if max_length else list(board_lengths))
    cap = (max(carriable) - 2.0 * end_trim) if carriable else float("-inf")

    plannable, flagged = [], []
    for name, length in items:
        if max_length and length > max_length + 1e-6:
            flagged.append((name, length,
                            "exceeds the %.0fmm transport limit" % max_length))
        elif length > cap + 1e-6:
            if carriable:
                flagged.append((name, length,
                                "longer than the longest usable stock "
                                "(%.0fmm after %.0fmm end-trim)"
                                % (cap, end_trim)))
            else:
                flagged.append((name, length,
                                "no stock length is within the %.0fmm "
                                "transport limit" % max_length))
        else:
            plannable.append((name, length))

    if not plannable:
        return LinearPlan([], flagged)

    longest = max(l for _, l in plannable)
    usable = [s for s in carriable if s - 2.0 * end_trim >= longest - 1e-6]

    best = None
    for stock_len in usable:
        stock_cap = stock_len - 2.0 * end_trim
        for order in _LINEAR_ORDERS:
            boards = _pack_linear(sorted(plannable, key=order), stock_len,
                                  stock_cap, kerf)
            bought = sum(b.length for b in boards)
            rank = (bought, len(boards))
            if best is None or rank < best[0]:
                best = (rank, boards)
    return LinearPlan(best[1], flagged)


# --- sheets (2D) -------------------------------------------------------------

class Sheet:
    """One sheet, packed into horizontal strips (rip, then crosscut)."""

    def __init__(self, length, width):
        self.length = length
        self.width = width
        self.strips = []   # [{"depth":, "y":, "x":, "parts":[(name,l,w)]}]
        self.used_w = 0.0

    def place(self, name, pl, pw, kerf):
        # A part longer than the sheet cannot go in any strip, new or open.
        if pl > self.length + 1e-6:
            return False
        # Try an open strip first: same idea as a rip already made. Cuts within
        # a strip are separated by one kerf each (n parts -> n-1 kerfs).
        for s in self.strips:
            if pw <= s["depth"] + 1e-6 and s["x"] + kerf + pl <= self.length + 1e-6:
                s["parts"].append((name, pl, pw))
                s["x"] += kerf + pl
                return True
        # Otherwise open a new strip, if there is width left to rip one. The rip
        # that separates it from the strip below eats a kerf; the first strip
        # sits against the factory edge and does not.
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
    """Pack (name, length, width) parts into sheets of one size. Returns [Sheet].

    `edge_trim` is knocked off each edge before packing, so a nominal piece only
    offers (L - 2*edge_trim) x (W - 2*edge_trim) of usable face. `oversize` grows
    each part in both dimensions (cut rough, trim to final). Multi-start: tries a
    few sort orders and keeps whichever needs the fewest sheets.
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
    placements into such bands and *validates* that they really are disjoint
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
    blade width; grain is handled by disabling rotation. The free-form placement
    rectpack returns is reduced back to rip strips and rejected if it does not
    form clean horizontal bands (see `_bands_from_placements`), so we never hand
    over a layout you cannot actually cut.
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


class SheetBuy:
    """A sheet plan plus what it costs you at the till and in the truck."""

    def __init__(self, sheet_size, sheet_name, piece_name, piece, pieces,
                 per_full, engine="shelf"):
        self.sheet_size = sheet_size    # (grain, cross) of the bought sheet, mm
        self.sheet_name = sheet_name    # "4x8", "5x5", ...
        self.piece_name = piece_name    # "full" | "half" | "half-rip"
        self.piece = piece              # (grain, cross) of the transport piece
        self.pieces = pieces            # [Sheet]
        self.per_full = per_full        # transport pieces from one full sheet
        self.engine = engine            # "shelf" | "rectpack"

    @property
    def full_sheets(self):
        """You buy full sheets. The store's saw is what gives you halves."""
        n = len(self.pieces)
        return (n + self.per_full - 1) // self.per_full

    @property
    def spare_pieces(self):
        return self.full_sheets * self.per_full - len(self.pieces)

    @property
    def bought_area(self):
        return self.full_sheets * self.sheet_size[0] * self.sheet_size[1]

    @property
    def yield_pct(self):
        used = sum(s.area_used for s in self.pieces)
        bought = self.bought_area
        return 100.0 * used / bought if bought else 0.0


class SheetPlan:
    """The sheets to buy, any preference notes, and parts that could not fit."""

    def __init__(self, buys, flagged, notes):
        self.buys = buys              # [SheetBuy]
        self.flagged = flagged        # [(name, l, w, reason)]
        self.notes = notes            # [str]


def _candidates(sheet_sizes):
    out = []
    for (grain, cross, sname) in sheet_sizes:
        for pname, (gf, cf, per_full) in SHEET_PIECES.items():
            out.append({
                "sheet_size": (grain, cross),
                "sheet_name": sname,
                "piece_name": pname,
                "piece": (grain * gf, cross * cf),
                "per_full": per_full,
            })
    return out


def _cover(parts, cands, kerf, allow_rotate, edge_trim, packer):
    """Greedily cover `parts` with buys, most-parts-then-least-material first.

    A part can only ride a piece it fits; each round picks the candidate that
    seats the most still-unplaced parts (ties: least material, then smaller
    piece), packs them, and removes them. Returns (buys, leftover).
    """
    remaining = list(parts)
    buys = []
    while remaining:
        best = None
        for c in cands:
            usable = _usable(c["piece"], edge_trim)
            fit = [p for p in remaining if _fits(p, usable, allow_rotate)]
            if not fit:
                continue
            packed, engine = _pack_one_size(
                fit, c["piece"], kerf, allow_rotate, edge_trim, packer)
            buy = SheetBuy(c["sheet_size"], c["sheet_name"], c["piece_name"],
                           c["piece"], packed, c["per_full"], engine)
            rank = (-len(fit), buy.bought_area, max(c["piece"]))
            if best is None or rank < best[0]:
                best = (rank, buy, fit)
        if best is None:
            break
        buys.append(best[1])
        for p in best[2]:
            remaining.remove(p)
    return buys, remaining


def choose_sheets(parts, sheet_sizes=None, kerf=KERF, allow_rotate=False,
                  max_length=None, edge_trim=0.0, prefer=None, packer="auto",
                  oversize=0.0):
    """Plan sheet goods from the catalog. Returns a SheetPlan.

    Each part rides the sheet size + transport piece (full / half / half-rip) that
    holds it for the least material. `prefer` is a *preference*, not a filter:
    parts that fit it use it, and parts too big for it are upgraded to the
    smallest piece that does fit, recorded in `.notes`. Parts that cannot meet
    the limits at all — bigger than any stocked sheet, or too big to carry within
    `max_length` — are returned in `.flagged`, and everything else is still
    planned. `edge_trim` shrinks each piece before packing; `oversize` grows each
    part (cut rough, trim to final); `packer` selects the engine.
    """
    sheet_sizes = sheet_sizes or SHEET_SIZES
    cands = _candidates(sheet_sizes)
    if oversize:
        parts = [(n, l + oversize, w + oversize) for n, l, w in parts]

    within = ([c for c in cands if max(c["piece"]) <= max_length + 1e-6]
              if max_length else list(cands))

    # Biggest usable face on offer, for the "does not fit any sheet" message.
    biggest = max(((s[0] - 2.0 * edge_trim, s[1] - 2.0 * edge_trim)
                   for s in sheet_sizes), key=lambda d: d[0] * d[1])

    plannable, flagged = [], []
    for part in parts:
        fits_any = any(_fits(part, _usable(c["piece"], edge_trim), allow_rotate)
                       for c in cands)
        fits_within = any(
            _fits(part, _usable(c["piece"], edge_trim), allow_rotate)
            for c in within)
        if not fits_any:
            flagged.append((part[0], part[1], part[2],
                            "bigger than any stocked sheet "
                            "(largest usable %.0f x %.0f) — split it"
                            % (biggest[0], biggest[1])))
        elif not fits_within:
            flagged.append((part[0], part[1], part[2],
                            "does not fit any piece within the %.0fmm "
                            "transport limit" % max_length))
        else:
            plannable.append(part)

    notes = []
    if not plannable:
        return SheetPlan([], flagged, notes)

    if prefer:
        pref = [c for c in within if c["piece_name"] == prefer]
        buys, leftover = _cover(plannable, pref, kerf, allow_rotate,
                                edge_trim, packer)
        if leftover:
            esc_buys, still = _cover(leftover, within, kerf, allow_rotate,
                                     edge_trim, packer)
            upgraded = [p for p in leftover if p not in still]
            if upgraded:
                notes.append(
                    "'%s' preferred, but %d part(s) needed a bigger piece: %s"
                    % (prefer, len(upgraded),
                       ", ".join(p[0] for p in upgraded)))
            buys += esc_buys
            leftover = still
    else:
        buys, leftover = _cover(plannable, within, kerf, allow_rotate,
                                edge_trim, packer)

    for p in leftover:
        flagged.append((p[0], p[1], p[2],
                        "could not be seated on any single stocked piece"))

    return SheetPlan(buys, flagged, notes)


def board_feet(stock_t, stock_w, length):
    """Board feet — how lumber is actually priced."""
    return (stock_t / IN) * (stock_w / IN) * (length / IN) / 144.0
