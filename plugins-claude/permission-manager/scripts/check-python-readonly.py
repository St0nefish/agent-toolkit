#!/usr/bin/env python3
"""Read Python source from stdin; exit 0 if statically read-only-safe.

Used by the python classifier to auto-allow `python3 -c "..."` invocations
that only read data and produce output. Heuristic: any unsafe construct
falls back to ask, never silently allowed.

Exit codes:
  0 — safe to allow
  1 — unsafe (reason on stdout)
  2 — parse error (reason on stdout)
"""

from __future__ import annotations

import ast
import sys


# Modules whose top-level import is safe — pure parsing, math, text, encoding,
# data-structure utilities. No filesystem writes, no network, no subprocess.
ALLOWED_MODULES = frozenset(
    {
        "json",
        "csv",
        "re",
        "string",
        "textwrap",
        "difflib",
        "math",
        "statistics",
        "decimal",
        "fractions",
        "random",
        "datetime",
        "time",
        "calendar",
        "zoneinfo",
        "collections",
        "collections.abc",
        "itertools",
        "functools",
        "operator",
        "heapq",
        "bisect",
        "array",
        "queue",
        "hashlib",
        "hmac",
        "base64",
        "binascii",
        "codecs",
        "secrets",
        "unicodedata",
        "stringprep",
        "io",
        "typing",
        "dataclasses",
        "enum",
        "types",
        "copy",
        "html",
        "html.parser",
        "html.entities",
        # xml.* modules removed — `xml.etree.ElementTree.write(path)` writes
        # arbitrary files, and `xml.sax.saxutils` exposes `os`/`codecs`/`urllib`.
        # JSON is the dominant use case; XML can fall through to a prompt.
        "urllib.parse",
        "ipaddress",
        "uuid",
        "os.path",
        "posixpath",
        "ntpath",
        "genericpath",
        "sys",
        "pprint",
        "reprlib",
        "abc",
    }
)


# Names that, when called, can sidestep the static check or escape the sandbox.
BANNED_CALLS = frozenset(
    {
        "exec",
        "eval",
        "compile",
        "__import__",
        "getattr",
        "setattr",
        "delattr",
        "vars",
        "globals",
        "locals",
        "breakpoint",
        "input",
        "open",  # handled separately to permit read modes
    }
)


# Dunder attributes that are safe to read. Everything else is rejected to prevent
# the classic `().__class__.__bases__[0].__subclasses__()` escape.
SAFE_DUNDERS = frozenset(
    {
        "__name__",
        "__doc__",
        "__file__",
        "__version__",
        "__main__",
        "__init__",  # __init__ as attr name appears in dataclass-y code
    }
)


# Dunder *Names* (read as a bare identifier, not via attribute access). Reading
# `__builtins__` opens a backdoor to every banned call via subscript:
# `__builtins__["open"]("/x", "w")`. Same for `__import__` (the function-form
# of the banned import system), `__loader__`, `__spec__`, `__package__`,
# `__path__`, `__cached__`. The Names below are the safe ones — bare reads
# of any other dunder identifier are rejected.
SAFE_DUNDER_NAMES = frozenset(
    {
        "__name__",
        "__doc__",
        "__file__",
        "__version__",
        "__main__",
    }
)


# Specific attributes on `sys` that are escape vectors even though `sys`
# itself is in the allowlist. `sys.modules` is the worst — `os` is already
# loaded by the runtime, so `sys.modules["os"].system(...)` runs commands.
# `sys.path` writes affect later imports, `sys.meta_path` installs import
# hooks, and `sys._getframe()` walks the call stack to escape scope checks.
SYS_BANNED_ATTRS = frozenset(
    {
        "modules",
        "path",
        "path_hooks",
        "path_importer_cache",
        "meta_path",
        "settrace",
        "setprofile",
        "_getframe",
        "_current_frames",
        "addaudithook",
    }
)


# Modules whose `.open(path, mode)` should be mode-checked the same way as the
# bare `open()` builtin. Both `io.open` and `codecs.open` accept mode and
# can be used to write files.
MODE_CHECKED_MODULES = frozenset({"io", "codecs"})

# io.* constructors that can write to disk. `io.FileIO(path, "w")` is a direct
# bypass of the `open()` mode check — same mode argument, different name.
# Buffered wrappers take an already-open writable; ban them too.
IO_MODE_CHECKED = frozenset({"open", "FileIO"})
IO_BANNED_WRITE_WRAPPERS = frozenset(
    {
        "BufferedWriter",
        "BufferedRandom",
        "BufferedRWPair",
    }
)


# `from <module> import <attr>` is banned for these (module, attr) pairs.
# Importing them rebinds a dangerous attribute to a bare Name, bypassing
# attribute-access checks. Several allowed modules expose `os`, `sys`, or
# `builtins` as a transitive attribute — banning the from-import closes
# that side-channel. Users can always do `import sys; sys.X` /
# `import io; io.X` and still hit the proper validation.
BANNED_FROM_IMPORTS = {
    "sys": SYS_BANNED_ATTRS,
    "io": IO_MODE_CHECKED | IO_BANNED_WRITE_WRAPPERS,
    "codecs": frozenset({"open", "builtins", "sys"}),
    "reprlib": frozenset({"builtins"}),
    # `json` re-exports `codecs` as a module attribute, so `from json import
    # codecs` would rebind it.
    "json": frozenset({"codecs"}),
    # Path / utility modules expose `os` (and sometimes `sys`/`builtins`) as
    # module-level attributes — `from posixpath import os` then `os.system()`
    # would pass without these blocks.
    "os.path": frozenset({"os", "sys", "builtins"}),
    "posixpath": frozenset({"os", "sys", "builtins"}),
    "ntpath": frozenset({"os", "sys", "builtins"}),
    "genericpath": frozenset({"os", "sys", "builtins"}),
    "uuid": frozenset({"os", "sys"}),
    "calendar": frozenset({"sys"}),
    "fractions": frozenset({"sys"}),
    "statistics": frozenset({"sys"}),
    "typing": frozenset({"sys"}),
    "dataclasses": frozenset({"sys"}),
    # `enum` exposes `bltns` (an alias for the `builtins` module) on top of
    # the usual `sys`. Both rebind to a clean Name.
    "enum": frozenset({"sys", "bltns"}),
    "collections.abc": frozenset({"sys"}),
    # `queue` imports `threading` for its synchronization primitives.
    "queue": frozenset({"threading"}),
}


# `import X as Y` rebinds the module under an alias. Several attribute-based
# checks (`io.open` mode-check, `sys.modules` block, `codecs.open` mode-check)
# depend on the receiver's Name id matching the original module name —
# aliasing defeats them.
NO_ALIAS_MODULES = frozenset({"io", "sys", "codecs"})


# Attribute names that should never be read on any receiver. Reaching `.os`,
# `.sys`, `.builtins`, or `.codecs` on an allowed module pierces the
# import-system sandbox (`posixpath.os.system(...)`,
# `reprlib.builtins.open(...)`, `codecs.sys.modules[...]`).
BANNED_ATTR_NAMES = frozenset(
    {
        "os",
        "sys",
        "builtins",
        "subprocess",
        "socket",
        "shutil",
        "ctypes",
        "multiprocessing",
        "threading",
        "importlib",
        "pty",
        "codecs",  # codecs is itself allowed but reaching it transitively
        # (e.g. `json.codecs.open(...)`) is always an escape attempt
        "bltns",  # `enum.bltns` is an alias for `builtins`
        "urllib",  # `xml.sax.saxutils.urllib` exposes the urllib package
        "_thread",
        "_socket",
    }
)


# `operator.attrgetter("name")(obj)` and `operator.methodcaller("name")(obj)`
# are string-based attribute / method dispatchers — equivalent to `getattr`
# and indirect method calls. Treat them as banned the same way `getattr` is.
OPERATOR_BANNED_DISPATCHERS = frozenset({"attrgetter", "methodcaller"})


# Bare `Name(id=X)` Loads that are only legitimate as the immediate `func` of
# a Call. `_o = open; _o(p, "w")` defeats the call-site mode check by aliasing
# the builtin. Block any reference to `open` outside a direct call position.
BANNED_LOAD_NAMES_OUTSIDE_CALL = frozenset({"open"})


def fail(msg: str) -> None:
    print(msg)
    sys.exit(1)


def check_import_module(module: str) -> str | None:
    """Return error message if module is not allowed, else None."""
    if module in ALLOWED_MODULES:
        return None
    # Allow submodules of allowed parents (e.g. xml.etree.ElementTree.foo)
    parts = module.split(".")
    for i in range(len(parts), 0, -1):
        if ".".join(parts[:i]) in ALLOWED_MODULES:
            return None
    return f"import of '{module}' not in read-only allowlist"


def check_open_call(node: ast.Call) -> str | None:
    """Allow open() only with read mode."""
    mode = None
    if len(node.args) >= 2:
        mode_node = node.args[1]
        if isinstance(mode_node, ast.Constant) and isinstance(mode_node.value, str):
            mode = mode_node.value
        else:
            return "open() with non-literal mode"
    for kw in node.keywords:
        if kw.arg == "mode":
            if isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                mode = kw.value.value
            else:
                return "open() with non-literal mode"
    if mode is None:
        return None  # default 'r'
    # Read modes: 'r', 'rb', 'rt', 'br', 'tr'. Anything with w/a/x/+ is a write.
    if any(c in mode for c in "wax+"):
        return f"open() with write mode '{mode}'"
    return None


def main() -> None:
    source = sys.stdin.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        print(f"python parse error: {e.msg}")
        sys.exit(2)

    # Pre-pass: collect every Name node that appears as the immediate func of
    # a Call. Used to allow `open(...)` while rejecting `f = open` aliasing.
    call_func_name_ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            call_func_name_ids.add(id(node.func))

    for node in ast.walk(tree):
        # --- Imports ---
        if isinstance(node, ast.Import):
            for alias in node.names:
                err = check_import_module(alias.name)
                if err:
                    fail(err)
                # `import io as X` / `import sys as X` — alias defeats
                # name-based attribute checks downstream.
                if alias.asname and alias.name in NO_ALIAS_MODULES:
                    fail(
                        f"import {alias.name} as {alias.asname} rebinds the "
                        f"module past the static check"
                    )
                # `import os.path` binds the bare name `os` in the namespace,
                # which then permits `os.system(...)` directly. Disallow the
                # dotted import; users can use `from os.path import join, ...`.
                if "." in alias.name and alias.name in {"os.path"} and not alias.asname:
                    fail(
                        f"`import {alias.name}` binds the bare `os` namespace "
                        f"— use `from {alias.name} import <names>` instead"
                    )
        elif isinstance(node, ast.ImportFrom):
            mod = node.module or ""
            if node.level > 0:
                fail("relative import not allowed")
            err = check_import_module(mod)
            if err:
                fail(err)
            banned = BANNED_FROM_IMPORTS.get(mod)
            if banned:
                for alias in node.names:
                    if alias.name == "*":
                        fail(f"wildcard import from '{mod}' not allowed")
                    if alias.name in banned:
                        fail(
                            f"from {mod} import {alias.name} rebinds a dangerous "
                            f"attribute past the static check"
                        )

        # --- Function/method calls ---
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                if func.id == "open":
                    err = check_open_call(node)
                    if err:
                        fail(err)
                elif func.id in BANNED_CALLS:
                    fail(f"call to banned builtin '{func.id}'")
            elif isinstance(func, ast.Attribute):
                # io.open / codecs.open / io.FileIO take a mode arg — apply
                # the same mode check as the bare `open()` builtin.
                if isinstance(func.value, ast.Name):
                    mod_name = func.value.id
                    if (
                        mod_name in MODE_CHECKED_MODULES
                        and func.attr in IO_MODE_CHECKED
                    ):
                        err = check_open_call(node)
                        if err:
                            fail(err)
                    elif mod_name == "io" and func.attr in IO_BANNED_WRITE_WRAPPERS:
                        fail(f"call to write-capable io.{func.attr}")
                    elif (
                        mod_name == "operator"
                        and func.attr in OPERATOR_BANNED_DISPATCHERS
                    ):
                        fail(
                            f"operator.{func.attr} dispatches by string name — "
                            f"equivalent to getattr"
                        )

        # --- Bare Name reads ---
        elif isinstance(node, ast.Name):
            name = node.id
            # Dunder Name (Subscript-bypass for __builtins__, etc.)
            if (
                name.startswith("__")
                and name.endswith("__")
                and name not in SAFE_DUNDER_NAMES
            ):
                fail(f"reference to dunder name '{name}'")
            # `open` is allowed only as the direct func of a Call. Any other
            # Load — assignment RHS, function arg, dict value, etc. — is an
            # aliasing attempt.
            if (
                name in BANNED_LOAD_NAMES_OUTSIDE_CALL
                and id(node) not in call_func_name_ids
            ):
                fail(
                    f"reference to '{name}' outside a direct call — would "
                    f"defeat the mode-check (e.g. `f = open; f(p, 'w')`)"
                )

        # --- Attribute access ---
        elif isinstance(node, ast.Attribute):
            attr = node.attr
            # sys.modules / sys.path / sys.meta_path etc. — escape vectors
            # even though `sys` itself is allowed.
            if (
                isinstance(node.value, ast.Name)
                and node.value.id == "sys"
                and attr in SYS_BANNED_ATTRS
            ):
                fail(f"sys.{attr} is an import-system escape vector")
            # `.os`, `.sys`, `.builtins`, etc. on any receiver pierce the
            # sandbox — `posixpath.os.system(...)`, `reprlib.builtins.open(...)`.
            if attr in BANNED_ATTR_NAMES:
                fail(f"attribute access '.{attr}' reaches a sandboxed module")
            # Dunder attribute escape: `().__class__.__bases__[0].__subclasses__()`
            if (
                attr.startswith("__")
                and attr.endswith("__")
                and attr not in SAFE_DUNDERS
            ):
                fail(f"dunder attribute access '.{attr}'")

    sys.exit(0)


if __name__ == "__main__":
    main()
