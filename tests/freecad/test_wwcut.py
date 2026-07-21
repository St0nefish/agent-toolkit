#!/usr/bin/env python3
"""Unit tests for wwcut — the cut-list optimizer and sourcing-option generator.

wwcut imports no FreeCAD/Part/Mesh, so it runs under a plain interpreter and is
CI-testable. Plain asserts, no pytest dependency. Exits non-zero on any failure.
"""

import os
import sys
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = os.path.normpath(
    os.path.join(_HERE, "..", "..", "plugins-claude", "freecad", "lib"))
sys.path.insert(0, _LIB)

import wwcut as wc  # noqa: E402

FT = wc.FT
IN = wc.IN

_PASS = 0
_FAIL = 0


def check(cond, label):
    global _PASS, _FAIL
    if cond:
        _PASS += 1
        print("  \033[32m✓\033[0m %s" % label)
    else:
        _FAIL += 1
        print("  \033[31m✗\033[0m %s" % label)


def raises(fn, label):
    try:
        fn()
    except ValueError:
        check(True, label)
    except Exception as exc:  # wrong exception type is still a failure
        check(False, "%s (raised %r, wanted ValueError)" % (label, exc))
    else:
        check(False, "%s (did not raise)" % label)


def approx(a, b, tol=0.5):
    return abs(a - b) <= tol


def labels(optset):
    return [o.label for o in optset.options]


class _StubRect:
    """A rectpack-shaped placed-rect stand-in: .rid/.x/.y/.width/.height."""

    def __init__(self, rid, x, y, w, h):
        self.rid, self.x, self.y = rid, x, y
        self.width, self.height = w, h


def _install_fake_rectpack(pack_fn=None):
    """A minimal stand-in for the optional `rectpack` package, installed into
    sys.modules so `_pack_sheet_rectpack`'s internal branches (beyond the
    soft-import guard) can be exercised even on a machine where the real
    dependency is not installed. `pack_fn(rects, bins)` -> [[_StubRect, ...],
    ...] controls what pack() produces; the default places every rect side by
    side in one row of one bin (a trivially "clean" shelf layout)."""

    class _Packer:
        def __init__(self, rotation=True):
            self.rotation = rotation
            self._rects = []
            self._bins = []
            self._packed = []

        def add_rect(self, w, h, rid=None):
            self._rects.append((w, h, rid))

        def add_bin(self, w, h, count=1):
            self._bins.append((w, h, count))

        def pack(self):
            if pack_fn is not None:
                self._packed = pack_fn(self._rects, self._bins)
                return
            x = 0.0
            row = []
            for (w, h, rid) in self._rects:
                row.append(_StubRect(rid, x, 0.0, w, h))
                x += w
            self._packed = [row] if row else []

        def __iter__(self):
            return iter(self._packed)

    fake = types.ModuleType("rectpack")
    fake.newPacker = _Packer
    sys.modules["rectpack"] = fake


def _remove_fake_rectpack():
    sys.modules.pop("rectpack", None)


# --- low-level linear packer -------------------------------------------------

print("-- linear: basic FFD --")
plan = wc.plan_linear([("a", 600), ("b", 600), ("c", 600), ("d", 430)],
                      end_trim=0.0)
check(len(plan) == 1, "four short parts pack into one board")
check(approx(plan[0].length, 8 * FT), "and it is the 8ft, the least material")
check(sum(len(b.cuts) for b in plan) == 4, "every part is placed exactly once")

print("-- linear: kerf is consumed --")
half = 8 * FT / 2.0
eightft = [8 * FT]
p0 = wc.plan_linear([("a", half), ("b", half)], board_lengths=eightft,
                    kerf=0.0, end_trim=0.0)
p1 = wc.plan_linear([("a", half), ("b", half)], board_lengths=eightft,
                    kerf=3.2, end_trim=0.0)
check(len(p0) == 1, "two exact-half parts fit one 8ft with no kerf")
check(len(p1) == 2, "the same two need a second 8ft once kerf is counted")

print("-- linear: end-trim shrinks usable length --")
p_notrim = wc.plan_linear([("long", 2420)], end_trim=0.0)
p_trim = wc.plan_linear([("long", 2420)], end_trim=1 * IN)
check(approx(p_notrim[0].length, 8 * FT), "2420mm part uses an 8ft with no trim")
check(approx(p_trim[0].length, 10 * FT),
      "the same part needs a 10ft once 1in is squared off each end")

print("-- linear: a part too long for every stock returns None --")
big = wc.plan_linear([("huge", 16 * FT + 100)], end_trim=0.0)
check(big is None, "no stock length holds it -> None (caller flags it)")

print("-- linear: prefer the shorter standard stock on a material tie --")
# 15 frame parts, 12705mm: 6x8ft and 3x16ft both buy 48ft; 8ft is the sane pick.
frame = [("Frame_Front", 1747), ("Frame_Back", 1747),
         ("Frame_Cross_0", 863), ("Frame_Cross_1", 863), ("Frame_Cross_2", 863),
         ("Frame_AssyEnd", 787), ("Frame_RouterEnd", 787)]
frame += [("Post_%d" % i, 631) for i in range(8)]
lp = wc.plan_linear([(n, l) for n, l in frame], end_trim=1 * IN)
check(approx(lp[0].length, 8 * FT) and len(lp) == 6,
      "the frame packs into six 8ft, not three 16ft")

print("-- linear: empty and offcut --")
check(wc.plan_linear([]) == [], "no parts -> empty list")
one = wc.plan_linear([("a", 600)], board_lengths=[8 * FT], end_trim=0.0, kerf=3.2)
check(approx(one[0].offcut, 8 * FT - 600), "offcut = usable - used (no leading kerf)")

print("-- linear: oversize grows the cut --")
p2 = wc.plan_linear([("y", 600)], board_lengths=[8 * FT], end_trim=0.0,
                    oversize=10.0)
check(approx(p2[0].cuts[0][1], 610),
      "the planned cut is the rough (final + oversize) length")


# --- low-level sheet packer --------------------------------------------------

print("-- sheets: basic pack + grain --")
FOURBYEIGHT = (8 * FT, 4 * FT)
s = wc.plan_sheets([("panel", 1000, 300)], sheet=FOURBYEIGHT, edge_trim=0.0)
check(len(s) == 1, "one small panel fits one 4x8")

print("-- sheets: rotation off by default (grain) --")
narrow = (1200, 1400)
raises(lambda: wc.plan_sheets([("p", 1300, 1100)], sheet=narrow,
                              allow_rotate=False, edge_trim=0.0),
       "a part too long for the grain axis will not fit un-rotated")
rot = wc.plan_sheets([("p", 1300, 1100)], sheet=narrow, allow_rotate=True,
                     edge_trim=0.0)
check(len(rot) == 1, "the same part fits once rotation is allowed")

print("-- Sheet.place: first cut has no kerf, later cuts do --")
sh = wc.Sheet(1000.0, 500.0)
check(sh.place("a", 400.0, 100.0, 10.0), "first part seats")
check(approx(sh.strips[0]["x"], 400.0), "the first cut consumes no leading kerf")
check(sh.place("b", 400.0, 100.0, 10.0), "a second part seats in the same rip")
check(approx(sh.strips[0]["x"], 810.0), "the second cut adds one kerf (400+10+400)")
check(sh.place("c", 100.0, 350.0, 10.0), "a third part opens a new rip")
check(approx(sh.strips[1]["y"], 110.0), "the new rip sits one kerf above the first")

print("-- Sheet.place: a part longer than the sheet never seats --")
sh2 = wc.Sheet(500.0, 500.0)
check(not sh2.place("toolong", 600.0, 100.0, 3.0),
      "a part longer than the sheet is refused, not silently overhung")


# --- band reconstruction (engine-agnostic) -----------------------------------

print("-- bands: clean layout reconstructs --")
good = [(0, 0.0, 0.0, 100.0, 50.0), (1, 100.0, 0.0, 100.0, 50.0),
        (2, 0.0, 50.0, 120.0, 40.0)]
bands = wc._bands_from_placements(good, 300.0, 100.0)
check(bands is not None and len(bands) == 2, "two clean rips reconstruct")
check(bands is not None and len(bands[0]["items"]) == 2,
      "the lower rip holds both side-by-side parts")

print("-- bands: overlaps and overflow are rejected --")
check(wc._bands_from_placements(
    [(0, 0.0, 0.0, 100.0, 50.0), (1, 50.0, 0.0, 100.0, 50.0)],
    300.0, 100.0) is None, "parts overlapping along a rip are rejected")
check(wc._bands_from_placements([(0, 0.0, 0.0, 400.0, 50.0)], 300.0, 100.0)
      is None, "a part wider than the sheet is rejected")
check(wc._bands_from_placements(
    [(0, 0.0, 0.0, 100.0, 80.0), (1, 0.0, 50.0, 100.0, 40.0)],
    300.0, 100.0) is None, "rips that overlap in depth are rejected")

print("-- engine: rectpack soft-import falls back cleanly --")
res = wc._pack_sheet_rectpack([("p", 1000, 300)], (8 * FT, 4 * FT), 3.2, False)
try:
    import rectpack  # noqa: F401
    _have_rp = True
except Exception:
    _have_rp = False
check(res is None if not _have_rp else res is not None,
      "returns None when rectpack is missing (shelf takes over)")
sheets, engine = wc._pack_one_size([("p", 1000, 300)], (8 * FT, 4 * FT), 3.2,
                                   False, 0.0, "auto")
check(len(sheets) == 1 and engine in ("shelf", "rectpack"),
      "auto packer always produces a plan and names its engine")

print("-- engine: _pack_sheet_rectpack branches (stubbed, so they run on any "
      "machine regardless of whether the real dependency is installed) --")
_install_fake_rectpack()
try:
    check(wc._pack_sheet_rectpack([], (8 * FT, 4 * FT), 3.2, False) == [],
          "empty parts -> [] once rectpack is importable")

    mixed = [("a", 100.0, 50.0, True), ("b", 100.0, 50.0, False)]
    check(wc._pack_sheet_rectpack(mixed, (8 * FT, 4 * FT), 3.2, False) is None,
          "disagreeing per-part rotation flags bail out to the shelf packer")
    sheets, engine = wc._pack_one_size(mixed, (8 * FT, 4 * FT), 3.2, False, 0.0,
                                       "auto")
    check(sheets is not None and engine == "shelf",
          "_pack_one_size still produces a plan for a mixed-rotation group, "
          "via the shelf fallback")

    # A part too big for a single bin on either axis (even rotated): rejected
    # before the packer even runs, so the shelf packer gets a chance to raise
    # its own clearer error instead.
    huge = [("nope", 9000.0, 9000.0)]
    check(wc._pack_sheet_rectpack(huge, (8 * FT, 4 * FT), 3.2, False) is None,
          "a part too big for even one bin (both axes) is rejected")
finally:
    _remove_fake_rectpack()

print("-- engine: _pack_sheet_rectpack happy path (stubbed clean layout) --")
_install_fake_rectpack()
try:
    clean = [("p1", 500.0, 200.0), ("p2", 400.0, 200.0)]
    res = wc._pack_sheet_rectpack(clean, (8 * FT, 4 * FT), 3.2, False)
    check(res is not None and len(res) == 1,
          "a clean side-by-side stub layout reduces to one Sheet")
    if res is not None:
        strip = res[0].strips[0]
        check(approx(strip["depth"], 200.0),
              "the reconstructed strip depth matches the parts' width")
        placed = {n for n, _l, _w in strip["parts"]}
        check(placed == {"p1", "p2"}, "both stubbed parts land in the one strip")
finally:
    _remove_fake_rectpack()

print("-- engine: _pack_sheet_rectpack rejects a layout that isn't clean rips --")
_install_fake_rectpack(pack_fn=lambda rects, bins: [[
    # Two rects at the same y that overlap in x: not a valid rip strip.
    _StubRect(rid, 0.0, 0.0, w, h) for (w, h, rid) in rects
]])
try:
    overlapping = [("p1", 500.0, 200.0), ("p2", 400.0, 200.0)]
    res = wc._pack_sheet_rectpack(overlapping, (8 * FT, 4 * FT), 3.2, False)
    check(res is None,
          "a free-form placement that does not reduce to clean rips is rejected")
finally:
    _remove_fake_rectpack()

print("-- engine: _pack_sheet_rectpack rejects a leftover (partially packed) bin --")
_install_fake_rectpack(pack_fn=lambda rects, bins: [[
    # Only the first rect gets placed; the second is dropped, as a real packer
    # would do if a bin ran out of room -- len(placed) != len(parts).
    _StubRect(rects[0][2], 0.0, 0.0, rects[0][0], rects[0][1])
]])
try:
    leftover = [("p1", 500.0, 200.0), ("p2", 400.0, 200.0)]
    res = wc._pack_sheet_rectpack(leftover, (8 * FT, 4 * FT), 3.2, False)
    check(res is None,
          "a partially-packed bin (not every part placed) is rejected")
finally:
    _remove_fake_rectpack()


# --- board feet --------------------------------------------------------------

print("-- board feet --")
check(approx(wc.board_feet(1.5 * IN, 3.5 * IN, 8 * FT), 3.5, 0.01),
      "a 2x4x8 is 3.5 board feet")
check(approx(wc.board_feet(0.75 * IN, 5.5 * IN, 6 * FT), 2.0625, 0.01),
      "a 1x6x6 is ~2.06 board feet")


# --- sourcing options: dimensional ------------------------------------------

# The frame strips: 15 parts, all 3.5" (88.9mm) wide.
FRAME = [(n, l, 88.9) for n, l in frame]

print("-- dimensional: exact-nominal is the value pick, rips are alternatives --")
os_val = wc.source_options(FRAME, "framing", prefer="value")
rec = os_val.recommended
check(rec is not None and rec.label == "2x4, as-is",
      "value recommends the 2x4 bought as-is")
check(approx(rec.board_feet, 21.0, 0.2) and rec.buy[0]["count"] == 6,
      "which is six 2x4 at 21.0 board-feet")
check(rec.tier == "$", "and it is the cheapest tier")
check(not os_val.flagged, "nothing is flagged")

print("-- dimensional: the 1-lane nominals (2x6/2x8 trap) are not offered --")
labs = labels(os_val)
check(any("2x10" in la for la in labs), "2x10 (2 clean strips) IS offered")
check(not any("2x6" in la or "2x8" in la for la in labs),
      "2x6 and 2x8 yield only one clean strip -> no rip option (the trap)")

print("-- dimensional: lane count reproduces the hand-checked case --")
r10 = next(o for o in os_val.options if "2x10" in o.label)
check(any("2 clean strips/board" in t for t in r10.tradeoffs),
      "a 2x10 yields exactly two clean 3.5in strips")
check(r10.layout_kind == "sheets" and len(r10.layout) == 3
      and approx(r10.board_feet, 27.8, 0.2),
      "ripping the frame from 2x10 is three boards, 27.8 board-feet")

print("-- dimensional: the 2x10 rip's board_feet matches the hand formula --")
# board_feet must be n_sheets * board_feet(thick, nominal_width, stock_length),
# using the ACTUAL nominal stock length bought (buy[0]["length"]), not the
# edge-trimmed usable Sheet.length the layout stores internally.
_thick = wc.MATERIALS["framing"]["thick"]
_nom_w = 9.25 * IN  # the 2x10's stocked nominal width
_L = r10.buy[0]["length"]
_expected_bf = len(r10.layout) * wc.board_feet(_thick, _nom_w, _L)
check(approx(r10.board_feet, _expected_bf, 0.01),
      "rip-from-2x10 board_feet == n_sheets * board_feet(thick, 9.25in, L)")

print("-- dimensional: prefer knob reorders the recommendation --")
check(wc.source_options(FRAME, "framing", prefer="cost").recommended.label
      == "2x4, as-is", "prefer=cost keeps the cheap 2x4")
check("rip from 2x10" ==
      wc.source_options(FRAME, "framing", prefer="quality").recommended.label,
      "prefer=quality recommends the all-square-edge 2x10 rip")

print("-- dimensional: a part wider than every nominal is flagged --")
osf = wc.source_options([("slab", 800, 400)], "framing")
check(len(osf.flagged) == 1 and "wider" in osf.flagged[0][1],
      "a 400mm-wide strip has no framing nominal and is flagged")


# --- ranking tie-breaks -------------------------------------------------------
# _rank_key documents a tie-break order for each `prefer` mode. The framing
# fixture above only ever distinguishes options by tier or quality, so the
# amount/tier tie-break clauses are never actually decisive there -- exercise
# them directly against synthetic SourcingOptions with genuinely tied keys.


class _FakeOpt:
    """A stand-in SourcingOption: only what _rank_key/_rank touch."""

    def __init__(self, label, tier, quality, amount):
        self.label = label
        self.tier = tier
        self.quality = quality
        self._amount = amount
        self.recommended = False

    @property
    def amount(self):
        return self._amount


print("-- ranking: value tie-break falls through amount, then tier --")
# Same tier and quality (tier-quality == 0 for both) -> decided by amount.
a = _FakeOpt("less-material", "$", 1, 10.0)
b = _FakeOpt("more-material", "$", 1, 20.0)
check([o.label for o in wc._rank([b, a], "value")]
      == ["less-material", "more-material"],
      "value: equal tier-quality ties break on least amount")
# Same tier-quality AND same amount -> decided by the final tier tie-break.
c = _FakeOpt("cheap-tier", "$", 1, 15.0)      # tier-quality = 1-1 = 0
d = _FakeOpt("pricier-tier", "$$", 2, 15.0)   # tier-quality = 2-2 = 0
check([o.label for o in wc._rank([d, c], "value")]
      == ["cheap-tier", "pricier-tier"],
      "value: a full tie on tier-quality and amount breaks on cheaper tier")

print("-- ranking: cost tie-break ignores quality, breaks on amount --")
e = _FakeOpt("less", "$", 1, 30.0)
f = _FakeOpt("more-but-nicer", "$", 5, 5.0)
check([o.label for o in wc._rank([e, f], "cost")] == ["more-but-nicer", "less"],
      "cost: same tier -> least amount wins regardless of quality")

print("-- ranking: quality tie-break falls through tier, then amount --")
g = _FakeOpt("pricier", "$$", 3, 50.0)
h = _FakeOpt("cheaper", "$", 3, 10.0)
check([o.label for o in wc._rank([g, h], "quality")] == ["cheaper", "pricier"],
      "quality: same quality -> cheaper tier wins")

print("-- ranking: framing end-to-end, all three prefer modes + alternatives --")
check(wc.source_options(FRAME, "framing", prefer="value").recommended.label
      == "2x4, as-is", "value -> 2x4, as-is")
check(wc.source_options(FRAME, "framing", prefer="cost").recommended.label
      == "2x4, as-is", "cost -> 2x4, as-is")
check(wc.source_options(FRAME, "framing", prefer="quality").recommended.label
      .startswith("rip from"), "quality -> a rip option")
_val_opts = wc.source_options(FRAME, "framing", prefer="value").options
_keys = [wc._rank_key(o, "value") for o in _val_opts]
check(_keys == sorted(_keys),
      "the full option list (recommended + alternatives) is in _rank_key order")


# --- sourcing options: hardwood ---------------------------------------------

HW = [("Band_Front", 1942, 102), ("Band_Back", 1942, 102),
      ("Band_Left", 982, 102), ("Band_Right", 982, 102),
      ("Rail_Front", 1850, 45), ("Rail_Back", 1850, 45),
      ("Rail_Left", 890, 45), ("Rail_Right", 890, 45)]

print("-- hardwood: wide vs narrow boards, phrased as >=W wide --")
osh = wc.source_options(HW, "hardwood", thickness="4/4", prefer="value")
labs = labels(osh)
check("wide boards" in labs and "narrow boards" in labs,
      "both a wide-board and a narrow-board option are produced")
check(osh.recommended.label == "wide boards",
      "the wide-board option (fewest boards) is recommended")
b = osh.recommended.buy[0]
check(b.get("min_width") is not None and b["nominal"] == "4/4",
      "the buy line is a 4/4 board >= some width, not a fixed nominal")
check(not osh.flagged, "nothing flagged")

print("-- hardwood: the narrow option carries one board width per profile --")
narrow = next(o for o in osh.options if o.label == "narrow boards")
check(len(narrow.buy) == 2, "two profile widths -> two separate buy lines")

print("-- hardwood: wide-board min_width matches the hand formula --")
# wide_w = sum(w + oversize for each distinct profile width)
#          + kerf * (n_profiles - 1) + 2*edge_cleanup + 2mm fudge
_cleanup = wc.TOOLING["edge_cleanup"]
_widths = sorted({round(w, 1) for _, _, w in HW})  # {45, 102}
check(_widths == [45, 102], "the HW fixture has exactly two distinct profiles")
_wide_w = (sum(w + wc.OVERSIZE for w in _widths)
           + wc.KERF * (len(_widths) - 1) + 2.0 * _cleanup + 2.0)
check(approx(osh.recommended.buy[0]["min_width"], _wide_w, 0.01),
      "wide-boards min_width == sum(w+oversize) + kerf*(n-1) + 2*cleanup + 2")

print("-- hardwood: narrow-board min_width matches the per-profile formula --")
# Each narrow-board buy line: min_width = w + oversize + 2*edge_cleanup + 2mm.
_narrow_by_width = {b["min_width"]: True for b in narrow.buy}
for w in _widths:
    expected = w + wc.OVERSIZE + 2.0 * _cleanup + 2.0
    check(any(approx(mw, expected, 0.01) for mw in _narrow_by_width),
          "narrow-board min_width for the %gmm profile == w+oversize+2*cleanup+2"
          % w)

print("-- hardwood: board_feet is consistent with the actual board width bought "
      "(min_width), not the bare profile width --")
_wide_L = osh.recommended.buy[0]["length"]
_wide_n = osh.recommended.buy[0]["count"]
_nom_thick = wc._quarter_inch("4/4") * IN
_expected_wide_bf = _wide_n * wc.board_feet(_nom_thick, _wide_w, _wide_L)
check(approx(osh.recommended.board_feet, _expected_wide_bf, 0.05),
      "wide-boards board_feet == n * board_feet(thick, min_width, length)")
_expected_narrow_bf = 0.0
for b in narrow.buy:
    _expected_narrow_bf += b["count"] * wc.board_feet(_nom_thick, b["min_width"],
                                                       b["length"])
check(approx(narrow.board_feet, _expected_narrow_bf, 0.05),
      "narrow-boards board_feet sums n*board_feet(thick, that line's min_width, "
      "length) per buy line")

print("-- hardwood: a single-profile-width input skips the narrow-board option "
      "(it would equal the wide one) --")
_one_width = [("A", 1000, 100), ("B", 1200, 100)]
_os_one = wc.source_options(_one_width, "hardwood", thickness="4/4")
check("narrow boards" not in labels(_os_one),
      "only one distinct profile width -> no separate narrow-board option")
check("wide boards" in labels(_os_one),
      "the single-width case still gets a wide-board option")

print("-- hardwood: thickness=None defaults to the material's first quarter --")
_os_default_t = wc.source_options(HW, "hardwood", prefer="value")
check(_os_default_t.recommended.buy[0]["nominal"] == wc.MATERIALS["hardwood"]
      ["thicknesses"][0],
      "an unspecified thickness defaults to spec['thicknesses'][0] (4/4)")

print("-- hardwood: a part longer than the longest board is flagged --")
osl = wc.source_options([("toolong", 13 * FT, 100)], "hardwood", thickness="4/4")
check(len(osl.flagged) == 1 and "longer" in osl.flagged[0][1],
      "a 13ft profile exceeds the 12ft max stock and is flagged")


# --- sourcing options: sheet -------------------------------------------------

SKINS = [("Skin", 1920, 960), ("Rib0", 1900, 82), ("Shelf", 1820, 860)]

print("-- sheet: nests onto the quality's sheet size, annotates transport --")
osp = wc.source_options(SKINS, "pine-ply", thickness="3/4", prefer="value")
check(osp.recommended is not None and osp.recommended.buy[0]["nominal"] == "4x8",
      "pine-ply nests onto 4x8")
check(osp.recommended.sheet_count is not None and osp.recommended.board_feet
      is None, "a sheet option counts sheets, not board-feet")
check(any("store-cut in half" in a for a in osp.recommended.annotations),
      "a full 4x8 is annotated as store-cuttable, not forced")

print("-- sheet: plywood rotates freely; grain is an opt-in cosmetic lock --")
tall = [("post", 300, 1400)]  # too long for the 4ft cross axis unless rotated
check(not wc.source_options(tall, "pine-ply", thickness="3/4").flagged,
      "cross-laminated plywood rotates to fit -- no grain lock by default")
check(not wc.source_options(tall, "mdf", thickness="3/4").flagged,
      "grainless MDF rotates the same part to fit too")
# Opting into a face-grain lock keeps the veneer one way and refuses the rotate.
wc.MATERIALS["_veneer"] = wc.sheet([(8 * FT, 4 * FT, "4x8")], grain=True,
                                   thicknesses=["3/4"], tier="$$", quality=3)
check(wc.source_options(tall, "_veneer", thickness="3/4").flagged,
      "grain=True keeps a show veneer and will not rotate the part")
del wc.MATERIALS["_veneer"]

print("-- sheet: rotation is honoured PER PART (grain pin on one part) --")
# 4-tuples carry a per-part rot flag; the same part pinned vs free.
pinned = [("p", 300, 1400, False)]  # too long for the 4ft cross, cannot rotate
freed = [("p", 300, 1400, True)]
check(wc.source_options(pinned, "pine-ply", thickness="3/4").flagged,
      "a grain-pinned part will not rotate and is flagged when it won't fit")
check(not wc.source_options(freed, "pine-ply", thickness="3/4").flagged,
      "the same part with rotation allowed fits")
# A mix in one group: the free one nests, the pinned one flags — both handled.
mixed = wc.source_options([("free", 300, 1400, True), ("pin", 300, 1400, False)],
                          "pine-ply", thickness="3/4")
check(len(mixed.flagged) == 1 and mixed.flagged[0][0] == "pin",
      "mixed rotatability in one group: only the pinned misfit is flagged")

print("-- sheet: a part bigger than the quality's sheet is flagged --")
osb = wc.source_options(SKINS, "birch-ply", thickness="3/4")
check(any("Skin" == n for n, _ in osb.flagged),
      "the 1920mm skin does not fit a 5x5 Baltic sheet and is flagged")


# --- registry ----------------------------------------------------------------

print("-- registry: the catalog is a plain, inspectable dict --")
check(wc.MATERIALS["framing"]["family"] == "dimensional",
      "framing is a dimensional material")
check(wc.MATERIALS["hardwood"]["family"] == "solidwood",
      "hardwood is sold as solid wood (board-foot)")
check(wc.MATERIALS["birch-ply"]["sizes"][0][2] == "5x5",
      "Baltic birch is a 5x5 sheet")
check(wc.TOOLING["jointer"] == 0.0,
      "the default tooling profile has no jointer (table saw only)")
check(all(wc.MATERIALS[mat]["grain"] is False
          for mat in ("mdf", "pine-ply", "birch-ply", "solid-core", "laminate")),
      "every stocked sheet good defaults grain-agnostic (plywood is cross-laminated)")

print("-- registry: a per-call override doesn't mutate the shared global --")
# The big skin does not fit a 5x5 Baltic sheet but does fit a full 4x8; a
# per-call registry override swaps birch's sizes for THIS call only.
_skin = [("Skin", 2000, 1000)]
_before = list(wc.MATERIALS["birch-ply"]["sizes"])
check(wc.source_options(_skin, "birch-ply", thickness="3/4").flagged,
      "with the default 5x5 catalog the 2000mm skin is flagged")
_reg = dict(wc.MATERIALS)
_reg["birch-ply"] = {**wc.MATERIALS["birch-ply"],
                     "sizes": [(8 * FT, 4 * FT, "4x8")]}
_over = wc.source_options(_skin, "birch-ply", thickness="3/4", registry=_reg)
check(not _over.flagged and _over.recommended.buy[0]["nominal"] == "4x8",
      "the override nests it onto a 4x8 for this call")
check(wc.MATERIALS["birch-ply"]["sizes"] == _before,
      "and the shared MATERIALS registry is untouched")


# --- summary -----------------------------------------------------------------

print()
print("wwcut: %d passed, %d failed" % (_PASS, _FAIL))
sys.exit(1 if _FAIL else 0)
