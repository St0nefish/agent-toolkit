"""Headless integration probe for the Model surface that _cutplan_probe.py does
not touch: joinery primitives, checks (clashes/printable/gap/envelope),
filament, multi-rider rip_with folding, and imperial unit formatting.

Run inside FreeCAD by tests/freecad/test-model.sh. Any assertion failure
raises -> fcrun reports it and the suite fails. On success the last line of
the log is "MODEL PROBE OK".
"""
import math
import os
import sys

sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww  # noqa: E402

ww.UNITS = "mm"

IN = ww.IN


def want(cond, why):
    if not cond:
        raise AssertionError("model probe: " + why)


def approx(a, b, tol):
    return abs(a - b) <= tol


# ==========================================================================
# 1. Joinery primitives: each op must remove material. Boards/panels are laid
#    out far apart (large x offsets) so nothing in this model accidentally
#    clashes with anything else -- that is check_clashes' job, tested below
#    on its own model.
# ==========================================================================

mj = ww.Model("joinery_probe")

# -- trench: a channel across the full extent of `along`, `width` wide on the
# remaining axis, `depth` deep from `face`.
j_trench = mj.board("J_Trench", 600.0, 100.0, at=(0, 0, 0), length_axis="x",
                    thickness_axis="z", material="framing")
v0 = j_trench.shape.Volume
mj.trench(j_trench, face="+z", along="y", pos=200.0, width=50.0, depth=10.0)
removed = v0 - j_trench.shape.Volume
want(approx(removed, 100.0 * 50.0 * 10.0, 1.0),
     "trench removes along_extent(y=100) x width(50) x depth(10) = 50000 mm^3, "
     "got %.1f" % removed)

# -- trench's own validation: bad face string, and along == the face's axis.
try:
    mj.trench(j_trench, face="+q", along="y", pos=0.0, width=10.0, depth=5.0)
    want(False, "trench(face='+q') should have raised ValueError")
except ValueError:
    pass

# A single-character face used to slip past validation into an IndexError.
try:
    mj.trench(j_trench, face="q", along="y", pos=0.0, width=10.0, depth=5.0)
    want(False, "trench(face='q') should have raised ValueError")
except ValueError:
    pass
except Exception as exc:
    want(False, "trench(face='q') raised %r, wanted ValueError" % exc)

try:
    mj.trench(j_trench, face="+z", along="z", pos=0.0, width=10.0, depth=5.0)
    want(False, "trench(along==face axis) should have raised ValueError")
except ValueError:
    pass

# -- dado: a trench wrapper, same geometry.
j_dado = mj.board("J_Dado", 600.0, 100.0, at=(0, 300, 0), length_axis="x",
                  thickness_axis="z", material="framing")
v0 = j_dado.shape.Volume
mj.dado(j_dado, face="+z", along="y", pos=150.0, width=18.0, depth=9.5)
removed = v0 - j_dado.shape.Volume
want(approx(removed, 100.0 * 18.0 * 9.5, 1.0),
     "dado removes along_extent(y=100) x width(18) x depth(9.5) = 17100 mm^3, "
     "got %.1f" % removed)

# -- rabbet: a step flush against one edge.
j_rabbet = mj.board("J_Rabbet", 600.0, 100.0, at=(0, 600, 0), length_axis="x",
                    thickness_axis="z", material="framing")
v0 = j_rabbet.shape.Volume
mj.rabbet(j_rabbet, face="+z", edge="+x", width=20.0, depth=10.0)
removed = v0 - j_rabbet.shape.Volume
want(approx(removed, 100.0 * 20.0 * 10.0, 1.0),
     "rabbet removes the full y-extent(100) x width(20) x depth(10) = 20000 "
     "mm^3, got %.1f" % removed)

# -- mortise: a blind rectangular pocket.
j_mortise = mj.board("J_Mortise", 600.0, 100.0, at=(0, 900, 0),
                     length_axis="x", thickness_axis="z", material="framing")
v0 = j_mortise.shape.Volume
# `at`/`size` are absolute coordinates (x, y here, since face="+z" leaves x,y
# free); the board itself was built at y-offset 900, so the mortise's y must
# be offset the same way.
mj.mortise(j_mortise, face="+z", at=(250.0, 930.0), size=(40.0, 30.0),
          depth=12.0)
removed = v0 - j_mortise.shape.Volume
want(approx(removed, 40.0 * 30.0 * 12.0, 1.0),
     "mortise removes size(40x30) x depth(12) = 14400 mm^3, got %.1f" % removed)

# -- tenon: reduces a board end to a tongue by cutting 4 shoulders.
j_tenon = mj.board("J_Tenon", 300.0, 80.0, at=(0, 1200, 0), length_axis="x",
                   thickness_axis="z", material="framing")
v0 = j_tenon.shape.Volume
mj.tenon(j_tenon, end="+x", size=(40.0, 15.0), length=25.0)
removed = v0 - j_tenon.shape.Volume
# board thickness (z) is the framing actual thickness, 1.5in = 38.1mm.
thick = ww.LUMBER["2x4"][0]
want(approx(thick, 38.1, 0.1), "sanity: framing actual thickness is 38.1mm")
expected_tenon = 25.0 * 80.0 * thick - 25.0 * 40.0 * 15.0
want(approx(removed, expected_tenon, 2.0),
     "tenon removes end_block - tongue_block = %.1f mm^3, got %.1f"
     % (expected_tenon, removed))

# -- hole: a cylindrical blind bore.
j_hole = mj.board("J_Hole", 300.0, 80.0, at=(0, 1500, 0), length_axis="x",
                  thickness_axis="z", material="framing")
v0 = j_hole.shape.Volume
# `at` is absolute; the board was built at y-offset 1500.
mj.hole(j_hole, at=(50.0, 1540.0, thick), dia=10.0, depth=20.0, axis=(0, 0, -1))
removed = v0 - j_hole.shape.Volume
want(approx(removed, math.pi * 5.0 * 5.0 * 20.0, 5.0),
     "hole removes pi*r^2*depth = %.1f mm^3, got %.1f"
     % (math.pi * 5.0 * 5.0 * 20.0, removed))

# -- notch: the raw primitive, subtract a box in absolute coordinates.
j_notch = mj.board("J_Notch", 300.0, 80.0, at=(0, 1800, 0), length_axis="x",
                   thickness_axis="z", material="framing")
v0 = j_notch.shape.Volume
# `at` is absolute; the board was built at y-offset 1800.
mj.notch(j_notch, size=(50.0, 30.0, 10.0), at=(100.0, 1820.0, thick - 10.0))
removed = v0 - j_notch.shape.Volume
want(approx(removed, 50.0 * 30.0 * 10.0, 1.0),
     "notch removes exactly its box, 15000 mm^3, got %.1f" % removed)

# -- a joint on a panel (sheet goods), not just a board.
ply_t = ww.SHEET_ACTUAL["pine-ply"]["3/4"]
j_panel = mj.panel("J_PanelTrench", 800.0, 400.0, at=(0, 2100, 0),
                   thickness_axis="z", material="pine-ply", thickness="3/4")
v0 = j_panel.shape.Volume
# `pos` is absolute on the "third" axis (y here); the panel was built at
# y-offset 2100.
mj.trench(j_panel, face="+x", along="z", pos=2200.0, width=60.0, depth=8.0)
removed = v0 - j_panel.shape.Volume
want(approx(removed, ply_t * 60.0 * 8.0, 1.0),
     "trench into a panel's edge removes thickness x width(60) x depth(8) = "
     "%.1f mm^3, got %.1f" % (ply_t * 60.0 * 8.0, removed))

ww.say("JOINERY   all seven primitives (+panel) removed the expected volume")


# ==========================================================================
# 2. Checks: check_clashes, check_printable, gap, envelope. A small, isolated
#    model so the pair-by-pair clash search has a known, hand-countable
#    answer.
# ==========================================================================

mc = ww.Model("checks_probe")

ov_a = mc.box("Ov_A", 100.0, 100.0, 100.0, at=(0, 0, 0))
ov_b = mc.box("Ov_B", 100.0, 100.0, 100.0, at=(50, 50, 50))
dj_a = mc.box("Dj_A", 50.0, 50.0, 50.0, at=(1000, 0, 0))
dj_b = mc.box("Dj_B", 50.0, 50.0, 50.0, at=(1000, 200, 0))

want(mc.check_printable(ov_a) is True,
     "a plain, valid solid box is printable")

clashes = mc.check_clashes()
want(len(clashes) == 1, "exactly one clashing pair among these four parts, "
     "got %d" % len(clashes))
want(clashes[0][0] == "Ov_A" and clashes[0][1] == "Ov_B",
     "the clashing pair is (Ov_A, Ov_B), got %r" % (clashes[0],))
want(approx(clashes[0][2], 50.0 * 50.0 * 50.0, 1.0),
     "the overlap volume is the 50x50x50 shared cube = 125000 mm^3, got %.1f"
     % clashes[0][2])

env = mc.envelope()
want(env is not None, "envelope() returns a bbox for a non-empty model")
want(approx(env[0], 1050.0, 0.5) and approx(env[1], 250.0, 0.5)
     and approx(env[2], 150.0, 0.5),
     "envelope should be 1050 x 250 x 150 (spanning Ov_A/Ov_B and Dj_A/Dj_B), "
     "got %s" % (env,))

g_overlap = mc.gap(ov_a, ov_b)
want(g_overlap == -1.0, "gap() on overlapping parts returns -1.0, got %r"
     % g_overlap)

g_apart = mc.gap(dj_a, dj_b)
want(approx(g_apart, 150.0, 0.5),
     "Dj_A and Dj_B are 150mm apart in y, gap() should say so, got %.1f"
     % g_apart)

want(mc.filament() == 0.0, "filament() on a model with no printed parts is 0.0")

ww.say("CHECKS    clashes/printable/gap/envelope all matched hand-computed "
      "expectations")


# ==========================================================================
# 3. filament(): a model WITH a printed part exercises the real branch.
# ==========================================================================

mf = ww.Model("filament_probe")
mf.add("PrintedCube", ww.solid(20.0, 20.0, 20.0), kind="printed")

grams = mf.filament()
expected_g = (20.0 * 20.0 * 20.0 / 1000.0) * ww.PLA_DENSITY
want(grams > 0.0, "filament() with a printed part returns grams > 0")
want(approx(grams, expected_g, 0.1),
     "a 20mm cube in PLA is %.2fg, got %.2fg" % (expected_g, grams))

flog = open(os.environ["WW_LOG"]).read()
want("FILAMENT" in flog, "filament() logs a FILAMENT line")

ww.say("FILAMENT  printed-part branch returns %.2fg (expected %.2fg)"
      % (grams, expected_g))


# ==========================================================================
# 4. Multi-rider rip_with: a bearer with TWO riders folds onto one blank, and
#    the folded width accumulates both riders + a kerf each.
# ==========================================================================

mr = ww.Model("rider_probe")

bearer_shape = ww.prism([(0, 0), (50, 0), (0, 20)], 700.0, along="x")
riderA_shape = ww.prism([(0, 0), (30, 0), (0, 15)], 700.0, along="x")
riderB_shape = ww.prism([(0, 0), (25, 0), (0, 12)], 700.0, along="x")

mr.strip("Bearer", bearer_shape, material="hardwood", thickness="4/4")
mr.strip("RiderA", riderA_shape, material="hardwood", thickness="4/4",
         rip_with="Bearer")
mr.strip("RiderB", riderB_shape, material="hardwood", thickness="4/4",
         rip_with="Bearer")

rresults = mr.cutplan(oversize=3.0)
rlog = open(os.environ["WW_LOG"]).read()

want("Bearer+RiderA+RiderB" in rlog,
     "both riders fold onto the bearer's blank as one combined part name")

hw_opt = next(o for o in rresults
             if o.material == "hardwood" and o.thickness == "4/4")
want(hw_opt.recommended is not None, "the folded blank still produces a plan")
want(len(hw_opt.recommended.buy) == 1,
     "the bearer + 2 riders are ONE buy line (one blank), not three")

# Expected board width: bearer width(50) + riderA(30) + kerf + riderB(25) +
# kerf, then the hardwood wide-board formula's own +2*edge_cleanup+2mm fudge
# (single profile width -> no extra rip-kerf term in that formula itself).
kerf = 3.2  # wwcut.KERF
cleanup = 0.25 * IN  # wwcut.TOOLING["edge_cleanup"]
folded_width = 50.0 + (30.0 + kerf) + (25.0 + kerf)
expected_min_width = folded_width + 2.0 * cleanup + 2.0
got_min_width = hw_opt.recommended.buy[0]["min_width"]
want(approx(got_min_width, expected_min_width, 0.1),
     "folded blank min_width should be %.2f (bearer+riderA+riderB+2*kerf, then "
     "+2*cleanup+2), got %.2f" % (expected_min_width, got_min_width))

ww.say("RIP_WITH  multi-rider fold: name=%s min_width=%.2f (expected %.2f)"
      % ("Bearer+RiderA+RiderB", got_min_width, expected_min_width))


# ==========================================================================
# 5. Imperial formatting: UNITS="in" and UNITS="both" render shop fractions,
#    since every other probe pins UNITS="mm" for substring matching.
# ==========================================================================

ww.UNITS = "in"
want(ww.fmt(914.4) == '36"',
     "914.4mm (exactly 36in) should render as 36\" under UNITS=in, got %r"
     % ww.fmt(914.4))
want(ww.fmt(38.1) == '1-1/2"',
     "38.1mm (exactly 1.5in) should render as 1-1/2\" under UNITS=in, got %r"
     % ww.fmt(38.1))
want(ww._frac(9.1875) == "9-3/16",
     "9.1875in (9 + 3/16) reduces to the shop fraction 9-3/16, got %r"
     % ww._frac(9.1875))
want(ww._frac(9.96875) == "10",
     "9.96875in rounds up to the whole number 10 (num==denom carry), got %r"
     % ww._frac(9.96875))

ww.UNITS = "both"
want(ww.fmt(914.4) == '914.4 (36")',
     "UNITS=both shows metric with the imperial fraction in parens, got %r"
     % ww.fmt(914.4))

ww.UNITS = "mm"
want(ww.fmt(914.4) == "914.4", "UNITS=mm is the plain metric number")

# fmt_stock: round feet render as "N ft"; anything else falls back to mm.
want(ww.fmt_stock(2438.4) == "8 ft", "8ft of stock renders as '8 ft'")
want(ww.fmt_stock(2425.7) == "2426 mm" or ww.fmt_stock(2425.7).endswith(" mm"),
     "a non-round-feet length falls back to '%.0f mm'")

ww.say("IMPERIAL  fmt/_frac/fmt_stock all matched hand-computed shop fractions")


# ==========================================================================
# Lower priority: say() ASCII-stripping, cutlist() returns rows.
# ==========================================================================

ww.say("café — mdf, naïve façade")
final_log = open(os.environ["WW_LOG"]).read()
last_lines = [ln for ln in final_log.splitlines() if ln.startswith("caf")]
want(bool(last_lines), "the non-ASCII say() call logged a line at all")
want(all(ord(c) < 128 for c in last_lines[-1]),
     "say() strips non-ASCII down to plain ASCII, got %r" % last_lines[-1])

mcl = ww.Model("cutlist_probe")
mcl.board("CL_A", 500.0, 100.0, material="framing")
mcl.panel("CL_B", 400.0, 300.0, at=(0, 200, 0), material="pine-ply",
         thickness="3/4")
rows = mcl.cutlist()
want(len(rows) == 2, "cutlist() returns one row per wood part, got %d"
     % len(rows))
want({r[0] for r in rows} == {"CL_A", "CL_B"},
     "cutlist rows are keyed by part name")
# empty-of-wood model returns []
mcl_empty = ww.Model("cutlist_empty_probe")
mcl_empty.add("JustPrinted", ww.solid(10, 10, 10), kind="printed")
want(mcl_empty.cutlist() == [], "a model with no wood parts returns []")

ww.say("CUTLIST   %d row(s), say() ASCII-stripped correctly" % len(rows))

ww.say("MODEL PROBE OK")
