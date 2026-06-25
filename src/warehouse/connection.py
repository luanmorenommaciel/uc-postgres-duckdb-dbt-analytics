"""DuckDB connection helpers for the single shared warehouse file.

This is the ONE place a DuckDB connection is opened. Every component routes
through here so the path resolution (``DUCKDB_DATABASE``), MotherDuck escape
hatch, and read-only enforcement live in a single spot.

CONCURRENCY CONTRACT:
  - DuckDB is single-writer-process. Writers call :func:`connect` (read/write)
    BRIEFLY and NEVER concurrently — they are serialized so that only one write
    connection is open at a time.
  - Readers call :func:`connect_read_only` (``access_mode=READ_ONLY``) and may
    run concurrently with each other and with a single writer.
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import TYPE_CHECKING, Any

import duckdb

from src.warehouse.paths import ensure_parent_dir, warehouse_path_str

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
            MUST pass ``read_only=True``. Writers leave it ``False`` and are
            responsible for not running concurrently.
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
    """Open a read-only connection to the shared warehouse.

    Convenience wrapper for readers; always opens with ``access_mode=READ_ONLY``.

    Args:
        config: Extra DuckDB config dict, merged on top of the access-mode key.

    Returns:
        An open read-only :class:`duckdb.DuckDBPyConnection`.
    """
    return connect(read_only=True, config=config)


@contextmanager
def connection(
    *,
    read_only: bool = False,
    config: dict[str, Any] | None = None,
) -> Iterator[duckdb.DuckDBPyConnection]:
    """Yield a warehouse connection that is always closed on exit.

    Args:
        read_only: When ``True`` open with ``access_mode=READ_ONLY``; see
            :func:`connect` for the writer/reader contract.
        config: Extra DuckDB config dict, merged on top of the access-mode key.

    Yields:
        An open :class:`duckdb.DuckDBPyConnection` that is closed when the
        ``with`` block exits, even on error.
    """
    conn = connect(read_only=read_only, config=config)
    try:
        yield conn
    finally:
        conn.close()
