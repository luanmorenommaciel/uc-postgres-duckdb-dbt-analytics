"""Single source of truth for the DuckDB warehouse file location (C4).

ENV VAR (canonical, everywhere): ``DUCKDB_DATABASE``.
  - ``DUCKDB_PATH`` and ``WAREHOUSE_DB_PATH`` are REJECTED legacy names; if either
    is set without ``DUCKDB_DATABASE`` we raise so misconfiguration fails loud.
DEFAULT VALUE: ``<repo>/platform/warehouse/warehouse.duckdb`` (gitignored).

This module is the ONLY place the default path literal exists. No other file in
the repo may hardcode a warehouse path.

The MotherDuck escape hatch (``DUCKDB_DATABASE=md:<db>``) is honoured verbatim:
when the value starts with ``md:`` it is returned as-is and never resolved to a
filesystem path.
"""

from __future__ import annotations

import os
from pathlib import Path

ENV_VAR = "DUCKDB_DATABASE"
_REJECTED_ENV_VARS = ("DUCKDB_PATH", "WAREHOUSE_DB_PATH")

# This file lives at <repo>/platform/warehouse/paths.py, so the repo root is two
# parents up. The default DB file sits next to this module.
_THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = _THIS_DIR.parent.parent
DEFAULT_WAREHOUSE_FILE = _THIS_DIR / "warehouse.duckdb"


def _check_rejected_env_vars() -> None:
    """Fail loud if a legacy/rejected env var is set without the canonical one."""
    if os.environ.get(ENV_VAR):
        return
    for legacy in _REJECTED_ENV_VARS:
        if os.environ.get(legacy):
            raise RuntimeError(
                f"Env var {legacy!r} is not supported. The warehouse location is "
                f"configured exclusively via {ENV_VAR!r}. Set {ENV_VAR} instead."
            )


def is_motherduck(value: str) -> bool:
    """Return True for a MotherDuck DSN (``md:`` / ``motherduck:`` prefix)."""
    lowered = value.strip().lower()
    return lowered.startswith("md:") or lowered.startswith("motherduck:")


def warehouse_path_str() -> str:
    """Return the warehouse target as a string for DuckDB / dbt.

    - If ``DUCKDB_DATABASE`` is a MotherDuck DSN, return it unchanged.
    - If set to a filesystem path, return its absolute form.
    - Otherwise return the absolute default file path.
    """
    _check_rejected_env_vars()
    raw = os.environ.get(ENV_VAR)
    if raw:
        raw = raw.strip()
        if is_motherduck(raw):
            return raw
        return str(Path(raw).expanduser().resolve())
    return str(DEFAULT_WAREHOUSE_FILE.resolve())


def warehouse_path() -> Path:
    """Return the warehouse file as a ``Path`` (filesystem targets only).

    Raises ``ValueError`` for MotherDuck DSNs, which have no filesystem path.
    Callers that must support MotherDuck should use :func:`warehouse_path_str`.
    """
    target = warehouse_path_str()
    if is_motherduck(target):
        raise ValueError(
            f"{ENV_VAR}={target!r} is a MotherDuck DSN and has no filesystem path; "
            "use warehouse_path_str() instead."
        )
    return Path(target)


def ensure_parent_dir() -> Path | None:
    """Create the parent directory of the warehouse file if needed.

    Returns the created/existing directory, or ``None`` for MotherDuck targets.
    Used by writers (C2 ingest, C3 dbt) before opening a read/write connection.
    """
    target = warehouse_path_str()
    if is_motherduck(target):
        return None
    parent = Path(target).parent
    parent.mkdir(parents=True, exist_ok=True)
    return parent
