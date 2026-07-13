# freecad

Agent-scripted FreeCAD modelling with a live GUI the human steers.

The agent writes the model as a Python script. FreeCAD renders it. The human
pans, rotates, isolates parts, and says what is wrong. The agent edits the
script; the model rebuilds in place with the camera untouched.

It is the OpenSCAD loop — edit, look, edit — but with real B-rep solids, a
draggable assembly, and one tool covering both woodworking and 3D printing.

**The script is the source of truth. The `.FCStd` is a build artefact.** Delete
it whenever you like; it regenerates in seconds. A corrupted document is a
non-event.

## Requirements

FreeCAD 1.0+.

```bash
brew install --cask freecad          # macOS
flatpak install org.freecad.FreeCAD  # Linux
```

Set `FREECAD_BIN` if it lives somewhere unusual.

## Commands

| Command | Purpose |
|---|---|
| `fcrun model.py` | Headless build: validate + export. No GUI, fast. |
| `fcrun --gui model.py` | Build with the GUI up, so view state is written into the document. |
| `fclive -b model.py` | Live session: rebuilds on every save, preserves the camera. |
| `fcquit model.py` | Stop cleanly. Never `kill` FreeCAD. |
| `fcsnap model.py` | Read the live session back: your camera, your selection, your drags. |
| `fcrender doc.FCStd out/ iso,top,front` | Render PNGs — how the agent sees its own geometry. |

## Skills

| Skill | Invocation |
|---|---|
| `freecad-modeling` | Model-only. Auto-triggers when a FreeCAD model is being designed or edited. |
| `freecad-live` | `/freecad:live [model.py]` — start or stop a live session. |

## Writing a model

```python
import os, sys
sys.path.insert(0, os.environ["WWKIT_LIB"])
import wwkit as ww

ww.UNITS = "in"                 # reports in inches; geometry is always mm

m = ww.Model("shelf-unit")
side = m.board("Side_Left", "1x10", ww.inch(36),
               length_axis="z", thickness_axis="x")   # upright
m.dado(side, face="+x", along="y", pos=ww.inch(12),
       width=ww.inch("3/4") + 0.4, depth=ww.inch("3/8"))

m.check_clashes()   # parts sharing volume will not physically fit
m.envelope()        # does the finished thing fit through the door?
m.cutlist()         # wood: dimensions for the saw
m.finish(os.environ.get("WW_OUT", os.getcwd()))
```

### Nominal sizes are lies

A "2x4" is 1.5" x 3.5". "3/4" plywood is 23/32". Modelling the nominal number is
the classic way to produce a design that cannot be built, so `ww.LUMBER`,
`ww.PLY`, `ww.MDF` and `ww.BALTIC` hold **actual** dimensions, and `board()` /
`panel()` take the nominal name. Sheet thickness varies by supplier — measure
yours and override rather than trusting the table.

`ww.inch()` accepts `3.5`, `"3/4"`, `"1 1/2"`.

### Joinery

`trench()` is the primitive — a channel cut into a named face, running along a
named axis. `dado()` is that in the middle of a face; `rabbet()` is the same
pushed flush against an edge. Also `mortise()`, `tenon()`, `hole()`, `notch()`.

`kind="wood"` / `kind="printed"` drives colour, the cut list, and the filament
estimate.

Examples: `examples/bracket-box.py` (plywood panels in printed corner brackets,
print clearance parameterised) and `examples/joinery.py` (a shelf unit in real
1x10 with dados, rabbets, and a mortise-and-tenon stretcher).

## Edge selection, and why this dodges FreeCAD's worst bug

`Edge7` gets renumbered by a recompute — that is the topological naming problem,
and it is what breaks mouse-built models. `wwkit` selects edges by *geometry*
(`vertical_edges`, `edges_at`, `edges_where`), which cannot be renumbered.
Script-driven modelling can simply not have FreeCAD's most notorious bug.

## Why not use the Woodworking addon

`dprojects/Woodworking` is real and actively maintained, and we deliberately do
not depend on it: every one of its tools is bound to `FreeCADGui.Selection` or
executes Qt dialog code at import time, so none of it is callable headless. Its
joinery is also thinner than it looks — there is no dado, rabbet, dovetail or
finger-joint generator anywhere in it.

We do stamp the `Woodworking_Width/Height/Length` properties it looks for, so if
you open one of our documents in the GUI with that addon installed, its cut-list
report works. Without the stamp it would silently drop every part, because it
ignores boolean results — which is every part with a joint cut into it.

## From a parts list to a cutting plan

`cutlist()` says what parts you need. `cutplan()` says what to **buy**, and
board by board what to **cut from each one** — the thing you take to the yard
and then to the saw.

```text
CUT PLAN  (kerf 3.2 (1/8"))

  1x10  -- 1 board(s) of 12 ft
    #1: Side_Left (914.4 (36")), Side_Right (914.4 (36")), Shelf_0 (590.5 (23-1/4")), ...
        offcut 44.4 (1-3/4")

  1/4 sheet  -- 1 of 8 ft x 4 ft  (18% used, grain respected)
    sheet #1:
      rip 590.5 (23-1/4") wide: Back (914.4 (36") x 590.5 (23-1/4"))

BUY       1 x 1x10 @ 12 ft; 1 x 2x2 @ 6 ft; 1 x 1/4 sheet
```

Boards are packed by length into stock lengths; sheets are packed into strips,
because that is how you actually cut a sheet — rip it, then crosscut the strips.
Kerf is accounted for in both.

**Grain runs the length of a sheet**, so rotating a part 90° to squeeze it in
turns the grain the wrong way. Rotation is therefore **off by default** — a plan
that saves half a sheet by cross-graining your cabinet sides is not a saving.
Pass `allow_rotate=True` for MDF or when you genuinely do not care.

Packing is first-fit-decreasing, not optimal. Optimal bin packing is NP-hard and
pointless at this scale: with a dozen parts FFD lands within a board of optimal,
and the saw is not that precise anyway.

### Transport, which is a real constraint

A plan that buys a 12ft board is useless if the board will not go in the truck.

```python
m.cutplan(max_length=ww.ft(8),     # longest thing you can get home
          sheet_piece="half")      # have the store cut sheets in half
```

`max_length` removes over-long stock from consideration entirely — the planner
will buy two 8ft boards rather than one 12ft one. A *part* longer than the limit
raises: that is a design problem, not a packing one, since even cut to size it
will not fit in the vehicle.

**You always buy a full 4x8 sheet** — `sheet_piece` is what you ask the store's
panel saw to do to it before it goes in the vehicle:

| `sheet_piece` | piece | grain |
|---|---|---|
| `"full"` | 8ft x 4ft | along the 8ft |
| `"half"` | 4ft x 4ft | along a 4ft axis (crosscut) |
| `"half-rip"` | 8ft x 2ft | still along the 8ft |

A crosscut half and a ripped half have the **same area and different grain**, so
they are not interchangeable. Leave `sheet_piece` unset to let the planner pick
the fewest full sheets, breaking ties toward the smaller piece.

The shopping list says what to ask for:

```text
BUY  2 x 1x10 @ 8 ft; 1 x 2x2 @ 6 ft; 1 x 1/4 full sheet (cut in half at the store, 1 spare)
```

Override what your yard actually stocks:

```python
m.cutplan(stock_lengths=[ww.ft(6), ww.ft(8)], kerf=3.2)
```

### Units: metric shop, imperial lumberyard

`ww.UNITS` is `"mm"` (default), `"in"`, or `"both"`. Geometry is *always* mm;
this only affects reports. `"both"` prints `914.4 (36")` — metric to work in,
imperial to buy in. Stock always keeps its nominal imperial name, so you ask for
a **2x4**, not a 38x89.

## Why this is not OpenCutList

SketchUp's OpenCutList exists to recover dimensions from a model built by hand.
When the model is generated from a script, the script already knows every part's
dimensions — so the cut list and the cut plan fall straight out of the source.

## FreeCAD behaviours this plugin absorbs

Each of these cost a real debugging session.

- **Document names are sanitised.** `newDocument("bracket-box")` produces a doc
  named `bracket_box`. Look it up by the original name and you miss — so a
  live-reload loop stacks `bracket_box`, `bracket_box1`, ... forever instead of
  replacing. `ww.Model` sanitises.
- **Headless documents open invisible.** No GUI means no view providers, so
  `obj.ViewObject` is `None` and every object opens hidden — the document looks
  empty. Visibility and colour can only be set with `App.GuiUp`.
- **Under the GUI, `print()` never reaches stdout.** FreeCAD rebinds it to the
  Report View. Anything watching the process pipe sees silence forever. Hence
  the log files.
- **Non-ASCII output aborts the script**, after printing results but before
  exporting — leaving stale artefacts that look current. `ww.say()` enforces
  ASCII.
- **`Part::Cut` returns a Compound, not a Solid.** `ShapeType` says nothing
  about printability; the mesh does (closed, manifold, no self-intersections).
- **Never hard-kill FreeCAD.** It leaves recovery breadcrumbs, and the next
  launch hangs behind a modal "Original file corrupted" dialog — invisibly, in
  an automated run. `fcquit` closes documents via the API (which does not
  prompt) and then the window.
- **`open -a FreeCAD` starts a second instance.** We launch the binary directly
  so it inherits the environment, which means macOS never registers it with
  LaunchServices — so `open -a` cannot find it and launches another. AppleScript
  cannot address it either.
- **Camera moves are animated.** Capture straight after a view change and you
  photograph the camera mid-flight; `fcrender` settles the event loop first.

## Trackpad navigation

FreeCAD defaults to three-button-mouse bindings that are unusable on a laptop.
Set the navigation style to **Gesture** in the status-bar dropdown (bottom
right, shows `CAD` by default): left-drag rotates, two-finger drag pans, scroll
zooms. Spacebar toggles visibility of the tree selection — that is how you
isolate a part.
