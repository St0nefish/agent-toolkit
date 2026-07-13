"""Watch a model script and rebuild it in the open FreeCAD window on change.

The point is that the human never closes the file. They pan, rotate, isolate;
the agent edits the script; the model updates underneath them with the camera
where they left it. That is the loop OpenSCAD gets right and stock FreeCAD
does not.

Camera is captured before the rebuild and restored after, because the rebuild
closes and recreates the document (wwkit.Model does this by name, which is
what stops FreeCAD from silently stacking up model001, model002, ...).

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


def _rebuild():
    view = _view()
    if view is not None:
        try:
            _state["camera"] = view.getCamera()
        except Exception:
            pass

    # Drop wwkit from the module cache so edits to the library take effect too,
    # not just edits to the model script. Without this, `import wwkit` is a
    # no-op after the first build and library changes look silently ignored.
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
    try:
        os.remove(STOP)
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


def _snapshot(out_dir):
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

        view = gdoc.activeView()
        png = os.path.join(out_dir, "%s.snap.png" % doc.Name)
        view.saveImage(png, 1400, 1000, "Current")
        result["png"] = png

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
    try:
        with open(SNAP) as fh:
            out_dir = fh.read().strip()
    except OSError:
        out_dir = os.path.dirname(SCRIPT)
    if not out_dir:
        out_dir = os.path.dirname(SCRIPT)

    result = _snapshot(out_dir)
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


def _tick():
    if STOP and os.path.exists(STOP):
        _quit()
        return

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
