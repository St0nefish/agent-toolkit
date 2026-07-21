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

# A panel declares a sheet-goods *quality* (a wwcut.MATERIALS key) plus a nominal
# thickness label; the actual mm the solid is built at comes from here. The model
# picks the quality; the yield/sourcing is the cut plan's job. Keep these in step
# with any thickness label offered by the matching wwcut sheet material.
SHEET_ACTUAL = {
    "mdf": MDF,
    "pine-ply": PLY,
    "solid-core": PLY,
    "birch-ply": {"1/2": 12.0, "3/4": 18.0},  # Baltic is sold metric
    "laminate": {"1.2mm": 1.2},               # plastic laminate (Formica)
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
    """One real part: a named solid with a material role.

    A part declares WHAT it is made of (a `material` type from wwcut.MATERIALS,
    plus a `thickness` label where the family needs one) — never a stock size.
    The finished cross-section and length come from the solid; turning the type
    into "buy N of this nominal, cut it thus" is the cut plan's job.
    """

    def __init__(self, obj, kind, nominal=None, material=None, thickness=None,
                 rip_with=None, from_scrap=False, oversize=None, grain=None,
                 grain_seq=None, plan_length=None, plan_width=None):
        self.obj = obj
        self.kind = kind  # "wood" | "printed"
        self.nominal = nominal  # (dx, dy, dz) as authored, for the cut list
        self.material = material  # wwcut.MATERIALS key, or None -> not planned
        self.thickness = thickness  # thickness label where the family needs one
        # The DECLARED length and rip width, when the constructor knew them
        # (board()/panel() take them explicitly). The cut plan uses these instead
        # of guessing length/width by sorting the bbox — a part wider than it is
        # long (a squat dimensional board) would otherwise get the two swapped,
        # hiding a "wider than any nominal" flag. None -> fall back to the sort.
        self.plan_length = plan_length
        self.plan_width = plan_width
        # This part is ripped from a sibling's blank (an adjacent profile on the
        # same stick): it names the bearer part and is counted on the bearer's
        # blank, not bought on its own.
        self.rip_with = rip_with
        # Cut from offcut/scrap, not bought: reported but never added to the buy.
        self.from_scrap = from_scrap
        # Face-grain lock for THIS sheet part: None follows the material default
        # (plywood rotates freely), True pins the grain (no rotation) for a show
        # veneer, False forces rotation even on a grain-locked material.
        self.grain = grain
        # Continuous-grain sequence label: parts sharing one are cut consecutively
        # from a single board/sheet, in model order, so the grain flows across
        # them (a drawer-front bank, a wrapped edge band).
        self.grain_seq = grain_seq
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
    def add(self, name, shape, kind="wood", nominal=None, material=None,
            thickness=None, rip_with=None, from_scrap=False, oversize=None,
            grain=None, grain_seq=None, plan_length=None, plan_width=None):
        o = self.doc.addObject("Part::Feature", name)
        o.Shape = shape
        p = Part_(o, kind, nominal=nominal, material=material,
                  thickness=thickness, rip_with=rip_with, from_scrap=from_scrap,
                  oversize=oversize, grain=grain, grain_seq=grain_seq,
                  plan_length=plan_length, plan_width=plan_width)
        self.parts.append(p)
        return p

    def box(self, name, dx, dy, dz, at=(0, 0, 0), kind="wood", material=None,
            thickness=None, rip_with=None, from_scrap=False, oversize=None,
            grain=None, grain_seq=None):
        """A plain rectangular solid. Pass a `material` type to have cutplan
        source it (e.g. material="hardwood" for an edge band, "laminate" for a
        Formica facing); leave it off and it is a shape the plan skips. Set
        from_scrap=True for a part cut from offcuts (reported, never bought).
        grain=True pins a sheet part's grain; grain_seq="label" ties parts into a
        continuous-grain run."""
        return self.add(name, solid(dx, dy, dz, at), kind, nominal=(dx, dy, dz),
                        material=material, thickness=thickness, rip_with=rip_with,
                        from_scrap=from_scrap, oversize=oversize, grain=grain,
                        grain_seq=grain_seq)

    def strip(self, name, shape, material="hardwood", thickness="4/4",
              rip_with=None, kind="wood", oversize=None, grain=None,
              grain_seq=None):
        """A part cut from stock whose shape is not a plain board() box — a
        ripped hardwood cleat, an angled edge band, an on-edge ply strip.
        cutplan sources it from `material`: its longest bounding dimension is the
        length, the next is the rip width, and the material's own thickness is
        the third.

        `shape` is any already-built Part shape (e.g. from ww.prism/wedge). Pass
        rip_with="OtherPart" when this rides an adjacent profile on a sibling's
        blank (an interlocking key on a cleat's stick) — it is then counted on
        that blank, not bought on its own."""
        bb = shape.BoundBox
        return self.add(name, shape, kind,
                        nominal=(bb.XLength, bb.YLength, bb.ZLength),
                        material=material, thickness=thickness, rip_with=rip_with,
                        oversize=oversize, grain=grain, grain_seq=grain_seq)

    def board(self, name, length, width, at=(0, 0, 0),
              length_axis="x", thickness_axis="z", material="framing",
              thickness=None, kind="wood", oversize=None):
        """A board of dimensional lumber, sized to its FINISHED cross-section.

        `material` is a type (default "framing"); the thickness comes from that
        material unless given explicitly, and `width` is the finished width you
        design. The cut plan decides how to buy it — the exact nominal as-is, or
        clean strips ripped from a wider board. Orientation is two axes because
        one is ambiguous: a board flat and the same board on edge share a length
        axis but are different parts. Width takes the axis left over.
        """
        import wwcut
        spec = wwcut.MATERIALS.get(material)
        if spec is None:
            raise KeyError("unknown material %r; known: %s"
                           % (material, ", ".join(sorted(wwcut.MATERIALS))))
        t = spec.get("thick") if thickness is None else thickness
        if t is None:
            raise ValueError("material %r has no fixed thickness; pass thickness="
                             % material)
        if length_axis == thickness_axis:
            raise ValueError("length and thickness cannot share an axis")
        width_axis = ({"x", "y", "z"} - {length_axis, thickness_axis}).pop()
        by_axis = {length_axis: length, thickness_axis: t, width_axis: width}
        dims = (by_axis["x"], by_axis["y"], by_axis["z"])
        return self.add(name, solid(*dims, at=at), kind, nominal=dims,
                        material=material, thickness=thickness, oversize=oversize,
                        plan_length=length, plan_width=width)

    def panel(self, name, length, width, at=(0, 0, 0), thickness_axis="z",
              material="pine-ply", thickness="3/4", kind="wood", oversize=None,
              grain=None, grain_seq=None):
        """A sheet-goods panel. `material` is a quality (a wwcut sheet type:
        mdf / pine-ply / birch-ply / solid-core / laminate); `thickness` is a
        nominal label. The solid is built at the real mm from SHEET_ACTUAL, and
        the cut plan nests it onto that quality's sheet sizes.

        thickness_axis matters: a cabinet bottom is thick in Z, a back panel is
        thick in Y. Getting it wrong produces the right area at a nonsense
        thickness.
        """
        table = SHEET_ACTUAL.get(material)
        if table is None:
            raise KeyError("unknown sheet material %r; known: %s"
                           % (material, ", ".join(sorted(SHEET_ACTUAL))))
        if thickness not in table:
            raise KeyError("no actual thickness for %r %r; known: %s"
                           % (material, thickness, ", ".join(sorted(table))))
        t = table[thickness]
        others = [a for a in "xyz" if a != thickness_axis]
        by_axis = {thickness_axis: t, others[0]: length, others[1]: width}
        dims = (by_axis["x"], by_axis["y"], by_axis["z"])
        return self.add(name, solid(*dims, at=at), kind, nominal=dims,
                        material=material, thickness=thickness, oversize=oversize,
                        grain=grain, grain_seq=grain_seq,
                        plan_length=length, plan_width=width)

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
        # Validate the shape BEFORE destructuring, so a short/malformed face
        # ("q", "") raises a clear ValueError rather than an IndexError.
        if len(face) != 2 or face[0] not in "+-" or face[1] not in "xyz":
            raise ValueError("face must be like '+x', got %r" % face)
        sign, nax = face[0], face[1]
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
        """Shortest distance between two parts, in mm.

        `distToShape` reports 0 for intersecting solids, so it cannot measure
        penetration depth — overlap is detected from shared volume instead and
        reported explicitly, with a negative return value to flag it.
        """
        common = a.shape.common(b.shape).Volume
        if common > 1e-6:
            say("GAP       %s <-> %s  OVERLAP (%.0f mm^3 shared)"
                % (a.name, b.name, common))
            return -1.0
        d = a.shape.distToShape(b.shape)[0]
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
            mat = p.material or ""
            if p.thickness:
                mat = "%s %s" % (mat, p.thickness)
            rows.append((p.name, mat, dims))
            say("  %-16s %-14s %8s x %8s x %8s"
                % (p.name, mat, fmt(dims[0]), fmt(dims[1]), fmt(dims[2])))
        return rows

    def cutplan(self, kerf=None, end_trim=None, edge_trim=None, oversize=None,
                prefer="value", tooling=None, packer="auto", materials=None):
        """From a parts list to a shopping list and a cutting order.

        `cutlist()` says what parts you need. This says what to *buy*, and how to
        break each board or sheet down — the thing you take to the yard and the
        saw. Parts declare a material *type*, not a stock size, so each material
        group gets a small ranked set of sourcing OPTIONS: the recommended one is
        printed in full (buy line, board-feet or sheets, cost tier, cut layout),
        the alternatives collapse to one line each ("also works: ...").

        prefer     how to rank within a type: "value" (default — best quality per
                   tier, then least material), "cost", or "quality".
        end_trim   squared off each board end before packing (default 1").
        edge_trim  trimmed off each sheet edge before packing (default 1/2").
        oversize   default rough-cut allowance per part (default 1/8"): parts are
                   cut oversize and trimmed to final for clean edges. Any part can
                   override via board()/panel()/box/strip(oversize=...) — set 0
                   for a part already at final size, or a glue-up member trimmed
                   at the assembly (put the allowance on the assembly instead).
        tooling    the shop's tool allowances (wwcut.TOOLING); edge_cleanup is the
                   rip-edge clean-up a rip-from-wider plan spends per squared edge.
        packer     2-D engine. "auto"/"rectpack" both try rectpack (when it is
                   importable and its layout reduces to clean rips) and fall back
                   to the built-in shelf packer; "shelf" forces the shelf packer.
        materials  per-call overrides for the catalog, e.g.
                   {"birch-ply": {"sizes": [(30*IN, 20*IN, "20x30")]}} — merged
                   over wwcut.MATERIALS for THIS call only, so a model tunes stock
                   sizes/tiers without mutating the shared global registry.

        Transport is not a constraint: the planner nests onto full stock and
        annotates ("could be store-cut in half"). A part with no material is
        skipped (nothing to buy); from_scrap parts are reported, never bought.
        Returns the list of OptionSet objects (one per material group).
        """
        import wwcut

        kerf = wwcut.KERF if kerf is None else kerf
        end_trim = wwcut.END_TRIM if end_trim is None else end_trim
        edge_trim = wwcut.EDGE_TRIM if edge_trim is None else edge_trim
        oversize = wwcut.OVERSIZE if oversize is None else oversize
        tooling = wwcut.TOOLING if tooling is None else tooling

        # Effective catalog: the shared registry, with any per-call overrides
        # shallow-merged over the matching material spec. Never mutates the
        # global, so one model's stock-size tweak can't leak into another.
        reg = wwcut.MATERIALS
        if materials:
            reg = dict(wwcut.MATERIALS)
            for _k, _ov in materials.items():
                reg[_k] = {**wwcut.MATERIALS.get(_k, {}), **_ov}

        planned = [p for p in self.parts if p.material and not p.from_scrap]
        scrap = [p for p in self.parts if p.from_scrap]
        skipped = [p for p in self.parts
                   if p.kind == "wood" and not p.material and not p.from_scrap]

        # rip_with children ride a bearer's blank: fold each into its bearer.
        riders = {}
        for p in planned:
            if p.rip_with:
                riders.setdefault(p.rip_with, []).append(p)

        # grain_seq members: parts cut consecutively from one board, in model
        # order, so the grain flows across them.
        seq_members = {}
        for p in planned:
            if p.grain_seq and not p.rip_with:
                seq_members.setdefault(p.grain_seq, []).append(p)

        def dims_of(p):
            # Prefer the length/width the constructor declared; only guess by
            # sorting the bbox (longest = length) when they are unknown (strip/
            # box), where the part really is long-and-narrow by construction.
            if p.plan_length is not None:
                return p.plan_length, p.plan_width
            d = sorted(p.nominal or _bbox_dims(p.shape), reverse=True)
            return d[0], d[1]   # length, rip width (thickness = d[2], material's)

        def rough_len(p):       # per-part oversize grows length always
            ov = oversize if p.oversize is None else p.oversize
            return dims_of(p)[0] + ov

        def rough_wid(p):       # width grows too (sheet parts trim both faces)
            ov = oversize if p.oversize is None else p.oversize
            return dims_of(p)[1] + ov

        # Group by (material, thickness). Each entry is (name, length, width, ov,
        # grain): ov is the per-part rough allowance still to apply, grain is the
        # rotation preference (None=material default, True=pin, False=force-rot).
        groups = {}
        seq_map = {}     # block label -> ordered [(member, rough_len, rough_wid)]
        seq_done = set()
        for p in planned:
            if p.rip_with:
                continue
            if p.grain_seq:
                if p.grain_seq in seq_done:
                    continue
                seq_done.add(p.grain_seq)
                members = seq_members[p.grain_seq]
                mat, thk = members[0].material, members[0].thickness
                mdims = [(mp.name, rough_len(mp), rough_wid(mp)) for mp in members]
                # One contiguous block: members stacked end-to-end along the grain
                # (length), width = widest member. Oversize is already folded in,
                # so ov=0 below; grain is pinned (True) — a sequence has a run
                # direction. If the block outgrows every board it will flag.
                comb_len = sum(d[1] for d in mdims) + kerf * (len(mdims) - 1)
                comb_wid = max(d[2] for d in mdims)
                seq_map[p.grain_seq] = mdims
                groups.setdefault((mat, thk), []).append(
                    (p.grain_seq, comb_len, comb_wid, 0.0, True))
                continue
            length, width = dims_of(p)
            ov = oversize if p.oversize is None else p.oversize
            name = p.name
            kids = riders.get(p.name, [])
            if kids:
                # Fold the co-located rips onto one blank: blank length is the
                # longest member (each grown by its OWN oversize), width is the
                # profiles stacked with a kerf between. Oversize is folded in
                # here, so this entry carries ov=0 (a bearer and its riders can
                # each want a different rough-length allowance).
                length += ov
                for kid in kids:
                    kov = oversize if kid.oversize is None else kid.oversize
                    kl, kw = dims_of(kid)
                    length = max(length, kl + kov)
                    width += kw + kerf
                    name = "%s+%s" % (name, kid.name)
                ov = 0.0
            groups.setdefault((p.material, p.thickness), []).append(
                (name, length, width, ov, p.grain))

        say("=" * 64)
        say("CUT PLAN  (kerf %s, end-trim %s, edge-trim %s, oversize %s, "
            "prefer %s)" % (fmt(kerf), fmt(end_trim), fmt(edge_trim),
                            fmt(oversize), prefer))
        if oversize:
            say("          part sizes below are rough (cut oversize, trim to final)")

        buy = []
        results = []
        for key in sorted(groups, key=lambda k: (k[0], k[1] or "")):
            material, thickness = key
            spec = reg[material]
            sheet_fam = spec["family"] == "sheet"
            mat_grain = spec.get("grain", False)
            # Apply each part's own oversize up front (source_options takes one
            # scalar), and resolve rotation per part. A board/hardwood strip grows
            # in LENGTH only (its rip width is cut to final); a sheet part grows
            # in both faces and carries a per-part rotation flag.
            parts = []
            for (n, l, w, ov, grain) in groups[key]:
                if sheet_fam:
                    rot = (not mat_grain) if grain is None else (not grain)
                    parts.append((n, l + ov, w + ov, rot))
                else:
                    parts.append((n, l + ov, w))
            opt = wwcut.source_options(parts, material, thickness, kerf, end_trim,
                                       edge_trim, 0.0, prefer, tooling, packer,
                                       registry=reg)
            if seq_map:
                for o in opt.options:
                    self._expand_seq(o, seq_map)
            results.append(opt)
            self._say_options(opt, buy)

        flagged_seq = {n for opt in results for (n, _r) in opt.flagged
                       if n in seq_map}
        for label in seq_map:
            names = ", ".join(m[0] for m in seq_map[label])
            say("")
            if label in flagged_seq:
                say("  GRAIN SEQ (%s): %s -- the run is bigger than one board; "
                    "split it to keep the grain continuous" % (label, names))
            else:
                say("  GRAIN SEQ (%s): %s -- cut consecutively from one board, "
                    "in order, for continuous grain" % (label, names))

        if scrap:
            say("")
            say("  FROM SCRAP (%d part(s), cut from offcuts, not bought): %s"
                % (len(scrap), ", ".join(p.name for p in scrap)))
        if skipped:
            say("")
            say("  NOTE: %d part(s) not planned (no material declared): %s"
                % (len(skipped), ", ".join(p.name for p in skipped)))

        say("")
        say("BUY       " + ("; ".join(buy) if buy else "nothing to plan"))
        say("=" * 64)
        return results

    # -- cutplan rendering ------------------------------------------------
    def _buylines(self, opt):
        """A sourcing option's shopping line(s), e.g. '6 x 2x4 @ 8 ft'."""
        out = []
        for b in opt.buy:
            s = "%d x %s" % (b["count"], b["nominal"])
            if b.get("min_width") is not None:
                s += " >=%s wide" % fmt(b["min_width"])
            if b.get("length") is not None:
                s += " @ %s" % fmt_stock(b["length"])
            out.append(s)
        return out

    def _amount(self, opt):
        if opt.board_feet is not None:
            return "%.1f bd-ft" % opt.board_feet
        return "%d sheet(s)" % opt.sheet_count

    def _say_layout(self, opt):
        if opt.layout_kind == "boards":
            for i, b in enumerate(opt.layout, 1):
                cuts = ", ".join("%s (%s)" % (n, fmt(l)) for n, l in b.cuts)
                say("      #%d [%s, offcut %s]: %s"
                    % (i, fmt_stock(b.length), fmt(b.offcut), cuts))
        else:  # sheets / ripped boards, cut as rip strips then crosscuts
            for i, s in enumerate(opt.layout, 1):
                say("      board/sheet #%d:" % i)
                for strip in s.strips:
                    parts = ", ".join("%s (%s x %s)" % (n, fmt(pl), fmt(pw))
                                      for n, pl, pw in strip["parts"])
                    say("        rip %s wide: %s" % (fmt(strip["depth"]), parts))

    def _expand_seq(self, opt, seq_map):
        """Unfold a nested grain-sequence block into its member cuts, in order.

        The block was packed as one contiguous part so it is guaranteed to come
        off a single board; here it is replaced by its members laid consecutively
        (which is the continuous-grain cut order) wherever it landed.
        """
        if opt.layout_kind == "boards":
            for b in opt.layout:
                cuts = []
                for (nm, ln) in b.cuts:
                    if nm in seq_map:
                        cuts.extend((mn, ml) for (mn, ml, _mw) in seq_map[nm])
                    else:
                        cuts.append((nm, ln))
                b.cuts = cuts
        else:
            for s in opt.layout:
                for strip in s.strips:
                    parts = []
                    for (nm, pl, pw) in strip["parts"]:
                        if nm in seq_map:
                            parts.extend(seq_map[nm])
                        else:
                            parts.append((nm, pl, pw))
                    strip["parts"] = parts

    def _say_options(self, opt, buy):
        head = opt.material + ((" %s" % opt.thickness) if opt.thickness else "")
        rec = opt.recommended
        if rec is None:
            say("")
            say("  %s -- nothing planned" % head)
            for n, reason in opt.flagged:
                say("    ! %s: %s" % (n, reason))
            return

        say("")
        say("  %s -- %s   (%s, %s)"
            % (head, ", ".join(self._buylines(rec)), self._amount(rec), rec.tier))
        if rec.tradeoffs:
            say("      %s" % ", ".join(rec.tradeoffs))
        for note in rec.annotations:
            say("      note: %s" % note)
        self._say_layout(rec)

        for alt in opt.alternatives:
            extra = (" [%s]" % ", ".join(alt.tradeoffs)) if alt.tradeoffs else ""
            say("      also works: %s  --  %s, %s%s"
                % (", ".join(self._buylines(alt)), self._amount(alt),
                   alt.tier, extra))
        for n, reason in opt.flagged:
            say("    ! %s: %s" % (n, reason))

        buy.extend(self._buylines(rec))

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
