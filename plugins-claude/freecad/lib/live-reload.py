"""Watch a model script and rebuild it in the open FreeCAD window on change.

The point is that the human never closes the file. They pan, rotate, isolate;
the agent edits the script; the model updates underneath them with the camera
where they left it. That is the loop OpenSCAD gets right and stock FreeCAD
does not.

Camera is captured before the rebuild and restored after. wwkit.Model now
rebuilds the document in place, so the view -- and with it the camera -- survives
on its own; this is kept as a safety net for models that recreate a document
themselves. Do not "optimise" it into a reason to close documents again: closing
one under the GUI destroys its view, and creating the replacement raises the
window over whatever the human is doing, on every single reload.

A script that raises leaves the previous model on screen and prints the
traceback — a typo shouldn't blank the window mid-conversation.
"""

import json
import os
import sys
import traceback

import FreeCAD as App
import FreeCADGui as Gui
# FreeCAD bundles a `PySide` shim re-exporting whatever binding it was built
# against (PySide2/Qt5 or PySide6/Qt6). That shim is reported broken on some
# Linux distro packages, and an unguarded import here would take the whole tool
# down with an ImportError. Fall through to the real bindings.
try:
    from PySide import QtCore
except ImportError:  # pragma: no cover - distro-dependent
    try:
        from PySide6 import QtCore
    except ImportError:
        from PySide2 import QtCore

SCRIPT = os.environ["WW_WATCH"]
POLL_MS = int(os.environ.get("WW_POLL_MS", "1000"))
LOG = os.environ.get("WW_LOG")
STOP = os.environ.get("WW_STOP")
SNAP = os.environ.get("WW_SNAP")
OPEN = os.environ.get("WW_OPEN")
PID = os.environ.get("WW_PID")

# Record THIS FreeCAD process's pid so fcquit can tell whether *this* session is
# still up (see fcsession _fc_session_running) instead of grepping for any
# FreeCAD. Removed again in _quit() on a clean shutdown.
if PID:
    try:
        with open(PID, "w") as _fh:
            _fh.write(str(os.getpid()))
    except OSError:
        pass

_state = {"mtime": 0.0, "camera": None, "builds": 0}


def _say(msg):
    """Under the GUI, print() goes to FreeCAD's Report View, not to stdout.
    Anyone watching the process pipe sees silence — so write the file too."""
    print(msg)
    if LOG:
        try:
            with open(LOG, "a") as fh:
                fh.write(str(msg) + "\n")
        except OSError:
            pass


def _view():
    doc = Gui.activeDocument()
    return doc.activeView() if doc else None


def _apply_view_prefs(view):
    """One-time: make orbiting sane for furniture/woodworking. FreeCAD ships with
    Trackball orbit, which tumbles the model and loses 'up' -- disorienting for a
    model that has an obvious floor and top. Gesture navigation + Turntable orbit
    (spin about vertical, tilt) + rotate-at-cursor is far better here."""
    try:
        p = App.ParamGet("User parameter:BaseApp/Preferences/View")
        p.SetString("NavigationStyle", "Gui::GestureNavigationStyle")
        p.SetInt("OrbitStyle", 0)     # 0 = Turntable (keeps the up vector)
        p.SetInt("RotationMode", 1)   # 1 = rotate about the cursor
    except Exception:
        pass
    try:
        view.setNavigationType("Gui::GestureNavigationStyle")
    except Exception:
        pass
    _say("LIVE      view: Gesture nav + Turntable orbit + rotate-at-cursor")


def _rebuild():
    view = _view()
    if view is not None:
        try:
            _state["camera"] = view.getCamera()
        except Exception:
            pass

    # Drop wwkit from the module cache so edits to the modelling library take
    # effect on the next rebuild, not just edits to the model script. Without
    # this, `import wwkit` is a no-op after the first build and library changes
    # look silently ignored.
    #
    # DESIGN (intentional, do not "fix"): wwcut -- the cut-list engine -- is
    # deliberately NOT popped here, and cutplan()/cutlist() are NOT run on
    # rebuild. The cut list is ON-DEMAND on purpose. A build iterates constantly
    # (dozens of live reloads while shaping the model); recomputing the plan on
    # every one wastes work and has made FreeCAD miss the reload window and
    # wedge. You want the plan a handful of times, not every edit -- so cut-list
    # changes land when you next ASK for it (a WW_REPORT build, or a headless
    # run), not live. Popping wwcut to make it reload live re-introduces exactly
    # the hang this avoids.
    sys.modules.pop("wwkit", None)

    try:
        source = open(SCRIPT).read()
        globals_ = {"__name__": "__main__", "__file__": SCRIPT}
        exec(compile(source, SCRIPT, "exec"), globals_)
    except Exception:
        _say("LIVE      rebuild FAILED - previous model left on screen")
        _say(traceback.format_exc())
        return False

    view = _view()
    if view is not None:
        if _state["camera"] and _state["builds"] > 0:
            try:
                view.setCamera(_state["camera"])
            except Exception:
                Gui.SendMsgToActiveView("ViewFit")
        else:
            if _state["builds"] == 0:
                _apply_view_prefs(view)
            view.viewAxonometric()
            Gui.SendMsgToActiveView("ViewFit")
    _state["builds"] += 1
    return True


def _quit():
    """Shut down without the modal save prompt.

    Closing the main window asks 'save changes?' and blocks forever in an
    automated run. App.closeDocument() discards via the API without asking, so
    close the documents first and the window then has nothing to ask about.
    Discarding is safe by construction: the script is the source of truth and
    the .FCStd is a build artefact.
    """
    _say("LIVE      stop requested, closing cleanly")
    for name in list(App.listDocuments()):
        try:
            App.closeDocument(name)
        except Exception:
            pass
    for _f in (STOP, PID):   # drop the stop request and our pid marker
        try:
            if _f:
                os.remove(_f)
        except OSError:
            pass

    # Closing the main window is not the same as quitting: with no documents
    # left, Qt's event loop happily keeps running and the process lingers (this
    # is normal macOS app behaviour). Ask the application itself to exit, or
    # fcquit times out and the only way out is a kill — which is exactly what
    # poisons the next launch.
    try:
        Gui.getMainWindow().close()
    except Exception:
        pass
    QtCore.QCoreApplication.quit()


_SNAP_VIEWS = {
    "iso": "viewAxonometric", "axo": "viewAxonometric",
    "front": "viewFront", "rear": "viewRear",
    "top": "viewTop", "bottom": "viewBottom",
    "left": "viewLeft", "right": "viewRight",
}


def _settle(ms):
    """Pump the event loop so a camera animation finishes before we grab a frame
    -- otherwise a canned view is photographed mid-flight."""
    t = QtCore.QElapsedTimer()
    t.start()
    while t.elapsed() < ms:
        QtCore.QCoreApplication.processEvents(QtCore.QEventLoop.AllEvents, 50)


def _snapshot(out_dir, view_name=""):
    """Report the live session back to the agent: view, selection, drags.

    Without this the loop only runs one way — the agent pushes geometry and the
    human's manipulation is invisible and destroyed by the next rebuild. Here we
    capture:

      * a PNG of the user's *actual* camera (not a canned view)
      * what they have selected, so "this one" resolves to a name
      * how each part's placement differs from where the script put it

    That last one turns a drag into a proposal the agent can fold back into the
    script, rather than something the next rebuild silently throws away.
    """
    result = {"png": None, "selected": [], "moved": [], "doc": None}
    try:
        gdoc = Gui.activeDocument()
        if gdoc is None:
            result["error"] = "no active document"
            return result
        doc = App.activeDocument()
        result["doc"] = doc.Name

        v = gdoc.activeView()
        # Optional canned view: remember the user's camera, swing to iso/top/...,
        # grab the frame, then snap their camera right back so their view is
        # undisturbed. No new window, no focus steal.
        cam = None
        setter = _SNAP_VIEWS.get(view_name.strip().lower()) if view_name else None
        if setter:
            try:
                cam = v.getCamera()
                getattr(v, setter)()
                Gui.SendMsgToActiveView("ViewFit")
                _settle(600)
                result["view"] = view_name
            except Exception:
                cam = None
        png = os.path.join(out_dir, "%s.snap.png" % doc.Name)
        v.saveImage(png, 1400, 1000, "Current")
        result["png"] = png
        if cam is not None:
            try:
                v.setCamera(cam)
            except Exception:
                pass

        try:
            result["selected"] = [o.Name for o in Gui.Selection.getSelection()]
        except Exception:
            pass

        intent_path = getattr(App, "__ww_intent__", None)
        if intent_path and os.path.exists(intent_path):
            with open(intent_path) as fh:
                intent = json.load(fh)
            for name, want in intent.get("parts", {}).items():
                obj = doc.getObject(name)
                if obj is None:
                    continue
                now = obj.Placement.Base
                dx = now.x - want["pos"][0]
                dy = now.y - want["pos"][1]
                dz = now.z - want["pos"][2]
                dyaw = obj.Placement.Rotation.toEuler()[0] - want.get("yaw", 0.0)
                if max(abs(dx), abs(dy), abs(dz), abs(dyaw)) > 1e-6:
                    result["moved"].append(
                        {
                            "name": name,
                            "kind": want.get("kind"),
                            "delta_mm": [round(dx, 2), round(dy, 2), round(dz, 2)],
                            "delta_yaw_deg": round(dyaw, 2),
                        }
                    )
        else:
            result["note"] = "no intent file - drags cannot be diffed"
    except Exception:
        result["error"] = traceback.format_exc()
    return result


def _handle_snap():
    view_name = ""
    try:
        with open(SNAP) as fh:
            lines = fh.read().splitlines()
        out_dir = lines[0].strip() if lines else ""
        view_name = lines[1].strip() if len(lines) > 1 else ""
    except OSError:
        out_dir = os.path.dirname(SCRIPT)
    if not out_dir:
        out_dir = os.path.dirname(SCRIPT)

    result = _snapshot(out_dir, view_name)
    try:
        with open(os.path.join(out_dir, "snapshot.json"), "w") as fh:
            json.dump(result, fh, indent=2)
    except OSError:
        pass
    try:
        os.remove(SNAP)
    except OSError:
        pass
    _say("SNAP      %d moved, %d selected -> %s"
         % (len(result["moved"]), len(result["selected"]), result.get("png")))


def _handle_open():
    """Open a second document as a TAB in this running instance -- a .py model
    (built fresh) or a .FCStd. Lets the agent inspect one part/joint in isolation
    without a new window. ww.Model only closes its own doc name on rebuild, so
    the extra tab survives the watched script's rebuilds."""
    try:
        with open(OPEN) as fh:
            path = fh.read().strip()
    except OSError:
        path = ""
    try:
        os.remove(OPEN)
    except OSError:
        pass
    if not path or not os.path.exists(path):
        _say("OPEN      no such file: %r" % path)
        return
    try:
        if path.endswith(".py"):
            sys.modules.pop("wwkit", None)  # modelling lib only; wwcut stays
            # cached on purpose -- the cut list is on-demand (see _rebuild note).
            g = {"__name__": "__main__", "__file__": path}
            exec(compile(open(path).read(), path, "exec"), g)
        else:
            App.openDocument(path)
        _say("OPEN      %s -> new tab" % os.path.basename(path))
    except Exception:
        _say("OPEN      FAILED\n" + traceback.format_exc())


def _tick():
    if STOP and os.path.exists(STOP):
        _quit()
        return

    if OPEN and os.path.exists(OPEN):
        _handle_open()

    if SNAP and os.path.exists(SNAP):
        _handle_snap()

    try:
        mtime = os.path.getmtime(SCRIPT)
    except OSError:
        return  # mid-write; try again next tick
    if mtime <= _state["mtime"]:
        return
    _state["mtime"] = mtime
    _say("LIVE      change detected, rebuilding %s" % os.path.basename(SCRIPT))
    if _rebuild():
        _say("LIVE      rebuild #%d ok" % _state["builds"])


_timer = QtCore.QTimer()
_timer.timeout.connect(_tick)
_timer.start(POLL_MS)
App.__ww_live_timer = _timer  # keep a reference or Qt garbage-collects it

_say("LIVE      watching %s (every %dms)" % (SCRIPT, POLL_MS))
_tick()
