---
name: freecad-modeling
user-invocable: false
allowed-tools: Bash, Read, Write, Edit
description: >-
  Script parametric FreeCAD models (woodworking, 3D printing, mixed
  wood-and-printed assemblies) with a live GUI the user steers. Use when
  designing or editing a FreeCAD model, a .FCStd, a printable part, furniture,
  cabinets, jigs, or a workshop layout — and whenever the user wants to see and
  manipulate a model rather than only read numbers.
---

# Scripting FreeCAD for a human who is watching

The user describes a build. You write the model as a Python script. FreeCAD
renders it and they pan, rotate, isolate parts, and tell you what is wrong. You
edit the script; the model updates under their cursor with the camera where they
left it. **The script is the source of truth — the `.FCStd` is a build artefact,
disposable and regenerable.** Never hand-edit a `.FCStd`.

## Tools

| Command | Purpose |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/scripts/fcrun model.py` | Headless build: validation + exports, no GUI, no window. Fast. Your default. |
| `${CLAUDE_PLUGIN_ROOT}/scripts/fclive -b model.py` | Start the live session the user watches. Leave it running — the ONE window. |
| `${CLAUDE_PLUGIN_ROOT}/scripts/fcsnap model.py [out] [view]` | See the live session in the user's own window — their camera, or a canned `view` (iso/top/front/...) that snaps back. Plus selection + drags. **No new window.** |
| `${CLAUDE_PLUGIN_ROOT}/scripts/fcopen model.py part.py` | Open a detail study as a TAB in the live window (no new window); `fcsnap` captures it. |
| `${CLAUDE_PLUGIN_ROOT}/scripts/fcquit model.py` | Stop it cleanly. **Always use this — never `kill`.** |
| `${CLAUDE_PLUGIN_ROOT}/scripts/fcrender doc.FCStd out/ iso,top,front` | Render PNGs to disk — but opens a throwaway GUI window that steals focus. Last resort; prefer `fcsnap`. |

Look at your own renders before asking the user to look. Catching your own
mistake costs a tool call; making them catch it costs their attention.

**Do not take over the user's desktop.** Every `fcrun --gui` and every `fcrender`
opens a FreeCAD window that steals focus — fine once, maddening on every
iteration. So: verify **headless** (`fcrun` + `check_clashes()`, bounding boxes,
`Shape.isInside` point checks — no window), and *see* results through the live
session — `fcsnap` (their window, optional canned view) or a detail study in an
`fcopen` tab. There is no headless PNG path on macOS (Qt-offscreen hangs, Coin's
offscreen renderer errors), so reserve `fcrender`/`fcrun --gui` for when no live
session is open at all.

## The loop runs both ways

`fcsnap` is how the user's manipulation reaches you. It returns a PNG of *their*
camera (not a canned view), what they have selected — so "this one" resolves to
a name — and `moved`: how each part's placement now differs from where your
script put it.

**A drag is a proposal, not a mistake.** When `moved` is non-empty, the user has
told you something with the mouse. Fold it into the script as a real parameter
and say what you changed. Do not silently ignore it — the next rebuild destroys
it.

## Writing a model

```python
import os, sys
sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww

ww.UNITS = "in"                       # reports in inches; geometry always mm

m = ww.Model("shelf-unit")            # closes any same-named doc first
side = m.board("Side_Left", "1x10", ww.inch(36),
               length_axis="z", thickness_axis="x")   # upright
m.dado(side, face="+x", along="y", pos=ww.inch(12),
       width=ww.inch("3/4") + 0.4, depth=ww.inch("3/8"))

m.check_clashes()                     # two parts sharing volume will not fit
m.envelope()                          # does it fit through the door?
m.cutlist()
m.filament()
m.finish(os.environ.get("WW_OUT", os.getcwd()))
```

Put every number worth arguing about in a parameter block at the top. That block
is the interface the user actually edits.

### Nominal sizes are lies — this is the one that bites

A "2x4" is 1.5" x 3.5". "3/4" plywood is 23/32". **Never type the nominal number
as a dimension.** Use `ww.LUMBER`, `ww.PLY`, `ww.MDF`, `ww.BALTIC`, or the
`board()` / `panel()` constructors, which take the nominal *name* and produce
actual geometry. `ww.inch()` accepts `3.5`, `"3/4"`, `"1 1/2"`.

### Units: metric shop, imperial lumberyard

This user works in **metric** and buys in **imperial**. Default to
`ww.UNITS = "both"` for anything headed to the shop — it prints `914.4 (36")`.
Geometry is always mm. Always refer to stock by its nominal name (a **2x4**,
never a 38x89).

### cutplan(), not just cutlist()

`cutlist()` says what parts are needed. `cutplan()` says what to **buy** and what
to **cut from each board** — that is the useful artefact. It only plans parts made
with `board()` or `panel()`; a part made with `box()` has no stock, so there is
nothing to buy it from, and it is reported as skipped. Prefer `board()`/`panel()`
for anything real.

Rotation of sheet parts is off by default because **grain runs the length of a
sheet**. Do not enable it to improve yield unless the material has no grain.

**This user drives a Tacoma (5ft bed) and prefers half sheets.** Default to
`m.cutplan(max_length=ww.ft(8), sheet_piece="half")` unless told otherwise — a
plan that buys a 12ft board or a full 4x8 is a plan he cannot get home. He always
buys a full sheet and has the store cut it; `sheet_piece` says how.

### Joinery

`trench(part, face, along, pos, width, depth)` is the primitive: a channel cut
into a named face (`+x`, `-z`, ...), running along a named axis. `dado()` is that
in the middle of a face; `rabbet()` is the same pushed flush against an edge.
Also `mortise()`, `tenon()`, `hole()`, `notch()`, `fillet()`, `chamfer()`.

Orientation is explicit: `board()` takes `length_axis` **and** `thickness_axis`,
because one axis is ambiguous — a board lying flat and the same board on edge
share a length axis and are not the same part.

### Angled joinery, ramps, and grids

`trench`/`dado`/`rabbet`/`notch` all cut axis-aligned boxes. For anything
*angled* — a French-cleat ramp, a bevel, a taper, a dovetail key — reach for
`ww.prism(profile, length, along=...)`: it extrudes a 2D `(u, v)` polygon (drawn
in the plane perpendicular to `along`; `y`→`(x,z)`, `x`→`(y,z)`, `z`→`(x,y)`)
into a solid you drop straight into `m.add(name, ...)` or `part.cut(...)`.
`ww.wedge(u0, u1, v0, v1, length, along=...)` is the right-triangle (ramp) case.
Both beat fighting `chamfer()`'s edge predicate when you want a specific angled
face at a specific place.

`ww.frange(start, stop, step)` is `range()` for floats — rib grids, dog-hole
fields, screw on-centre spacing. Size the span to a whole multiple of the pitch
so end margins come out even (e.g. a 192 mm rib grid with 96 mm dog holes offset
48 mm lands no hole on a rib).

### Part kinds set the colour

`m.add`/`box`/`board`/`panel` take `kind=`: `"wood"` (default, brown, 35%
see-through so joinery reads), `"printed"` (blue), `"hardware"` (grey — bought
metal: slides, casters, plates), `"steel"` (fasteners). Unknown kinds fall back
to blue, and `KIND_STYLE` is a plain dict you can extend. `kind` also drives the
reports: `cutlist()` counts `wood`, `filament()` counts `printed`.

### Select edges by geometry, never by index

`Edge7` is renumbered by a recompute — that is FreeCAD's topological naming
problem. Use `vertical_edges`, `edges_at`, `edges_where`. A predicate cannot be
renumbered, so a scripted model simply does not have FreeCAD's worst bug.

### Always run check_clashes()

Two parts sharing volume is a part that will not physically fit. It catches
exactly the errors that are invisible in a render — it has already caught real
bugs in the shipped examples.

## Things FreeCAD will do to you

These are not hypotheticals; each one has already cost a debugging session.

**Document names are sanitised.** `newDocument("bracket-box")` yields a document
named `bracket_box`. Any lookup against the unsanitised name silently misses —
which, in a live-reload loop, means every rebuild stacks *another* document
(`bracket_box`, `bracket_box1`, ...) instead of replacing it. `ww.Model` handles
this; if you call `App.newDocument` yourself, sanitise to `[A-Za-z0-9_]`. The
**saved file** uses the sanitised name too, so `Model("bt-band")` writes
`bt_band.FCStd` — `fcrender bt-band.FCStd` misses (it now points you at the
sanitised sibling, but the file on disk is always the underscored name).

**Headless documents open invisible.** With no GUI, `obj.ViewObject` is `None` —
no view providers exist, so a headless-authored `.FCStd` opens with everything
hidden and the 3D view looks empty. Colour and visibility can only be set when
`App.GuiUp`. `ww.Model.finish()` does this correctly.

**Under the GUI, `print()` does not reach stdout.** FreeCAD rebinds Python's
stdout to its Report View widget. A caller watching the process pipe sees
silence forever. Use `ww.say()`, which also appends to `$WW_LOG`.

**Non-ASCII in output aborts the script.** An em-dash in a `print()` raises
inside FreeCAD's console and kills the run *after* printing results but *before*
exporting — leaving stale artefacts that look current. Keep script output ASCII;
`ww.say()` enforces this.

**`Part::Cut` returns a Compound, not a Solid.** `shape.ShapeType != "Solid"`
means nothing about printability. Judge from the mesh: closed, manifold, no
self-intersections. That is what `m.check_printable()` reports.

**Never kill FreeCAD.** A hard kill leaves recovery breadcrumbs, and the next
launch greets you with a modal "Original file corrupted" dialog that blocks every
automated run behind it — invisibly, because you cannot see the dialog. Use
`fcquit`. Also note we launch the binary directly (so it inherits the env), which
means macOS never registers it with LaunchServices: `open -a FreeCAD` would spawn
a *second* instance, and AppleScript cannot address the running one.

**Camera moves are animated.** Capturing an image straight after switching views
photographs the camera mid-flight. `fcrender` settles the event loop first.

## Working with the user

Start `fclive -b` once and leave it up for the session. Edit the script; do not
restart FreeCAD to apply a change — the watcher reloads `wwkit` too, so library
edits land live as well.

**Don't point `fcrun` or `fcrender` at the folder a live session owns.** Writing
the same `WW_OUT`/`.FCStd` that a `fclive` session holds open makes FreeCAD see
an external change and can wedge the QTimer reloader (only "rebuild #1" ever
logs, and `fcquit` then can't complete). Validate and render to a *temp* dir
instead — e.g. `WW_OUT=$(mktemp -d) fcrun model.py`.

Report what changed in terms they care about (panel dimensions, filament grams,
clashes), not in terms of FreeCAD objects.
