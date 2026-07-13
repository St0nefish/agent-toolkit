"""Render an .FCStd to PNGs, then quit. Driven by fcrender via env vars.

Runs under the FreeCAD GUI because image capture needs a real view provider and
a GL context — there is no headless render path.

Two hard-won constraints shape this file:

* Under the GUI, FreeCAD rebinds Python's stdout to its Report View, so print()
  never reaches the calling process. Anything the caller must see goes to
  $FCRENDER_LOG.
* If capture() raises, the exception surfaces only in that Report View and the
  window sits open forever — an invisible hang. So capture() can never be
  allowed to leave the window open: it closes in a finally, and a watchdog
  closes it regardless if capture never returns at all.

A headless-authored document opens with every object hidden (no view providers
were ever created), so anything not explicitly shown renders as an empty frame.
"""

import os
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

DOC = os.environ["FCRENDER_DOC"]
OUT = os.environ["FCRENDER_OUT"]
LOG = os.environ.get("FCRENDER_LOG")
VIEWS = os.environ.get("FCRENDER_VIEWS", "iso,front,top,right").split(",")
W = int(os.environ.get("FCRENDER_W", "1200"))
H = int(os.environ.get("FCRENDER_H", "900"))
WATCHDOG_MS = int(os.environ.get("FCRENDER_WATCHDOG_MS", "45000"))

SETTERS = {
    "iso": "viewAxonometric",
    "axo": "viewAxonometric",
    "front": "viewFront",
    "rear": "viewRear",
    "top": "viewTop",
    "bottom": "viewBottom",
    "left": "viewLeft",
    "right": "viewRight",
}

SETTLE_MS = int(os.environ.get("FCRENDER_SETTLE_MS", "700"))

_done = {"finished": False}


def _settle(ms):
    """Pump the event loop so a camera animation can finish before capture."""
    deadline = QtCore.QElapsedTimer()
    deadline.start()
    while deadline.elapsed() < ms:
        QtCore.QCoreApplication.processEvents(
            QtCore.QEventLoop.AllEvents, 50
        )


def say(msg):
    print(msg)
    if LOG:
        try:
            with open(LOG, "a") as fh:
                fh.write(str(msg) + "\n")
        except OSError:
            pass


def shutdown():
    """Close documents via the API (silent) so the window has nothing to ask
    about, then close the window. Never leaves a live instance behind."""
    for name in list(App.listDocuments()):
        try:
            App.closeDocument(name)
        except Exception:
            pass
    try:
        Gui.getMainWindow().close()
    except Exception:
        pass
    # Closing the window leaves the event loop running; quit the app outright.
    QtCore.QCoreApplication.quit()


def capture():
    try:
        doc = App.openDocument(DOC)

        # Respect the document's own visibility. A doc saved from a GUI run has
        # real parts shown and construction geometry (cut tools, un-cut stock)
        # hidden; force-showing everything drags that scratch back into frame.
        #
        # Only if NOTHING is visible do we force parts on — that is the
        # headless-authored case, where no view provider ever existed and the
        # whole document would otherwise photograph as an empty scene.
        solids = [
            o for o in doc.Objects
            if getattr(o, "ViewObject", None) is not None
            and getattr(o, "Shape", None) is not None
            and o.Shape.Volume > 0
        ]
        visible = [o for o in solids if o.ViewObject.Visibility]
        if not visible:
            say("RENDER    document had nothing visible (headless-authored) - showing all")
            for o in solids:
                o.ViewObject.Visibility = True
            visible = solids
        shown = len(visible)

        view = Gui.activeDocument().activeView()
        for name in VIEWS:
            setter = SETTERS.get(name.strip())
            if not setter:
                say("RENDER    unknown view %r, skipped" % name)
                continue
            getattr(view, setter)()
            Gui.SendMsgToActiveView("ViewFit")
            # FreeCAD animates camera moves. Without letting that finish we
            # photograph the camera in mid-flight — a "top" view rendered
            # straight after an "iso" view comes out as a three-quarter shot,
            # which is worse than useless: it looks plausible and is wrong.
            _settle(SETTLE_MS)
            path = os.path.join(OUT, "%s.png" % name.strip())
            view.saveImage(path, W, H, "Current")
            say("RENDER    %s" % path)

        say("RENDER    ok - %d object(s) visible" % shown)
    except Exception:
        say("RENDER    FAILED")
        say(traceback.format_exc())
    finally:
        _done["finished"] = True
        shutdown()


def watchdog():
    if not _done["finished"]:
        say("RENDER    watchdog fired after %dms - closing" % WATCHDOG_MS)
        shutdown()


# Give the GUI a moment to finish coming up before grabbing frames from it.
QtCore.QTimer.singleShot(1500, capture)
# Belt and braces: never leave an instance wedged open on an unforeseen stall.
QtCore.QTimer.singleShot(WATCHDOG_MS, watchdog)
