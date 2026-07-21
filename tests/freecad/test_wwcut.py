#!/usr/bin/env python3
"""Unit tests for wwcut — the cut-list optimizer.

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


# --- boards -----------------------------------------------------------------

print("-- boards: basic FFD --")
plan = wc.plan_linear([("a", 600), ("b", 600), ("c", 600), ("d", 430)],
                      end_trim=0.0)
check(len(plan) == 1, "four short parts pack into one board")
check(approx(plan[0].length, 8 * FT), "and it is the 8ft, not a longer stock")
check(sum(len(b.cuts) for b in plan) == 4, "every part is placed exactly once")

print("-- boards: kerf is consumed --")
# Pin the catalog to a single 8ft so the only lever is kerf (otherwise the
# planner legitimately buys one longer board to hold both halves).
half = 8 * FT / 2.0
eightft = [8 * FT]
p0 = wc.plan_linear([("a", half), ("b", half)], board_lengths=eightft,
                    kerf=0.0, end_trim=0.0)
p1 = wc.plan_linear([("a", half), ("b", half)], board_lengths=eightft,
                    kerf=3.2, end_trim=0.0)
check(len(p0) == 1, "two exact-half parts fit one 8ft with no kerf")
check(len(p1) == 2, "the same two need a second 8ft once kerf is counted")

print("-- boards: end-trim shrinks usable length --")
p_notrim = wc.plan_linear([("long", 2420)], end_trim=0.0)
p_trim = wc.plan_linear([("long", 2420)], end_trim=1 * IN)
check(approx(p_notrim[0].length, 8 * FT), "2420mm part uses an 8ft with no trim")
check(approx(p_trim[0].length, 10 * FT),
      "the same part needs a 10ft once 1in is squared off each end")
check(p_trim[0].offcut < p_trim[0].usable,
      "offcut is measured against the trimmed usable length")

print("-- boards: transport limit flags, does not crash --")
lim = wc.plan_linear([("x", 2500), ("ok", 600)], max_length=8 * FT, end_trim=0.0)
check(len(lim.flagged) == 1 and lim.flagged[0][0] == "x",
      "the over-limit part is flagged, not forced into an impossible plan")
check("transport limit" in lim.flagged[0][2], "and the reason names the limit")
check(len(lim.boards) == 1, "the part that does fit is still planned")
check(all(b.length <= 8 * FT + 1e-6 for b in lim),
      "no board longer than the transport limit is offered")

print("-- boards: end-trim can outrun every stock length --")
big = wc.plan_linear([("huge", 16 * FT - 10), ("ok", 600)], end_trim=1 * IN)
check(len(big.flagged) == 1 and big.flagged[0][0] == "huge",
      "a part longer than the longest usable length is flagged")
check(len(big.boards) == 1, "the rest of the run is still planned")


# --- sheets -----------------------------------------------------------------

print("-- sheets: basic pack + grain --")
FOURBYEIGHT = (8 * FT, 4 * FT)
s = wc.plan_sheets([("panel", 1000, 300)], sheet=FOURBYEIGHT, edge_trim=0.0)
check(len(s) == 1, "one small panel fits one 4x8")

print("-- sheets: rotation is off by default (grain) --")
narrow = (1200, 1400)  # a piece narrower than the part is long
raises(lambda: wc.plan_sheets([("p", 1300, 1100)], sheet=narrow,
                              allow_rotate=False, edge_trim=0.0),
       "a part too long for the grain axis will not fit un-rotated")
rot = wc.plan_sheets([("p", 1300, 1100)], sheet=narrow, allow_rotate=True,
                     edge_trim=0.0)
check(len(rot) == 1, "the same part fits once rotation is allowed")

print("-- sheets: edge-trim shrinks usable face --")
tight = (2438, 1219)  # essentially fills a 4x8
ok = wc.plan_sheets([("p", 2438, 1219)], sheet=FOURBYEIGHT, edge_trim=0.0)
check(len(ok) == 1, "a face-filling panel fits with no edge trim")
raises(lambda: wc.plan_sheets([("p", 2438, 1219)], sheet=FOURBYEIGHT,
                              edge_trim=1 * IN),
       "the same panel no longer fits once 1in is trimmed off each edge")
_ = tight  # documented intent

print("-- sheets: multi-size catalog picks least material --")
# A 1400x1400 part cannot fit a 4x8 (only 4ft across) but fits a 5x5.
sp = wc.choose_sheets([("wide", 1400, 1400)], edge_trim=0.0)
check(sp.buys[0].sheet_name == "5x5", "over-wide part is bought as a 5x5")
# A 1200x1200 part fits both, but a 5x5 is less bought area.
sp2 = wc.choose_sheets([("mid", 1200, 1200)], edge_trim=0.0)
check(sp2.buys[0].sheet_name == "5x5", "when both fit, the smaller-area wins")

print("-- sheets: preferred transport piece --")
sph = wc.choose_sheets([("p", 500, 500)], prefer="half", edge_trim=0.0)
check(sph.buys[0].piece_name == "half", "prefer='half' uses a crosscut half")
check(sph.buys[0].full_sheets == 1 and sph.buys[0].spare_pieces == 1,
      "one half used of a full sheet leaves one spare half")

print("-- sheets: preference escalates, does not fail --")
# A group where small parts fit a half but the big skin needs a full sheet.
sp_esc = wc.choose_sheets(
    [("skin", 1900, 950), ("a", 500, 400), ("b", 500, 400)],
    prefer="half", max_length=8 * FT, edge_trim=0.0)
piece_names = {b.piece_name for b in sp_esc.buys}
check("full" in piece_names, "the oversized skin is upgraded to a full sheet")
check("half" in piece_names, "the small parts still ride the preferred half")
check(len(sp_esc.notes) == 1 and "skin" in sp_esc.notes[0],
      "the upgrade is called out in a note naming the part")
check(not sp_esc.flagged, "nothing is flagged — every part was planned")

print("-- sheets: yield is a sane fraction --")
spy = wc.choose_sheets([("p", 1200, 600)], sheet_sizes=[(8 * FT, 4 * FT, "4x8")],
                       prefer="full", edge_trim=0.0)
check(0.0 < spy.buys[0].yield_pct <= 100.0, "yield percentage is within (0, 100]")

print("-- sheets: impossible parts are flagged, the rest planned --")
sp_big = wc.choose_sheets([("giant", 9 * FT, 9 * FT), ("ok", 600, 400)],
                          edge_trim=0.0)
check(len(sp_big.flagged) == 1 and sp_big.flagged[0][0] == "giant",
      "a part bigger than every catalog sheet is flagged, not crashed on")
check("bigger than any stocked sheet" in sp_big.flagged[0][3],
      "and the reason says to split it")
check(len(sp_big.buys) == 1, "the part that fits is still bought and planned")

print("-- sheets: forced-half skin over transport limit is flagged --")
# max_length below a half's long axis: a part longer than every carriable piece.
sp_lim = wc.choose_sheets([("long", 1300, 300)],
                          sheet_sizes=[(8 * FT, 4 * FT, "4x8")],
                          max_length=1200.0, edge_trim=0.0)
check(len(sp_lim.flagged) == 1 and "transport limit" in sp_lim.flagged[0][3],
      "a part too big for any carriable piece is flagged with the limit")


# --- oversize: parts are cut rough and trimmed to final ----------------------

print("-- oversize: boards --")
p2 = wc.plan_linear([("y", 600)], board_lengths=[8 * FT], end_trim=0.0,
                    oversize=10.0)
check(approx(p2.boards[0].cuts[0][1], 610),
      "the planned board cut is the rough (final + oversize) length")
near = wc.plan_linear([("x", 2435)], board_lengths=[8 * FT], end_trim=0.0,
                      oversize=0.0)
rough = wc.plan_linear([("x", 2435)], board_lengths=[8 * FT], end_trim=0.0,
                       oversize=10.0)
check(len(near.boards) == 1 and not near.flagged,
      "a 2435mm final part fits an 8ft")
check(bool(rough.flagged),
      "cut 10mm oversize the same part no longer fits and is flagged")

print("-- oversize: sheets --")
s_ok = wc.plan_sheets([("p", 2430, 1200)], sheet=(8 * FT, 4 * FT),
                      edge_trim=0.0, oversize=0.0)
check(len(s_ok) == 1, "a near-full panel fits at final size")
raises(lambda: wc.plan_sheets([("p", 2430, 1200)], sheet=(8 * FT, 4 * FT),
                              edge_trim=0.0, oversize=20.0),
       "cut 20mm oversize the same panel overflows the sheet")
sp_ov = wc.choose_sheets([("p", 1000, 300)],
                         sheet_sizes=[(8 * FT, 4 * FT, "4x8")], prefer="full",
                         edge_trim=0.0, oversize=10.0)
rough_part = sp_ov.buys[0].pieces[0].strips[0]["parts"][0]
check(approx(rough_part[1], 1010) and approx(rough_part[2], 310),
      "sheet parts are packed and reported at rough (final + oversize) size")


# --- rectpack band reconstruction (engine-agnostic, no dependency needed) ----

print("-- bands: clean layout reconstructs --")
# two parts side by side in one rip, a third in a rip above it
good = [(0, 0.0, 0.0, 100.0, 50.0),
        (1, 100.0, 0.0, 100.0, 50.0),
        (2, 0.0, 50.0, 120.0, 40.0)]
bands = wc._bands_from_placements(good, 300.0, 100.0)
check(bands is not None and len(bands) == 2, "two clean rips reconstruct")
check(bands is not None and len(bands[0]["items"]) == 2,
      "the lower rip holds both side-by-side parts")

print("-- bands: overlaps and overflow are rejected --")
xoverlap = [(0, 0.0, 0.0, 100.0, 50.0), (1, 50.0, 0.0, 100.0, 50.0)]
check(wc._bands_from_placements(xoverlap, 300.0, 100.0) is None,
      "parts overlapping along a rip are rejected")
xoverflow = [(0, 0.0, 0.0, 400.0, 50.0)]
check(wc._bands_from_placements(xoverflow, 300.0, 100.0) is None,
      "a part wider than the sheet is rejected")
yoverlap = [(0, 0.0, 0.0, 100.0, 80.0), (1, 0.0, 50.0, 100.0, 40.0)]
check(wc._bands_from_placements(yoverlap, 300.0, 100.0) is None,
      "rips that overlap in depth are rejected")
yoverflow = [(0, 0.0, 0.0, 100.0, 50.0), (1, 0.0, 60.0, 100.0, 50.0)]
check(wc._bands_from_placements(yoverflow, 300.0, 100.0) is None,
      "rips that run past the sheet width are rejected")


# --- rectpack engine path: absent -> shelf fallback, no crash ----------------

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
sheets2, engine2 = wc._pack_one_size([("p", 1000, 300)], (8 * FT, 4 * FT), 3.2,
                                     False, 0.0, "shelf")
check(engine2 == "shelf", "explicit packer='shelf' uses the shelf engine")


# --- boards: extended -------------------------------------------------------

print("-- boards: cheapest single length across the catalog --")
# Three 1800mm parts: a 6ft holds one each (3 boards, 5.5m), every longer stock
# either holds one (more material) or two (fewer boards, still more material).
three = wc.plan_linear([("a", 1800), ("b", 1800), ("c", 1800)], end_trim=0.0)
check(approx(three[0].length, 6 * FT) and len(three) == 3,
      "the planner buys three 6ft, the least-material single length")

print("-- boards: no stock within the transport limit --")
none_fit = wc.plan_linear([("a", 600)], max_length=5 * FT)
check(not none_fit.boards and len(none_fit.flagged) == 1,
      "nothing is planned when no catalog board is carriable")
check("no stock length is within" in none_fit.flagged[0][2],
      "and the reason says so")

print("-- boards: empty input is empty, not an error --")
empty_b = wc.plan_linear([])
check(len(empty_b) == 0 and not empty_b.flagged, "no parts -> no boards, no flags")

print("-- boards: offcut is exact --")
one = wc.plan_linear([("a", 600)], board_lengths=[8 * FT], end_trim=0.0, kerf=3.2)
check(approx(one[0].offcut, 8 * FT - 600), "offcut = usable - used (no leading kerf)")


# --- sheets: strip geometry (regression for the length/kerf fix) ------------

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


# --- sheets: extended -------------------------------------------------------

print("-- sheets: half-rip piece --")
spr = wc.choose_sheets([("p", 2000, 300)], sheet_sizes=[(8 * FT, 4 * FT, "4x8")],
                       prefer="half-rip", max_length=8 * FT, edge_trim=0.0)
check(spr.buys[0].piece_name == "half-rip", "prefer='half-rip' rips a long strip")
check(spr.buys[0].per_full == 2 and spr.buys[0].spare_pieces == 1,
      "a full sheet yields two rips, one spare here")

print("-- sheets: allow_rotate flips a fit in choose_sheets --")
cat = [(1400, 600, "strip")]
no_rot = wc.choose_sheets([("p", 500, 1300)], sheet_sizes=cat,
                          allow_rotate=False, edge_trim=0.0)
yes_rot = wc.choose_sheets([("p", 500, 1300)], sheet_sizes=cat,
                           allow_rotate=True, edge_trim=0.0)
check(no_rot.flagged and not no_rot.buys, "grain-locked, the part does not fit")
check(yes_rot.buys and not yes_rot.flagged, "rotation allowed, it fits and is bought")

print("-- sheets: spare-piece math with an odd count of halves --")
odd = wc.choose_sheets(
    [("a", 1200, 1100), ("b", 1200, 1100), ("c", 1200, 1100)],
    sheet_sizes=[(8 * FT, 4 * FT, "4x8")], prefer="half", max_length=8 * FT,
    edge_trim=0.0)
check(len(odd.buys) == 1 and len(odd.buys[0].pieces) == 3,
      "three parts too big to share a half take three half pieces")
check(odd.buys[0].full_sheets == 2 and odd.buys[0].spare_pieces == 1,
      "three halves come from two full sheets, leaving one spare half")

print("-- sheets: default catalog + no preference picks least material --")
dfl = wc.choose_sheets([("p", 600, 400)], edge_trim=0.0)
check(dfl.buys[0].sheet_name == "5x5",
      "a small part is bought from the smaller-area 5x5")

print("-- sheets: empty input is empty, not an error --")
empty_s = wc.choose_sheets([])
check(not empty_s.buys and not empty_s.flagged, "no parts -> no buys, no flags")

print("-- engine: empty parts pack to nothing --")
es, _eng = wc._pack_one_size([], (8 * FT, 4 * FT), 3.2, False, 0.0, "auto")
check(es == [], "no parts -> no sheets")


# --- board feet -------------------------------------------------------------

print("-- board feet --")
bf = wc.board_feet(1.5 * IN, 3.5 * IN, 8 * FT)
check(approx(bf, 3.5, 0.01), "a 2x4x8 is 3.5 board feet")
bf2 = wc.board_feet(0.75 * IN, 5.5 * IN, 6 * FT)
check(approx(bf2, 2.0625, 0.01), "a 1x6x6 is ~2.06 board feet")


# --- summary ----------------------------------------------------------------

print()
print("wwcut: %d passed, %d failed" % (_PASS, _FAIL))
sys.exit(1 if _FAIL else 0)
