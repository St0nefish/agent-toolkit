"""Mixed-material reference model: plywood panels held by printed corners.

Run it:
    fcrun    examples/bracket-box.py     # validate + export, no GUI
    fclive -b examples/bracket-box.py    # watch it, rebuild as you edit
    fcsnap   examples/bracket-box.py     # read the live session back
    fcrender out/bracket_box.FCStd       # PNGs

Every number worth arguing about is at the top.
"""

import os
import sys

sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww  # noqa: E402

# --- parameters ---------------------------------------------------------
W, D, H = 300.0, 200.0, 150.0  # outer envelope
SHEET = "3/4"                  # plywood, actual thickness from ww.PLY
CLEAR = 0.4                    # total slot clearance over the ply (0.2/side)
POST = 30.0                    # bracket cross-section
BH = 50.0                      # bracket height (two per corner)
GROOVE = 8.0                   # depth a panel seats into a bracket
EDGE = 6.0                     # bracket setback from top/bottom

PLY = ww.PLY[SHEET]            # 23/32", not 3/4" — nominal sizes are lies
SLOT = PLY + CLEAR
OUT = os.environ.get("WW_OUT", os.getcwd())

m = ww.Model("bracket-box")

# --- printed corner bracket ---------------------------------------------
# Two perpendicular grooves, opening toward the box interior.
bracket = ww.solid(POST, POST, BH)
bracket = bracket.cut(ww.solid(GROOVE, SLOT, BH, at=(POST - GROOVE, 0, 0)))
bracket = bracket.cut(ww.solid(SLOT, GROOVE, BH, at=(0, POST - GROOVE, 0)))

m.check_printable(bracket, "bracket")

for i, ((cx, cy), rot) in enumerate(
    [((0, 0), 0), ((W, 0), 90), ((W, D), 180), ((0, D), 270)]
):
    for tag, z in (("lo", EDGE), ("hi", H - EDGE - BH)):
        m.place("Bracket_%d%s" % (i, tag), bracket, at=(cx, cy, z), rot_z=rot)

# --- plywood panels ------------------------------------------------------
# Each spans between brackets and seats GROOVE deep into each.
inset = POST - GROOVE
m.box("Panel_Front", W - 2 * inset, PLY, H, at=(inset, 0, 0))
m.box("Panel_Back", W - 2 * inset, PLY, H, at=(inset, D - PLY, 0))
m.box("Panel_Left", PLY, D - 2 * inset, H, at=(0, inset, 0))
m.box("Panel_Right", PLY, D - 2 * inset, H, at=(W - PLY, inset, 0))

# --- report + write ------------------------------------------------------
m.check_clashes()
m.envelope()
m.cutlist()
m.filament()
m.finish(OUT)
