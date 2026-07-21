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

`cutlist()` says what parts you need. `cutplan()` says what to **buy** and what
to **cut from each board** — the thing you take to the yard and then to the saw.

A part doesn't carry a stock size — it carries a **material type**
(`framing`, `hardwood`, `pine-ply`, ...), set by `board()` / `panel()` /
`strip()` / `box()`. `cutplan()` owns the buying decision: it groups parts by
`(material, thickness)` and, for each group, works out every way to source it,
ranks the options, and prints the winner in full with the rest collapsed to one
line.

```text
CUT PLAN  (kerf 3.2 (1/8"), end-trim 25.4 (1"), edge-trim 12.7 (1/2"), oversize 3.2 (1/8"), prefer value)

  framing -- 6 x 2x4 @ 8 ft   (21.0 bd-ft, $)
      factory (eased) edges, no ripping
      #1 [8 ft, offcut 6.6 (1/4")]: Frame_Front (1747.0 (68-3/4")), Post_AF_0 (630.9 (24-13/16"))
      ...
      also works: 3 x 2x10 @ 8 ft  --  27.8 bd-ft, $$ [2 clean strips/board, all-square edges, clearer grade]

  hardwood 4/4 -- 2 x 4/4 >=164.5 (6-1/2") wide @ 10 ft   (10.8 bd-ft, $$)
      board/sheet #1:
        rip 102.2 (4") wide: Band_Front (1942.2 x 102.2), Band_Right (982.2 x 102.2)
        rip 44.4 (1-3/4") wide: Cleat_F+Key_F (1850.1 x 44.4), Cleat_L+Key_L (890.1 x 44.4)

  mdf 3/4 -- 1 x 4x8   (1 sheet(s), $)
      note: full 4x8 - each could be store-cut in half

BUY       6 x 2x4 @ 8 ft; 2 x 4/4 >=164.5 (6-1/2") wide @ 10 ft; 1 x 4x8; ...
```

Each group's recommended option prints in full: the buy line, board-feet or
sheet count and cost tier, and the board-by-board (or sheet-by-sheet) cut
layout. Dimensional lumber can be bought as-is — factory edges, planned by
length only — or ripped from a wider nominal, trading bd-ft for square edges
and clearer grade (a 2x10 yields two clean 3.5" strips; a 2x8 yields only one,
so it is never offered — that's the trap this avoids). Hardwood nests every rip
profile across a board's random width and phrases the buy as "≥N boards ≥W
wide × L". Options that lose the ranking still show up, just collapsed to a
single "also works:" line so you can see what you gave up.

`prefer` ranks options **within** a material type — `"value"` (default: best
quality per cost tier, then least material), `"cost"`, or `"quality"` — but
never across types: you declared `framing`, so the plan will never suggest
hardwood instead.

**Grain is a property of the material, not a cutplan setting** — and for sheet
goods it is cosmetic, not a constraint. Plywood is cross-laminated, so its face
grain is a veneer look, not structure, and a hidden part (a drawer box side, a
cabinet back) has no grain worth respecting. Sheet parts therefore rotate freely
to improve yield by default; a material sets `grain=True` only to keep a show
veneer running one way. Solid-wood rip strips (framing, hardwood) always run
grain-along-length and are never rotated.

Two per-part knobs cover the exceptions. `grain=True` on a single
`panel()`/`box()`/`strip()` pins that one part's orientation. `grain_seq="label"`
ties parts into a continuous-grain run: they are cut consecutively from one board,
in model order, so the grain flows across them — a drawer-front bank, a wrapped
band. A run bigger than any single board is flagged rather than split, because
continuous grain cannot span two boards.

Packing is first-fit-decreasing, not optimal. Optimal bin packing is NP-hard and
pointless at this scale: with a dozen parts FFD lands within a board of optimal,
and the saw is not that precise anyway.

### Transport is the shopper's call

Earlier versions solved for the truck bed as a hard constraint. It doesn't
anymore. `cutplan()` nests parts onto full stock — a full board length, a full
sheet — and simply **annotates** what could be broken down before it leaves the
store, the way the `mdf` group above does:

```text
mdf 3/4 -- 1 x 4x8   (1 sheet(s), $)
    note: full 4x8 - each could be store-cut in half
```

Renting a truck, paying for delivery, or asking the store to cut a board or
sheet down before it goes in the vehicle is the shopper's call — the plan just
tells you the option exists. The only thing still **flagged** is genuine
impossibility: a part wider than every stocked nominal, longer than the longest
board, or bigger than every stocked sheet. Everything else in the plan is still
planned rather than the whole thing crashing, or worse, printing an impossible
cut.

### Override what your yard actually stocks

The catalog lives in `wwcut.MATERIALS` — a plain, user-extensible dict, so add
a species, a grade, or a sheet size your yard actually carries — and
`wwcut.TOOLING`, which sets tool allowances (`edge_cleanup`, `jointer`,
`planer`, `saw_rip`). Set any of them to `0` for a tool you don't own, and
`cutplan()` stops offering options that assume it.

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

`fclive` sets trackpad-friendly defaults on first build: **Gesture** navigation
(left-drag rotates, two-finger drag pans, scroll zooms), **Turntable** orbit
(keeps "up" instead of tumbling like Trackball), and rotate-about-cursor. To
change it, use the navigation-style dropdown in the status bar (bottom right).
Spacebar toggles visibility of the tree selection — that is how you isolate a
part.
