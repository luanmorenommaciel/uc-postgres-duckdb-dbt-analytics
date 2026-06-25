"""DuckDB connection helpers for the single shared warehouse file (C4).

This is the ONE place a DuckDB connection is opened. Every component routes
through here so the path resolution (``DUCKDB_DATABASE``), MotherDuck escape
hatch, and read-only enforcement live in a single spot.

CONCURRENCY CONTRACT (from the interface contract):
  - DuckDB is single-writer-process. Writers (C2 ingest, C3 dbt) call
    :func:`connect` (read/write) BRIEFLY and NEVER concurrently — serialized by
    the orchestration invariant (ingest-run THEN dbt-run).
  - Readers (C5 MCP, C4h harness, C8 probe) call :func:`connect_read_only`
    (``access_mode=READ_ONLY``) and may run concurrently with each other and
    with a single writer.
"""

from __future__ import annotations

from contextlib import contextmanager
from platform.warehouse.paths import ensure_parent_dir, warehouse_path_str
from typing import TYPE_CHECKING, Any

import duckdb

if TYPE_CHECKING:
    from collections.abc import Iterator


def connect(
    *,
    read_only: bool = False,
    config: dict[str, Any] | None = None,
) -> duckdb.DuckDBPyConnection:
    """Open a connection to the shared warehouse.

    Args:
        read_only: When ``True`` open with ``access_mode=READ_ONLY``. Readers
            (C5/C4h/C8) MUST pass ``read_only=True``. Writers (C2/C3) leave it
            ``False`` and are responsible for not running concurrently.
        config: Extra DuckDB config dict, merged on top of the access-mode key.

    Returns:
        An open :class:`duckdb.DuckDBPyConnection`. The caller owns its lifetime
        (use :func:`connection` for a context-managed handle).
    """
    target = warehouse_path_str()
    merged: dict[str, Any] = dict(config or {})
    if read_only:
        # Set both the kwarg and the config key; DuckDB honours either, and being
        # explicit keeps the intent legible to readers of EXPLAIN/log output.
        merged.setdefault("access_mode", "READ_ONLY")
    else:
        # Only writers create the file; never auto-create the parent for a
        # read-only open (a missing file should surface as an error, not a
        # silently-created empty DB).
        ensure_parent_dir()
    return duckdb.connect(target, read_only=read_only, config=merged)


def connect_read_only(config: dict[str, Any] | None = None) -> duckdb.DuckDBPyConnection:
    """Convenience wrapper for readers (C5 MCP / C4h / C8). Always read-only."""
    return connect(read_only=True, config=config)


@contextmanager
def connection(
    *,
    read_only: bool = False,
    config: dict[str, Any] | None = None,
) -> Iterator[duckdb.DuckDBPyConnection]:
    """Context-managed warehouse connection that always closes the handle."""
    conn = connect(read_only=read_only, config=config)
    try:
        yield conn
    finally:
        conn.close()
