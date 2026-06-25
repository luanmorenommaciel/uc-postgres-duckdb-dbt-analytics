"""Single source of truth for the DuckDB warehouse file location.

ENV VAR (canonical, everywhere): ``DUCKDB_DATABASE``.
  - ``DUCKDB_PATH`` and ``WAREHOUSE_DB_PATH`` are REJECTED legacy names; if either
    is set without ``DUCKDB_DATABASE`` we raise so misconfiguration fails loud.
DEFAULT VALUE: ``<repo>/src/warehouse/warehouse.duckdb`` (gitignored).

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

# This file lives at <repo>/src/warehouse/paths.py, so the repo root is two
# parents up (warehouse -> src -> repo root); parent.parent stays correct after
# the move. The default DB file sits next to this module.
_THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = _THIS_DIR.parent.parent
DEFAULT_WAREHOUSE_FILE = _THIS_DIR / "warehouse.duckdb"


def _check_rejected_env_vars() -> None:
    """Fail loud if a legacy/rejected env var is set without the canonical one.

    Raises:
        RuntimeError: If ``DUCKDB_PATH`` or ``WAREHOUSE_DB_PATH`` is set while the
            canonical ``DUCKDB_DATABASE`` is unset, so a stale configuration
            surfaces as an error instead of being silently ignored.
    """
    if os.environ.get(ENV_VAR):
        return
    for legacy in _REJECTED_ENV_VARS:
        if os.environ.get(legacy):
            raise RuntimeError(
                f"Env var {legacy!r} is not supported. The warehouse location is "
                f"configured exclusively via {ENV_VAR!r}. Set {ENV_VAR} instead."
            )


def is_motherduck(value: str) -> bool:
    """Return True for a MotherDuck DSN (``md:`` / ``motherduck:`` prefix).

    Args:
        value: The raw ``DUCKDB_DATABASE`` value to classify.

    Returns:
        ``True`` if ``value`` names a MotherDuck database rather than a local
        filesystem path, ``False`` otherwise. The check is case-insensitive and
        ignores surrounding whitespace.
    """
    lowered = value.strip().lower()
    return lowered.startswith("md:") or lowered.startswith("motherduck:")


def warehouse_path_str() -> str:
    """Return the warehouse target as a string for DuckDB / dbt.

    - If ``DUCKDB_DATABASE`` is a MotherDuck DSN, return it unchanged.
    - If set to a filesystem path, return its absolute form.
    - Otherwise return the absolute default file path.

    Returns:
        The resolved warehouse target: a MotherDuck DSN verbatim, or an absolute
        filesystem path string.
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

    Returns:
        The resolved warehouse file as a :class:`pathlib.Path`.

    Raises:
        ValueError: If the configured target is a MotherDuck DSN, which has no
            filesystem path. Callers that must support MotherDuck should use
            :func:`warehouse_path_str` instead.
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

    Used by writers before opening a read/write connection so the target
    directory exists.

    Returns:
        The created/existing parent directory as a :class:`pathlib.Path`, or
        ``None`` for MotherDuck targets (which have no local parent directory).
    """
    target = warehouse_path_str()
    if is_motherduck(target):
        return None
    parent = Path(target).parent
    parent.mkdir(parents=True, exist_ok=True)
    return parent
