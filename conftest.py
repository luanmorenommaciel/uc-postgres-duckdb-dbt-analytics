"""Pytest bootstrap: make the repo's ``platform`` package win sys.modules.

The Component A code lives under a top-level package literally named ``platform``
(``platform/ingestion``, ``platform/warehouse``, ...), matching the locked
architecture contract. That name collides with Python's standard-library
``platform`` module.

Under ``uv run python -m platform.ingestion.run`` our package is imported first
and resolves correctly (its ``__init__`` re-exports the genuine stdlib symbols —
see ``platform/__init__.py``). But pytest imports the stdlib ``platform`` during
its own startup, so by the time test modules run ``sys.modules['platform']`` holds
the plain stdlib module, which has no ``ingestion``/``warehouse`` submodules
=> ``ModuleNotFoundError: 'platform' is not a package``.

This conftest runs before any test module is imported. It evicts the stdlib entry
and imports the repo's ``platform`` package fresh, so:
  - ``import platform.ingestion.run`` / ``platform.warehouse.connection`` resolve;
  - ``platform.system()`` etc. still work (the package re-exports stdlib symbols).

conftest.py at the repo root is the earliest, most surgical place to do this; no
production module is affected.
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent

# Ensure the repo root is importable (mirrors pyproject's pytest pythonpath=["."]).
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


def _force_repo_platform_package() -> None:
    existing = sys.modules.get("platform")
    # If the stdlib (non-package) module currently owns the name, drop it so the
    # next import resolves to the repo package on sys.path.
    if existing is not None and not hasattr(existing, "__path__"):
        del sys.modules["platform"]
    pkg = importlib.import_module("platform")
    # Sanity: the repo package exposes __path__ AND re-exports stdlib surface.
    assert hasattr(pkg, "__path__"), "repo 'platform' package failed to load"
    assert hasattr(pkg, "system"), "platform package did not re-export stdlib symbols"


_force_repo_platform_package()
