"""wwkit - helpers for scripting FreeCAD models that a human then inspects.

Written for a script-generates / human-inspects loop: an agent authors the
model, FreeCAD renders it, the human pans and rotates and says what's wrong,
the agent edits the script.

Design notes worth knowing before you extend this:

* **Shapes first, one document object per real part.** Joinery mutates a part's
  shape in place (``part.cut(tool)``) instead of chaining ``Part::Cut`` feature
  objects. A dado-ed panel is still one object called ``Panel_Left``, not a
  tree of anonymous cuts, and the document contains no construction scratch to
  hide, colour, or accidentally render.

* **Select edges by geometry, never by index.** ``Edge7`` is renumbered by a
  recompute — that is FreeCAD's topological naming problem, and it is what
  breaks mouse-built models. Selecting by predicate (``vertical_edges``,
  ``edges_at``) is immune to it by construction. Script-driven modelling can
  simply not have FreeCAD's most notorious bug.

FreeCAD behaviours this module absorbs:

1. Headless documents have no view providers: ``obj.ViewObject`` is ``None``,
   so a headless-authored file opens with everything hidden and the 3D view
   looks empty. Colour/visibility are only set when ``App.GuiUp``.
2. Non-ASCII in a ``print()`` raises inside FreeCAD's console and aborts the
   run - after printing results, before exporting, leaving stale artefacts that
   look current. ``say()`` strips to ASCII.
3. Booleans yield Compounds, so ``ShapeType != "Solid"`` says nothing about
   printability. Judge from the mesh: closed, manifold, no self-intersections.
"""

import json
import os
import re

import FreeCAD as App
import Mesh
import Part

# --- units ---------------------------------------------------------------
# Internally everything is millimetres, because FreeCAD is. Input and reports
# can be imperial, because lumber is.

IN = 25.4
FT = 304.8

# Reports only; geometry is always mm.
#   "mm"   - metric, the default: this is a metric shop
#   "in"   - imperial
#   "both" - metric with the imperial in parentheses, for the trip to the yard
UNITS = os.environ.get("WW_UNITS", "mm")


def inch(x):
    """Inches to mm. Accepts 3.5, "3/4", "1 1/2", "1-1/2"."""
    if isinstance(x, str):
        total = 0.0
        for part in x.strip().replace("-", " ").split():
            if "/" in part:
                num, den = part.split("/")
                total += float(num) / float(den)
            else:
                total += float(part)
        x = total
    return float(x) * IN


def ft(x):
    return float(x) * FT


def _frac(inches, denom=16):
    """Inches as a shop fraction: 9.03 -> 9 1/32 is silly, 9 -> 9."""
    whole = int(inches)
    num = round((inches - whole) * denom)
    if num == 0:
        return "%d" % whole
    if num == denom:
        return "%d" % (whole + 1)
    while num % 2 == 0 and denom % 2 == 0:
        num //= 2
        denom //= 2
    return "%d-%d/%d" % (whole, num, denom) if whole else "%d/%d" % (num, denom)


def fmt(mm):
    """A length for a report, honouring UNITS."""
    if UNITS == "in":
        return '%s"' % _frac(mm / IN)
    if UNITS == "both":
        return '%.1f (%s")' % (mm, _frac(mm / IN))
    return "%.1f" % mm


def fmt_stock(mm):
    """A stock length the way a lumberyard sells it: 2438 -> '8 ft'."""
    feet = mm / FT
    if abs(feet - round(feet)) < 0.02:
        return "%d ft" % round(feet)
    return "%.0f mm" % mm


# --- stock ---------------------------------------------------------------
# Nominal sizes are lies. A "2x4" is 1.5" x 3.5"; "3/4" plywood is usually
# 23/32". Modelling the nominal number is the classic way to produce a design
# that cannot be built. These are actual dimensions, in mm.

LUMBER = {  # nominal -> (thickness, width), surfaced softwood
    "1x2": (inch("3/4"), inch("1 1/2")),
    "1x3": (inch("3/4"), inch("2 1/2")),
    "1x4": (inch("3/4"), inch("3 1/2")),
    "1x6": (inch("3/4"), inch("5 1/2")),
    "1x8": (inch("3/4"), inch("7 1/4")),
    "1x10": (inch("3/4"), inch("9 1/4")),
    "1x12": (inch("3/4"), inch("11 1/4")),
    "2x2": (inch("1 1/2"), inch("1 1/2")),
    "2x3": (inch("1 1/2"), inch("2 1/2")),
    "2x4": (inch("1 1/2"), inch("3 1/2")),
    "2x6": (inch("1 1/2"), inch("5 1/2")),
    "2x8": (inch("1 1/2"), inch("7 1/4")),
    "2x10": (inch("1 1/2"), inch("9 1/4")),
    "2x12": (inch("1 1/2"), inch("11 1/4")),
    "4x4": (inch("3 1/2"), inch("3 1/2")),
    "6x6": (inch("5 1/2"), inch("5 1/2")),
}

# Sheet goods, actual thickness. These vary by product and supplier — measure
# yours and override rather than trusting the table blindly.
PLY = {  # US softwood/hardwood ply: undersized against nominal
    "1/4": inch("7/32"),
    "3/8": inch("11/32"),
    "1/2": inch("15/32"),
    "5/8": inch("19/32"),
    "3/4": inch("23/32"),
}
BALTIC = {"3mm": 3.0, "6mm": 6.0, "9mm": 9.0, "12mm": 12.0, "18mm": 18.0}
MDF = {  # MDF is true to nominal, unlike ply
    "1/4": inch("1/4"),
    "1/2": inch("1/2"),
    "3/4": inch("3/4"),
}

# --- appearance ----------------------------------------------------------
# Colour + transparency are keyed by a part's `kind` (see Model.add). `kind` is
# a free-form string, so a model can invent its own; anything not in KIND_STYLE
# falls back to KIND_STYLE_DEFAULT. Transparency lets joinery read through a shell.
WOOD = (0.80, 0.60, 0.35)
PRINTED = (0.20, 0.55, 0.85)
HARDWARE = (0.56, 0.58, 0.61)   # purchased metal: slides, casters, lift plates
STEEL = (0.26, 0.28, 0.32)      # fasteners

KIND_STYLE = {           # kind -> (rgb, transparency%)
    "wood":     (WOOD, 35),
    "printed":  (PRINTED, 0),
    "hardware": (HARDWARE, 0),
    "steel":    (STEEL, 0),
}
KIND_STYLE_DEFAULT = (PRINTED, 0)

PLA_DENSITY = 1.24  # g/cm^3
TESSELLATION = 0.05  # mm deviation for the printability mesh check

_LOG = os.environ.get("WW_LOG")


def say(msg):
    """print(), minus the characters that abort a FreeCAD console run.

    Also appends to $WW_LOG. Under the GUI, FreeCAD rebinds Python's stdout to
    its Report View, so print() never reaches the process pipe — the log file
    is the only channel that works in both headless and GUI runs.
    """
    line = str(msg).encode("ascii", "replace").decode("ascii")
    print(line)
    if _LOG:
        try:
            with open(_LOG, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass


# --- shape builders (pure; no document objects) --------------------------
def solid(dx, dy, dz, at=(0, 0, 0)):
    return Part.makeBox(dx, dy, dz, App.Vector(*at))


def cyl(radius, height, at=(0, 0, 0), axis=(0, 0, 1)):
    return Part.makeCylinder(radius, height, App.Vector(*at), App.Vector(*axis))


def frange(start, stop, step):
    """range() for floats: start, start+step, ... up to (not including) stop.

    range() is int-only, so fixed-pitch layouts -- rib grids, dog-hole fields,
    screw on-centre spacing -- otherwise need a hand-rolled while-loop each time.
    """
    out, v = [], start
    while v < stop:
        out.append(v)
        v += step
    return out


def prism(profile, length, along="y", at=(0, 0, 0)):
    """Extrude a 2D profile into a solid -- the primitive for ANGLED joinery.

    `profile` is a list of (u, v) points (a polygon, in order; auto-closed) drawn
    in the plane perpendicular to `along`, then swept `length` along that axis:
      along="y" -> (u, v) = (x, z)   along="x" -> (y, z)   along="z" -> (x, y)
    `at` offsets the whole prism. Use it for cleats, ramps, bevels, tapers, and
    dovetail keys -- the angled cuts chamfer()'s edge predicate can't place.
    Returns a Part.Shape, so it drops into m.add(name, prism(...)) or
    part.cut(prism(...)) directly.
    """
    ax = {"x": 0, "y": 1, "z": 2}[along]
    plane = [i for i in (0, 1, 2) if i != ax]

    def pt(u, v):
        c = [0.0, 0.0, 0.0]
        c[plane[0]], c[plane[1]] = u, v
        return App.Vector(c[0] + at[0], c[1] + at[1], c[2] + at[2])

    pts = [pt(u, v) for (u, v) in profile]
    pts.append(pts[0])
    ext = [0.0, 0.0, 0.0]
    ext[ax] = length
    return Part.Face(Part.makePolygon(pts)).extrude(App.Vector(*ext))


def wedge(u0, u1, v0, v1, length, along="y", at=(0, 0, 0)):
    """Right-triangle prism (a ramp) -- the common case of prism().

    Triangle corners (u0,v0)-(u1,v0)-(u0,v1) swept `length`; the ramp is the
    hypotenuse from (u1,v0) to (u0,v1). Same axis/plane convention as prism().
    """
    return prism([(u0, v0), (u1, v0), (u0, v1)], length, along=along, at=at)


# --- edge selection by geometry, not by index ----------------------------
def edges_where(shape, pred):
    return [e for e in shape.Edges if _safe(pred, e)]


def _safe(pred, edge):
    try:
        return bool(pred(edge))
    except Exception:
        return False


def vertical_edges(shape):
    """Every edge running along Z — e.g. the four corners of an upright post."""

    def pred(e):
        t = e.tangentAt(e.FirstParameter)
        return abs(t.z) > 0.999

    return edges_where(shape, pred)


def edges_at(shape, z=None, tol=1e-6):
    """Every edge lying in a given Z plane — e.g. the top rim of a box."""

    def pred(e):
        return all(abs(v.Point.z - z) < tol for v in e.Vertexes)

    return edges_where(shape, pred)


class Part_:
    """One real part: a named solid with a material role."""

    def __init__(self, obj, kind, nominal=None, stock=None, form=None,
                 oversize=None):
        self.obj = obj
        self.kind = kind  # "wood" | "printed"
        self.nominal = nominal  # (dx, dy, dz) as authored, for the cut list
        self.stock = stock  # e.g. "2x4" — the nominal name you buy it under
        self.form = form  # "board" | "sheet" | None — how the planner packs it
        # Rough-cut allowance for THIS part, or None to use the cutplan default.
        # 0 exempts a part that is already final size, or a glue-up member whose
        # trim happens at the assembly (set the assembly's oversize instead).
        self.oversize = oversize

    @property
    def name(self):
        return self.obj.Name

    @property
    def shape(self):
        return self.obj.Shape

    @property
    def bbox(self):
        return self.obj.Shape.BoundBox

    def cut(self, tool):
        """Subtract a shape. The part stays one object with the same name."""
        self.obj.Shape = self.obj.Shape.cut(tool)
        return self

    def fuse(self, tool):
        self.obj.Shape = self.obj.Shape.fuse(tool)
        return self

    def fillet(self, radius, pred=vertical_edges):
        edges = pred(self.obj.Shape) if callable(pred) else pred
        if edges:
            self.obj.Shape = self.obj.Shape.makeFillet(radius, edges)
        return self

    def chamfer(self, size, pred=vertical_edges):
        edges = pred(self.obj.Shape) if callable(pred) else pred
        if edges:
            self.obj.Shape = self.obj.Shape.makeChamfer(size, edges)
        return self


class Model:
    """A FreeCAD document plus the bookkeeping a build actually needs."""

    def __init__(self, name):
        # FreeCAD sanitises a document's internal Name to [A-Za-z0-9_], so
        # newDocument("bracket-box") yields a doc named "bracket_box". Sanitise
        # first, or the close-and-replace below silently misses and every
        # live-reload stacks another document: bracket_box, bracket_box1, ...
        name = re.sub(r"[^A-Za-z0-9_]", "_", name)
        if name in App.listDocuments():
            App.closeDocument(name)
        self.doc = App.newDocument(name)
        self.parts = []

    # -- construction -----------------------------------------------------
    def add(self, name, shape, kind="wood", nominal=None, stock=None, form=None,
            oversize=None):
        o = self.doc.addObject("Part::Feature", name)
        o.Shape = shape
        p = Part_(o, kind, nominal=nominal, stock=stock, form=form,
                  oversize=oversize)
        self.parts.append(p)
        return p

    def box(self, name, dx, dy, dz, at=(0, 0, 0), kind="wood", oversize=None,
            form=None, stock=None):
        """A plain rectangular solid. Pass form="board"/"sheet" and a stock name
        to have cutplan buy it (e.g. a hardwood edge band as linear stock, a
        laminate as a sheet); leave them off and it is a shape the plan skips."""
        return self.add(name, solid(dx, dy, dz, at), kind, nominal=(dx, dy, dz),
                        oversize=oversize, form=form, stock=stock)

    def strip(self, name, shape, stock, kind="wood", oversize=None):
        """A part cut to length from linear stock whose shape is not a plain
        board() box — a ripped hardwood cleat, an angled edge band, an on-edge
        ply strip. cutplan buys it as a board: its longest bounding dimension is
        the length, and parts sharing a `stock` name come off the same sticks.

        `shape` is any already-built Part shape (e.g. from ww.prism/wedge). Use
        distinct `stock` names for distinct rip profiles so the plan does not
        pool a wide band with a narrow cleat onto one stick."""
        bb = shape.BoundBox
        return self.add(name, shape, kind,
                        nominal=(bb.XLength, bb.YLength, bb.ZLength),
                        stock=stock, form="board", oversize=oversize)

    def board(self, name, stock, length, at=(0, 0, 0),
              length_axis="x", thickness_axis="z", rip=None, kind="wood",
              oversize=None):
        """A board of real dimensional lumber. `stock` is nominal ("2x4").

        Orientation is given by two axes rather than one, because one is
        ambiguous: a board lying flat and the same board standing on edge share
        a length axis but are not the same part. Width takes the axis left over.
        """
        if stock not in LUMBER:
            raise KeyError("unknown lumber %r; known: %s"
                           % (stock, ", ".join(sorted(LUMBER))))
        if length_axis == thickness_axis:
            raise ValueError("length and thickness cannot share an axis")
        t, w = LUMBER[stock]
        if rip:  # ripped narrower than the stock came
            w = rip
        width_axis = ({"x", "y", "z"} - {length_axis, thickness_axis}).pop()
        by_axis = {length_axis: length, thickness_axis: t, width_axis: w}
        dims = (by_axis["x"], by_axis["y"], by_axis["z"])
        return self.add(name, solid(*dims, at=at), kind, nominal=dims,
                        stock=stock, form="board", oversize=oversize)

    def panel(self, name, stock, length, width, at=(0, 0, 0),
              thickness_axis="z", table=PLY, kind="wood", oversize=None):
        """A sheet-goods panel. `stock` keys into PLY / BALTIC / MDF.

        thickness_axis matters: a cabinet bottom is thick in Z, a back panel is
        thick in Y. Getting it wrong produces a part with the right area and a
        nonsensical thickness.
        """
        if stock not in table:
            raise KeyError("unknown sheet %r; known: %s"
                           % (stock, ", ".join(sorted(table))))
        t = table[stock]
        others = [a for a in "xyz" if a != thickness_axis]
        by_axis = {thickness_axis: t, others[0]: length, others[1]: width}
        dims = (by_axis["x"], by_axis["y"], by_axis["z"])
        return self.add(name, solid(*dims, at=at), kind,
                        nominal=dims, stock=stock, form="sheet",
                        oversize=oversize)

    def place(self, name, shape, at=(0, 0, 0), rot_z=0.0, kind="printed"):
        """Stamp an already-built shape into the model at a placement."""
        p = self.add(name, shape, kind)
        p.obj.Placement = App.Placement(
            App.Vector(*at), App.Rotation(App.Vector(0, 0, 1), rot_z)
        )
        return p

    def of_kind(self, kind):
        return [p for p in self.parts if p.kind == kind]

    # -- joinery ----------------------------------------------------------
    # Every joint is a boolean cut. What these buy you is not the boolean but
    # the arithmetic: positions derived from the part's own bounding box, and a
    # clearance parameter in one obvious place.

    def notch(self, part, size, at):
        """The primitive: subtract a box in absolute coordinates."""
        return part.cut(solid(*size, at=at))

    def trench(self, part, face, along, pos, width, depth):
        """A flat-bottomed channel cut into one face. The joinery primitive.

        `face`   the surface it opens on: +x -x +y -y +z -z
        `along`  the axis it runs along (must not be the face's own axis)
        `pos`    where it starts on the remaining axis
        `width`  its extent on that remaining axis
        `depth`  how far it cuts into the part from `face`

        A dado is this in the middle of a face; a rabbet is this pushed flush
        against an edge, which is why both are wrappers rather than separate
        geometry.
        """
        sign, nax = face[0], face[1]
        if nax not in "xyz" or sign not in "+-":
            raise ValueError("face must be like '+x', got %r" % face)
        if along == nax:
            raise ValueError("a trench cannot run along its own face normal")
        third = ({"x", "y", "z"} - {nax, along}).pop()

        b = part.bbox
        lo = {"x": b.XMin, "y": b.YMin, "z": b.ZMin}
        hi = {"x": b.XMax, "y": b.YMax, "z": b.ZMax}
        length = {"x": b.XLength, "y": b.YLength, "z": b.ZLength}

        size = {along: length[along], third: width, nax: depth}
        at = {
            along: lo[along],
            third: pos,
            nax: (hi[nax] - depth) if sign == "+" else lo[nax],
        }
        return part.cut(
            solid(size["x"], size["y"], size["z"],
                  at=(at["x"], at["y"], at["z"]))
        )

    def dado(self, part, face, along, pos, width, depth):
        """A trench across the middle of a face, to receive another panel."""
        return self.trench(part, face, along, pos, width, depth)

    def rabbet(self, part, face, edge, width, depth):
        """A step along one edge — the classic case-back joint.

        `edge` (e.g. "+y") is the boundary the step is flush against.
        """
        eax = edge[1]
        b = part.bbox
        lo = {"x": b.XMin, "y": b.YMin, "z": b.ZMin}
        hi = {"x": b.XMax, "y": b.YMax, "z": b.ZMax}
        pos = (hi[eax] - width) if edge[0] == "+" else lo[eax]
        along = ({"x", "y", "z"} - {face[1], eax}).pop()
        return self.trench(part, face, along, pos, width, depth)

    def mortise(self, part, face, at, size, depth):
        """A blind rectangular pocket in `face`.

        `at` and `size` are given on the two axes that are not the face normal,
        in x,y,z order (the face's own axis is ignored).
        """
        sign, nax = face[0], face[1]
        others = [a for a in "xyz" if a != nax]
        b = part.bbox
        lo = {"x": b.XMin, "y": b.YMin, "z": b.ZMin}
        hi = {"x": b.XMax, "y": b.YMax, "z": b.ZMax}

        sz = dict(zip(others, size))
        pt = dict(zip(others, at))
        sz[nax] = depth
        pt[nax] = (hi[nax] - depth) if sign == "+" else lo[nax]
        return part.cut(
            solid(sz["x"], sz["y"], sz["z"], at=(pt["x"], pt["y"], pt["z"]))
        )

    def tenon(self, part, end, size, length):
        """Reduce a board's end to a tongue by cutting away the shoulders.

        `end` is +x or -x; `size` is the (width, thickness) of the tongue,
        centred in the board.
        """
        b = part.bbox
        tw, tt = size
        x = b.XMax - length if end == "+x" else b.XMin
        y0 = b.YMin + (b.YLength - tw) / 2.0
        z0 = b.ZMin + (b.ZLength - tt) / 2.0
        # Four shoulders around the tongue.
        part.cut(solid(length, y0 - b.YMin, b.ZLength, at=(x, b.YMin, b.ZMin)))
        part.cut(solid(length, b.YMax - (y0 + tw), b.ZLength, at=(x, y0 + tw, b.ZMin)))
        part.cut(solid(length, tw, z0 - b.ZMin, at=(x, y0, b.ZMin)))
        part.cut(solid(length, tw, b.ZMax - (z0 + tt), at=(x, y0, z0 + tt)))
        return part

    def hole(self, part, at, dia, depth, axis=(0, 0, -1)):
        start = App.Vector(*at)
        return part.cut(
            Part.makeCylinder(dia / 2.0, depth, start, App.Vector(*axis))
        )

    # -- checks -----------------------------------------------------------
    def check_printable(self, shape, label="part"):
        """Would a slicer accept this? Mesh-level truth, not ShapeType."""
        if isinstance(shape, Part_):
            label, shape = shape.name, shape.shape
        mesh = Mesh.Mesh()
        mesh.addFacets(shape.tessellate(TESSELLATION))
        # A shape split into two disconnected solids (e.g. a bevel that cut a
        # shell in two, leaving a floating cap) is individually valid/closed/
        # manifold per piece, so it would otherwise "pass" -- one body only.
        solids = len(shape.Solids)
        ok = (
            solids == 1
            and shape.isValid()
            and shape.isClosed()
            and mesh.isSolid()
            and not mesh.hasNonManifolds()
            and not mesh.hasSelfIntersections()
        )
        say("PRINTABLE %-14s %s  (solids=%d valid=%s closed=%s manifold=%s no-self-isect=%s)"
            % (label, "OK" if ok else "FAIL", solids, shape.isValid(), shape.isClosed(),
               not mesh.hasNonManifolds(), not mesh.hasSelfIntersections()))
        return ok

    def check_clashes(self, tol=1e-6):
        """Two parts sharing volume is a part that will not physically fit."""
        clashes = []
        for i, a in enumerate(self.parts):
            for b in self.parts[i + 1:]:
                vol = a.shape.common(b.shape).Volume
                if vol > tol:
                    clashes.append((a.name, b.name, vol))
                    say("CLASH     %s x %s  %.2f mm^3" % (a.name, b.name, vol))
        say("CLASH     %d interference pair(s)" % len(clashes))
        return clashes

    def gap(self, a, b):
        """Shortest distance between two parts. Negative means they overlap."""
        d = a.shape.distToShape(b.shape)[0]
        if a.shape.common(b.shape).Volume > 1e-6:
            d = -d
        say("GAP       %s <-> %s  %s mm" % (a.name, b.name, fmt(d)))
        return d

    def envelope(self):
        """Overall bounding box — does the finished thing fit through a door?"""
        boxes = [p.bbox for p in self.parts]
        if not boxes:
            return None
        x = max(b.XMax for b in boxes) - min(b.XMin for b in boxes)
        y = max(b.YMax for b in boxes) - min(b.YMin for b in boxes)
        z = max(b.ZMax for b in boxes) - min(b.ZMin for b in boxes)
        say("ENVELOPE  %s x %s x %s" % (fmt(x), fmt(y), fmt(z)))
        return (x, y, z)

    # -- reports ----------------------------------------------------------
    def cutlist(self):
        wood = self.of_kind("wood")
        if not wood:
            return []
        say("-" * 64)
        say("CUT LIST (wood%s)" % ("" if UNITS == "mm" else ", inches"))
        rows = []
        for p in wood:
            dims = sorted(p.nominal or _bbox_dims(p.shape), reverse=True)
            rows.append((p.name, p.stock, dims))
            say("  %-16s %-6s %8s x %8s x %8s"
                % (p.name, p.stock or "", fmt(dims[0]), fmt(dims[1]), fmt(dims[2])))
        return rows

    def cutplan(self, board_lengths=None, sheet_sizes=None, kerf=None,
                allow_rotate=False, max_length=None, sheet_piece=None,
                end_trim=None, edge_trim=None, oversize=None, packer="auto",
                stock_lengths=None):
        """From a parts list to a shopping list and a cutting order.

        `cutlist()` says what parts you need. This says what to *buy*, and board
        by board what to cut from each one — the thing you take to the yard and
        then to the saw.

        board_lengths  sellable board lengths to choose from (default catalog).
        sheet_sizes    sellable sheet sizes as [(grain, cross, name), ...].
        max_length     the longest piece you can actually get home. Stock longer
                       than this is never offered, however well it would pack.
        sheet_piece    "full" | "half" | "half-rip", or None to choose. You always
                       buy a full sheet; this is what you ask the store to cut it
                       into before it goes in the vehicle.
        end_trim       squared off each board end before packing (default 1").
        edge_trim      trimmed off each sheet edge before packing (default 1/2").
        oversize       default rough-cut allowance per part (default 1/8"): parts
                       are cut oversize and trimmed to final for clean edges. A
                       board grows only in length (its width is fixed rip stock);
                       a sheet part grows in both faces. Any part can override via
                       board()/panel()/box(oversize=...) — set 0 for a part that
                       is already final, or a glue-up member trimmed at the
                       assembly (put the allowance on the assembly instead).
        packer         "auto" | "rectpack" | "shelf" sheet-packing engine.

        `stock_lengths` is a deprecated alias for `board_lengths`.

        Parts made with box() are skipped: no stock, so nothing to buy them
        from. Use board() or panel() to have them planned.
        """
        import wwcut

        kerf = wwcut.KERF if kerf is None else kerf
        end_trim = wwcut.END_TRIM if end_trim is None else end_trim
        edge_trim = wwcut.EDGE_TRIM if edge_trim is None else edge_trim
        oversize = wwcut.OVERSIZE if oversize is None else oversize
        board_lengths = board_lengths if board_lengths is not None else stock_lengths

        boards = [p for p in self.parts if p.form == "board"]
        sheets = [p for p in self.parts if p.form == "sheet"]
        skipped = [p for p in self.parts
                   if p.kind == "wood" and p.form is None]

        say("=" * 64)
        limit = "  (transport limit %s)" % fmt(max_length) if max_length else ""
        say("CUT PLAN  (kerf %s, end-trim %s, edge-trim %s, oversize %s)%s"
            % (fmt(kerf), fmt(end_trim), fmt(edge_trim), fmt(oversize), limit))
        if oversize:
            say("          part sizes below are rough (cut oversize, trim to final)")

        buy = []
        flags = []   # (name, reason) — parts that could not meet the limits

        # --- boards, grouped by the stock you buy them as -----------------
        by_stock = {}
        for p in boards:
            by_stock.setdefault(p.stock, []).append(p)

        for stock in sorted(by_stock):
            # Per-part oversize (rough-cut allowance), defaulting to the cutplan
            # default. On a board only the LENGTH grows — width is fixed stock
            # you rip — so a glue-up member gets a trim-to-length allowance and
            # never a cross-seam one.
            items = [(p.name,
                      max(p.nominal) + (oversize if p.oversize is None
                                        else p.oversize))
                     for p in by_stock[stock]]
            plan = wwcut.plan_linear(items, board_lengths, kerf, max_length,
                                     end_trim, 0.0)
            for n, l, reason in plan.flagged:
                flags.append(("%s %s (%s)" % (stock, n, fmt(l)), reason))
            if len(plan):
                say("")
                say("  %s  -- %d board(s) of %s"
                    % (stock, len(plan), fmt_stock(plan[0].length)))
                for i, b in enumerate(plan, 1):
                    cuts = ", ".join("%s (%s)" % (n, fmt(l)) for n, l in b.cuts)
                    say("    #%d: %s" % (i, cuts))
                    say("        offcut %s" % fmt(b.offcut))
                buy.append("%d x %s @ %s"
                           % (len(plan), stock, fmt_stock(plan[0].length)))

        # --- sheet goods, grouped by thickness ----------------------------
        by_sheet = {}
        for p in sheets:
            by_sheet.setdefault(p.stock, []).append(p)

        for stock in sorted(by_sheet):
            items = []
            for p in by_sheet[stock]:
                dims = sorted(p.nominal, reverse=True)
                # A sheet part IS the trimmed panel, so both faces grow by the
                # part's oversize (default when None). Set oversize=0 on a part
                # whose trimming happens at the assembly, not the part.
                ov = oversize if p.oversize is None else p.oversize
                items.append((p.name, dims[0] + ov, dims[1] + ov))

            sp = wwcut.choose_sheets(items, sheet_sizes, kerf, allow_rotate,
                                     max_length, edge_trim, sheet_piece, packer,
                                     0.0)
            for note in sp.notes:
                say("")
                say("  NOTE (%s sheet): %s" % (stock, note))
            for n, pl, pw, reason in sp.flagged:
                flags.append(("%s %s (%s x %s)"
                              % (stock, n, fmt(pl), fmt(pw)), reason))

            for sb in sp.buys:
                piece_of = ("" if sb.piece_name == "full"
                            else " %s piece" % sb.piece_name)
                say("")
                say("  %s sheet  -- %d x %s%s (%s x %s), from %d full %s sheet(s) [%s]"
                    % (stock, len(sb.pieces), sb.sheet_name, piece_of,
                       fmt_stock(sb.piece[0]), fmt_stock(sb.piece[1]),
                       sb.full_sheets, sb.sheet_name, sb.engine))
                say("      %.0f%% of the bought material used%s"
                    % (sb.yield_pct, "" if allow_rotate else ", grain respected"))
                for i, s in enumerate(sb.pieces, 1):
                    say("    piece #%d:" % i)
                    for strip in s.strips:
                        parts = ", ".join("%s (%s x %s)" % (n, fmt(pl), fmt(pw))
                                          for n, pl, pw in strip["parts"])
                        say("      rip %s wide: %s" % (fmt(strip["depth"]), parts))

                if sb.piece_name == "full":
                    buy.append("%d x %s %s full sheet"
                               % (sb.full_sheets, stock, sb.sheet_name))
                else:
                    cut = ("cut in half" if sb.piece_name == "half"
                           else "ripped in half lengthwise")
                    spare = ((", %d spare" % sb.spare_pieces)
                             if sb.spare_pieces else "")
                    buy.append("%d x %s %s full sheet (%s at the store%s)"
                               % (sb.full_sheets, stock, sb.sheet_name, cut, spare))

        if skipped:
            say("")
            say("  NOTE: %d part(s) not planned (made with box(), so no stock): %s"
                % (len(skipped), ", ".join(p.name for p in skipped)))

        if flags:
            say("")
            say("FLAGGED   %d part(s) cannot meet the size limits:" % len(flags))
            for what, reason in flags:
                say("  ! %s: %s" % (what, reason))

        say("")
        say("BUY       " + ("; ".join(buy) if buy else "nothing to plan"))
        say("=" * 64)
        return buy

    def filament(self, density=PLA_DENSITY):
        printed = self.of_kind("printed")
        if not printed:
            return 0.0
        grams = sum(p.shape.Volume / 1000.0 * density for p in printed)
        each = printed[0].shape.Volume / 1000.0 * density
        say("FILAMENT  %d part(s), %.1f g each, %.0f g total (%.0f%% of a 1kg spool)"
            % (len(printed), each, grams, grams / 10.0))
        return grams

    # -- finish -----------------------------------------------------------
    def _stamp_interop(self):
        """Tag parts with the dprojects/Woodworking property convention.

        That addon's report tool reads Width/Height/Length off Part::Box, and
        silently *drops* anything else — including boolean results like ours,
        which is every part with a joint cut into it. Stamping the properties it
        looks for means a user who opens our document in FreeCAD's GUI with the
        addon installed gets a working cut list, instead of a blank one.

        Cheap interop. We do not depend on the addon; this just doesn't preclude
        it. (Their tooling is GUI/Selection-bound and cannot be called headless,
        so importing it was never an option.)
        """
        for p in self.parts:
            b = p.shape.BoundBox
            for prop, val in (
                ("Woodworking_Length", b.XLength),
                ("Woodworking_Width", b.YLength),
                ("Woodworking_Height", b.ZLength),
            ):
                try:
                    if not hasattr(p.obj, prop):
                        p.obj.addProperty("App::PropertyLength", prop, "Woodworking")
                    setattr(p.obj, prop, val)
                except Exception:
                    pass  # interop is a nicety; never fail a build over it

    def finish(self, out_dir, stl_of=None, step=True):
        self.doc.recompute()
        self._stamp_interop()
        self._style()

        base = os.path.join(out_dir, self.doc.Name)
        self.doc.saveAs(base + ".FCStd")
        written = [base + ".FCStd"]
        self._write_intent(out_dir)

        printed = self.of_kind("printed")
        if printed:
            target = next((p for p in printed if p.name == stl_of), printed[0])
            Mesh.export([target.obj], base + ".stl")
            written.append(base + ".stl")

        if step and self.parts:
            import Import

            Import.export([p.obj for p in self.parts], base + ".step")
            written.append(base + ".step")

        say("WROTE     " + ", ".join(os.path.basename(w) for w in written))

        # `fcrun --gui` is a one-shot build (it exists to bake view state into
        # the document), not a session. Close ourselves, or we leak a FreeCAD
        # window that no watcher is listening to — and so one fcquit cannot
        # close, leaving a hard kill as the only way out. fclive clears this.
        if App.GuiUp and os.environ.get("WW_GUI_ONESHOT"):
            import FreeCADGui as Gui

            say("EXIT      one-shot GUI build complete, closing")
            for name in list(App.listDocuments()):
                try:
                    App.closeDocument(name)
                except Exception:
                    pass
            Gui.getMainWindow().close()

        return written

    def _write_intent(self, out_dir):
        """Record where the script *meant* to put each part.

        This is what lets the loop run both ways. When the user drags a part in
        the GUI, fcsnap diffs the live placement against this file, and the move
        becomes a concrete proposal ("Panel_Left moved +12mm in X") that can be
        folded back into the script — instead of being silently destroyed by the
        next rebuild.
        """
        intent = {
            "doc": self.doc.Name,
            "parts": {
                p.name: {
                    "kind": p.kind,
                    "pos": list(p.obj.Placement.Base),
                    "yaw": p.obj.Placement.Rotation.toEuler()[0],
                }
                for p in self.parts
            },
        }
        path = os.path.join(out_dir, self.doc.Name + ".intent.json")
        with open(path, "w") as fh:
            json.dump(intent, fh, indent=2)
        App.__ww_intent__ = path  # breadcrumb the live watcher can find
        return path

    def _style(self):
        """Colour and reveal parts. Silently skipped headless (no ViewObject)."""
        if not App.GuiUp:
            say("VIEW      skipped (headless - no view providers)")
            return
        import FreeCADGui as Gui

        for p in self.parts:
            vo = p.obj.ViewObject
            color, transp = KIND_STYLE.get(p.kind, KIND_STYLE_DEFAULT)
            vo.ShapeColor = color
            vo.Transparency = transp
            vo.Visibility = True
        say("VIEW      %d part(s) coloured and shown" % len(self.parts))
        Gui.updateGui()


def _bbox_dims(shape):
    b = shape.BoundBox
    return [b.XLength, b.YLength, b.ZLength]
