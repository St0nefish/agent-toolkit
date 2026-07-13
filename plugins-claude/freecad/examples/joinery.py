"""Joinery reference: real lumber, real joints, imperial input.

A small shelf unit. Two 1x10 sides stand upright, dado-ed on their inner faces
to take three 1x10 shelves, with a rabbet down each inner back edge for a ply
back, and a 2x2 stretcher mortised and tenoned into the sides at the top.

The point of this file is that none of the numbers are nominal. A "1x10" is
3/4" x 9-1/4"; "3/4" ply is 23/32". Model the nominal sizes and you get a design
that will not go together — and `check_clashes()` will tell you so.

    fcrun    examples/joinery.py
    fclive -b examples/joinery.py
"""

import os
import sys

sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww  # noqa: E402

ww.UNITS = "both"  # metric shop, imperial lumberyard

# --- parameters ---------------------------------------------------------
STOCK = "1x10"
HEIGHT = ww.inch(36)
WIDTH = ww.inch(24)      # outside to outside
SHELVES = 3
BACK = "1/4"             # ply thickness key
FIT = 0.4                # dado cut wider than the shelf, so it seats
TENON = ww.inch("1/2")   # how far the stretcher tenon enters the side

T, DEPTH = ww.LUMBER[STOCK]   # 3/4" thick, 9-1/4" wide
BACK_T = ww.PLY[BACK]
DADO = T / 2.0                # half the stock thickness, the usual rule
OUT = os.environ.get("WW_OUT", os.getcwd())

m = ww.Model("shelf-unit")

# --- sides: upright, thickness across X, depth along Y, height up Z ------
left = m.board("Side_Left", STOCK, HEIGHT, at=(0, 0, 0),
               length_axis="z", thickness_axis="x")
right = m.board("Side_Right", STOCK, HEIGHT, at=(WIDTH - T, 0, 0),
                length_axis="z", thickness_axis="x")

# Inner faces look at each other.
INNER = {"Side_Left": "+x", "Side_Right": "-x"}

# --- shelves, housed in dados -------------------------------------------
spacing = HEIGHT / (SHELVES + 1)
heights = [spacing * (i + 1) for i in range(SHELVES)]
span = WIDTH - 2 * T + 2 * DADO  # reaches DADO deep into each side

for side in (left, right):
    for z in heights:
        m.dado(side, face=INNER[side.name], along="y",
               pos=z, width=T + FIT, depth=DADO)
    # Rabbet down the inner back edge to receive the ply back.
    m.rabbet(side, face=INNER[side.name], edge="+y",
             width=BACK_T, depth=DADO)

# Shelves are ripped narrower so they stop in front of the back panel.
SHELF_DEPTH = DEPTH - BACK_T
for i, z in enumerate(heights):
    m.board("Shelf_%d" % i, STOCK, span, at=(T - DADO, 0, z),
            length_axis="x", thickness_axis="z", rip=SHELF_DEPTH)

# --- back panel, sitting in the rabbets ---------------------------------
# Thickness on Y, not Z: a back panel is thin front-to-back.
m.panel("Back", BACK, span, HEIGHT, at=(T - DADO, DEPTH - BACK_T, 0),
        thickness_axis="y")

# --- stretcher: tenoned into mortises in the sides -----------------------
TW, TT = ww.inch(1), ww.inch(1)  # tongue section, centred in the 2x2
st_len = WIDTH - 2 * T + 2 * TENON
st_z = HEIGHT - ww.inch(3)
stretcher = m.board("Stretcher", "2x2", st_len, at=(T - TENON, 0, st_z),
                    length_axis="x", thickness_axis="z")
m.tenon(stretcher, end="-x", size=(TW, TT), length=TENON)
m.tenon(stretcher, end="+x", size=(TW, TT), length=TENON)

sb = stretcher.bbox
for side in (left, right):
    m.mortise(side, face=INNER[side.name],
              at=(sb.YMin + (ww.LUMBER["2x2"][1] - TW) / 2.0, sb.ZMin + (ww.LUMBER["2x2"][0] - TT) / 2.0),
              size=(TW, TT), depth=TENON)

# --- report + write ------------------------------------------------------
m.check_clashes()
m.envelope()
m.cutlist()
# Transport: a Tacoma bed with the tailgate down takes about 8ft, no more.
# Sheet goods come home as halves — the store cuts them.
m.cutplan(max_length=ww.ft(8), sheet_piece="half")
m.finish(OUT)
