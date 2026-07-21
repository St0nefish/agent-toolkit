"""Headless integration probe for Model.cutplan (the wwkit <-> wwcut wiring).

Run inside FreeCAD by tests/freecad/test-cutplan-integration.sh. Asserts on the
cut plan written to $WW_LOG: per-part oversize, stock grouping, preference
escalation with a note, and flag aggregation for parts that can't meet limits.
Any assertion failure raises -> fcrun reports it and the suite fails. On success
the last line of the log is "PROBE OK".
"""
import os
import sys

sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww  # noqa: E402

ww.UNITS = "mm"  # predictable numbers for substring assertions

m = ww.Model("cutplan_probe")

# Two identical 2x4 boards, one at default oversize and one exempted, plus a
# board too long to carry home.
m.board("Def", "2x4", 600.0, length_axis="x")
m.board("Exempt", "2x4", 600.0, at=(0, 200, 0), length_axis="x", oversize=0.0)
m.board("TooLong", "2x4", 3000.0, at=(0, 400, 0), length_axis="x")

# Sheet goods: two smalls that fit a half, a skin that must escalate to a full,
# and a giant that fits no stocked sheet at all.
m.panel("S1", "3/4", 500.0, 400.0)
m.panel("S2", "3/4", 500.0, 400.0, at=(0, 600, 0))
m.panel("Skin", "3/4", 1900.0, 950.0, at=(0, 1200, 0))
m.panel("Giant", "3/4", ww.ft(9), ww.ft(9), at=(0, 2400, 0))

# A custom-shaped part declared as linear strip stock, and a laminate as a sheet:
# both must be *planned*, not dropped as unplannable box() shapes.
m.strip("HW_Cleat", ww.prism([(0, 0), (14, 0), (0, 14)], 700.0, along="x"),
        stock="Hardwood")
m.box("Laminate", 900.0, 500.0, 1.2, at=(0, 3600, 0), form="sheet", stock="Formica")

buy = m.cutplan(max_length=ww.ft(8), sheet_piece="half", oversize=3.0)

m.finish(os.environ.get("WW_OUT", os.getcwd()))

log = open(os.environ["WW_LOG"]).read()


def want(cond, why):
    if not cond:
        raise AssertionError("cutplan probe: " + why)


# Per-part oversize wiring: default board grows by 3mm in length, exempt does not.
want("Def (603.0" in log, "default board length should be 603.0 (600 + 3 oversize)")
want("Exempt (600.0" in log, "exempt board length should stay 600.0")

# Preference escalation: the skin cannot ride a half, so it is upgraded to a full
# sheet and the plan says so, naming it.
want("NOTE" in log and "Skin" in log,
     "the escalated skin should produce a NOTE naming it")

# Flag aggregation: both impossible parts are called out, plan still produced.
want("FLAGGED" in log, "there should be a FLAGGED section")
want("TooLong" in log, "the over-long board should be flagged")
want("Giant" in log, "the over-size panel should be flagged")

# Custom-shaped parts declared with a stock get planned in their own group.
want("Hardwood  --" in log and "HW_Cleat" in log,
     "a strip()-declared hardwood part is planned as its own linear stock group")
want("Formica sheet  --" in log and "Laminate" in log,
     "a box(form='sheet') laminate is planned as a sheet group")

# The rest is still bought.
want(bool(buy), "cutplan should still return a non-empty buy list")
want("BUY" in log, "the plan should print a BUY line")

ww.say("PROBE OK")
