"""Component A platform package.

WARNING / DESIGN NOTE
---------------------
This package is named ``platform`` to match the locked architecture contract
(``platform/ingestion``, ``platform/warehouse``, ...). That name collides with
the Python standard library module ``platform``. When the interpreter's working
directory or ``sys.path[0]`` contains this directory, a bare ``import platform``
would otherwise resolve to THIS package and shadow the stdlib module, breaking
every dependency that imports the real one (``attr`` -> ``dbt`` -> ``dagster``,
``uvicorn``, etc. all call ``platform.python_implementation()`` at import time).

To keep BOTH the contract import path (``import platform.warehouse.connection``)
AND the stdlib behaviour working, this ``__init__`` loads the genuine stdlib
``platform`` module from its file location and re-exports its public surface onto
this package. The submodules (``warehouse``, ``ingestion``, ...) live alongside
it as normal subpackages and are unaffected.

Do NOT define a top-level attribute here whose name clashes with a public stdlib
``platform`` symbol unless you intend to override it.
"""

from __future__ import annotations

import importlib.util as _importlib_util
import os as _os
import sysconfig as _sysconfig

# Locate and load the real standard-library ``platform`` module by file path so
# we never recurse into this package.
_stdlib_dir = _sysconfig.get_paths()["stdlib"]
_real_platform_path = _os.path.join(_stdlib_dir, "platform.py")
_spec = _importlib_util.spec_from_file_location("_stdlib_platform", _real_platform_path)
if _spec is None or _spec.loader is None:  # pragma: no cover - defensive
    raise ImportError(f"could not locate the standard-library platform module at {_real_platform_path}")
_stdlib_platform = _importlib_util.module_from_spec(_spec)
_spec.loader.exec_module(_stdlib_platform)

# Re-export every public stdlib symbol so ``import platform; platform.system()``
# (and the transitive ``platform.python_implementation()`` calls in attr/dbt)
# resolve correctly even when this package is on the path.
for _name in dir(_stdlib_platform):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_stdlib_platform, _name)

del _name
