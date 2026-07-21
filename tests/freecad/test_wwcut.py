#!/usr/bin/env python3
"""Unit tests for wwcut — the cut-list optimizer and sourcing-option generator.

wwcut imports no FreeCAD/Part/Mesh, so it runs under a plain interpreter and is
CI-testable. Plain asserts, no pytest dependency. Exits non-zero on any failure.
"""

import os
import sys

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


# --- summary -----------------------------------------------------------------

print()
print("wwcut: %d passed, %d failed" % (_PASS, _FAIL))
sys.exit(1 if _FAIL else 0)
