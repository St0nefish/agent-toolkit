"""wwcut - turn a parts list into a cutting plan and a shopping list.

A cut list says "I need a 610mm shelf". A *cut plan* says "buy three 8ft 1x10s,
and out of board #1 cut 610, 610, 610, 430, with 118 left over". The second one
is the thing you take to the lumberyard and the saw. This module does that.

Two packing problems, both solved greedily (first-fit-decreasing). Optimal bin
packing is NP-hard and pointless here: with a dozen parts, FFD lands within a
board or two of optimal, and the saw is not that precise anyway.

  * linear   - boards. Parts have one meaningful dimension (length); they get
               packed into stock lengths (6ft, 8ft, ...).
  * sheet    - plywood/MDF. Parts are 2D; they get packed into sheets, using a
               shelf/guillotine layout because that is how you actually cut a
               sheet: rip it into strips, then crosscut each strip.

Grain runs the length of a sheet. Rotating a part 90 degrees to squeeze it in
turns the grain the wrong way, so rotation is OFF by default for sheet goods —
a plan that saves half a sheet by cross-graining your cabinet sides is not a
saving. Pass allow_rotate=True if the material has no grain (MDF) or you do not
care.
"""

IN = 25.4
FT = 304.8

# What the yard actually sells. Override per project.
STOCK_LENGTHS = [6 * FT, 8 * FT, 10 * FT, 12 * FT, 16 * FT]
KERF = 3.2  # a thin-kerf blade, ~1/8"

# Sheet goods come home in one of three shapes. You always *buy* a full 4x8;
# the store's panel saw is what turns it into something that fits in a truck.
#
# The first dimension is the grain direction. This is why a crosscut half and a
# ripped half are not interchangeable: crosscutting a 4x8 gives two 4x4s whose
# grain runs along a 4ft axis, while ripping gives two 2x8s whose grain still
# runs the full 8ft. Same area, different material.
#
#   name          piece (grain, cross)   per full sheet
SHEET_PIECES = {
    "full": ((8 * FT, 4 * FT), 1),
    "half": ((4 * FT, 4 * FT), 2),       # crosscut in half — the usual "half sheet"
    "half-rip": ((8 * FT, 2 * FT), 2),   # ripped in half — stays long and narrow
}
SHEET = SHEET_PIECES["full"][0]  # backwards-compatible default


class Board:
    """One physical board bought, and the parts cut from it."""

    def __init__(self, stock, length):
        self.stock = stock
        self.length = length
        self.cuts = []      # [(name, length)]
        self.used = 0.0     # material consumed, kerf included

    def fits(self, length, kerf):
        need = length + (kerf if self.cuts else 0.0)
        return self.used + need <= self.length + 1e-6

    def place(self, name, length, kerf):
        self.used += length + (kerf if self.cuts else 0.0)
        self.cuts.append((name, length))

    @property
    def offcut(self):
        return self.length - self.used


class Sheet:
    """One sheet, packed into horizontal strips (rip, then crosscut)."""

    def __init__(self, length, width):
        self.length = length
        self.width = width
        self.strips = []   # [{"depth":, "y":, "x":, "parts":[(name,l,w)]}]
        self.used_w = 0.0

    def place(self, name, pl, pw, kerf):
        # Try an open strip first: same idea as a rip already made.
        for s in self.strips:
            if pw <= s["depth"] + 1e-6 and s["x"] + pl + kerf <= self.length + 1e-6:
                s["parts"].append((name, pl, pw))
                s["x"] += pl + kerf
                return True
        # Otherwise open a new strip, if there is width left to rip one.
        if self.used_w + pw + kerf <= self.width + 1e-6:
            self.strips.append(
                {"depth": pw, "y": self.used_w, "x": pl + kerf,
                 "parts": [(name, pl, pw)]}
            )
            self.used_w += pw + kerf
            return True
        return False

    @property
    def area_used(self):
        return sum(pl * pw for s in self.strips for _, pl, pw in s["parts"])

    @property
    def area(self):
        return self.length * self.width


def plan_linear(parts, stock_lengths=None, kerf=KERF, max_length=None):
    """Pack (name, length) parts into stock boards. Returns [Board].

    Tries each stock length on its own and keeps whichever buys the least
    material — a single length is what you actually want at the yard, and it
    beats a mixed-length greedy plan often enough not to bother with more.

    `max_length` is a transport limit: the longest board you can actually get
    home. A 12ft board is a fine plan and a useless one if it will not go in the
    truck.
    """
    stock_lengths = stock_lengths or STOCK_LENGTHS
    items = sorted(parts, key=lambda p: -p[1])

    longest = max((l for _, l in items), default=0.0)

    if max_length:
        # A part longer than the limit is not a packing problem, it is a design
        # problem: even cut to size it will not fit in the vehicle.
        toolong = [(n, l) for n, l in items if l > max_length + 1e-6]
        if toolong:
            raise ValueError(
                "part(s) longer than the %.0fmm transport limit: %s"
                % (max_length,
                   ", ".join("%s (%.0fmm)" % (n, l) for n, l in toolong))
            )
        stock_lengths = [s for s in stock_lengths if s <= max_length + 1e-6]
        if not stock_lengths:
            raise ValueError(
                "no stock length is within the %.0fmm transport limit"
                % max_length
            )

    usable = [s for s in stock_lengths if s >= longest]
    if not usable:
        raise ValueError(
            "no stock length holds a %.0fmm part (longest offered %.0fmm)"
            % (longest, max(stock_lengths))
        )

    best = None
    for stock_len in usable:
        boards = []
        for name, length in items:
            for b in boards:
                if b.fits(length, kerf):
                    b.place(name, length, kerf)
                    break
            else:
                b = Board(stock_len, stock_len)
                b.place(name, length, kerf)
                boards.append(b)
        bought = sum(b.length for b in boards)
        if best is None or bought < best[0]:
            best = (bought, boards)
    return best[1]


def plan_sheets(parts, sheet=SHEET, kerf=KERF, allow_rotate=False):
    """Pack (name, length, width) parts into sheets of one size. Returns [Sheet]."""
    sl, sw = sheet
    items = sorted(parts, key=lambda p: (-p[2], -p[1]))  # widest strip first

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


class SheetBuy:
    """A sheet plan plus what it costs you at the till and in the truck."""

    def __init__(self, piece_name, piece, pieces, per_full):
        self.piece_name = piece_name    # "full" | "half" | "half-rip"
        self.piece = piece              # (grain, cross) mm
        self.pieces = pieces            # [Sheet]
        self.per_full = per_full        # pieces obtainable from one full sheet

    @property
    def full_sheets(self):
        """You buy full sheets. The store's saw is what gives you halves."""
        n = len(self.pieces)
        return (n + self.per_full - 1) // self.per_full

    @property
    def spare_pieces(self):
        return self.full_sheets * self.per_full - len(self.pieces)

    @property
    def yield_pct(self):
        used = sum(s.area_used for s in self.pieces)
        bought = self.full_sheets * SHEET_PIECES["full"][0][0] * \
            SHEET_PIECES["full"][0][1]
        return 100.0 * used / bought if bought else 0.0


def choose_sheets(parts, kerf=KERF, allow_rotate=False, max_length=None,
                  prefer=None):
    """Pick a sheet piece size and pack into it. Returns SheetBuy.

    You always buy a full 4x8 — the choice is what the store cuts it into before
    it goes in the truck. So candidates are ranked by full sheets purchased, and
    ties are broken toward the *smaller* piece, because the smaller piece is the
    one that fits in the vehicle and on the bench.

    `max_length` drops any piece too big to carry. `prefer` forces a piece name.
    """
    names = [prefer] if prefer else list(SHEET_PIECES)

    best = None
    failures = []
    for name in names:
        piece, per_full = SHEET_PIECES[name]
        if max_length and max(piece) > max_length + 1e-6:
            failures.append("%s (%.0fmm > %.0fmm limit)"
                            % (name, max(piece), max_length))
            continue
        try:
            packed = plan_sheets(parts, piece, kerf, allow_rotate)
        except ValueError as exc:
            failures.append("%s (%s)" % (name, exc))
            continue
        buy = SheetBuy(name, piece, packed, per_full)
        rank = (buy.full_sheets, max(piece))  # fewest sheets, then smallest piece
        if best is None or rank < best[0]:
            best = (rank, buy)

    if best is None:
        raise ValueError(
            "no sheet size works: %s" % ("; ".join(failures) or "no candidates")
        )
    return best[1]


def board_feet(stock_t, stock_w, length):
    """Board feet — how lumber is actually priced."""
    return (stock_t / IN) * (stock_w / IN) * (length / IN) / 144.0
