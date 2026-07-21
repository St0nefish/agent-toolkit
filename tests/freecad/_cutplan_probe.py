"""Headless integration probe for Model.cutplan (the wwkit <-> wwcut wiring).

Run inside FreeCAD by tests/freecad/test-cutplan-integration.sh. Asserts on the
cut plan written to $WW_LOG: material grouping, per-part oversize, co-located
rips folded onto one blank (rip_with), from_scrap reporting, sourcing options
(recommended + "also works" alternatives), and flagging of impossible parts.
Any assertion failure raises -> fcrun reports it and the suite fails. On success
the last line of the log is "PROBE OK".
"""
import os
import sys

sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww  # noqa: E402

ww.UNITS = "mm"  # predictable numbers for substring assertions

m = ww.Model("cutplan_probe")

# framing: two short strips, one at default oversize and one exempted, plus a
# strip too wide for any framing nominal (must be flagged, not forced).
m.board("Def", 600.0, ww.inch(3.5), length_axis="x", material="framing")
m.board("Exempt", 600.0, ww.inch(3.5), at=(0, 200, 0), length_axis="x",
        material="framing", oversize=0.0)
m.board("Slab", 800.0, 400.0, at=(0, 400, 0), length_axis="x",
        material="framing")

# hardwood: a cleat and its interlocking key ride ONE blank (rip_with folds the
# key onto the cleat's stick — it must not be bought or flagged on its own).
cleat = ww.prism([(0, 0), (14, 0), (0, 14)], 700.0, along="x")
key = ww.prism([(0, 14), (13, 1), (13, 26), (0, 26)], 700.0, along="x")
m.strip("Cleat_F", cleat, material="hardwood", thickness="4/4")
m.strip("Key_F", key, material="hardwood", thickness="4/4", rip_with="Cleat_F")

# sheet goods: two ply panels (nest onto a 4x8) and a laminate facing.
m.panel("Ply1", 1200.0, 600.0, material="pine-ply", thickness="3/4")
m.panel("Ply2", 1200.0, 600.0, at=(0, 900, 0), material="pine-ply",
        thickness="3/4")
m.box("Lam", 900.0, 500.0, 1.2, at=(0, 1700, 0), material="laminate",
      thickness="1.2mm")

# a block cut from offcuts: reported, never bought.
m.box("Cap", 60.0, 60.0, 82.0, at=(0, 2500, 0), from_scrap=True)

results = m.cutplan(oversize=3.0)

m.finish(os.environ.get("WW_OUT", os.getcwd()))

log = open(os.environ["WW_LOG"]).read()


def want(cond, why):
    if not cond:
        raise AssertionError("cutplan probe: " + why)


# Material grouping: each type gets its own section header.
want("framing --" in log, "framing parts are grouped and headed")
want("hardwood 4/4 --" in log, "hardwood parts are grouped by thickness")
want("pine-ply 3/4 --" in log, "sheet goods are grouped by quality + thickness")
want("laminate 1.2mm --" in log, "the laminate is planned as its own sheet group")

# Per-part oversize wiring: default board grows 3mm in length, exempt does not.
want("Def (603.0" in log, "default board length should be 603.0 (600 + 3 oversize)")
want("Exempt (600.0" in log, "exempt board length should stay 600.0")

# Co-located rip: the key is folded onto the cleat's blank (one combined part),
# never listed as its own buy.
want("Cleat_F+Key_F" in log, "the key rides the cleat's blank as one folded part")

# Sourcing options: framing shows the exact-nominal 2x4 recommended plus at least
# one rip alternative.
want("2x4" in log, "the recommended framing option is the 2x4")
want("also works" in log, "at least one alternative sourcing option is offered")

# from_scrap reporting: reported, never in the BUY line.
want("FROM SCRAP" in log and "Cap" in log, "the scrap block is reported")

# Flagging: the over-wide framing strip is flagged, the rest still planned.
want("Slab" in log and "wider" in log, "the 400mm strip has no nominal -> flagged")

# The rest is bought and returned.
want(bool(results), "cutplan returns the list of option sets")
want("BUY" in log, "the plan prints a BUY line")

ww.say("PROBE OK")
