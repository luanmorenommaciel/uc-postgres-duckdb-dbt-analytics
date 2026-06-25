"""Warehouse substrate: the single DuckDB file path + connection helpers.

This package is the sole owner of the warehouse file. It exposes:
  - ``src.warehouse.paths``      -> ``warehouse_path()`` / ``warehouse_path_str()``
  - ``src.warehouse.connection`` -> ``connect()`` / ``connect_read_only()``

Every other part of the pipeline consumes these helpers; none of them hardcode
the path or reimplement the connection.
"""

from __future__ import annotations

from src.warehouse.connection import connect, connect_read_only
from src.warehouse.paths import warehouse_path, warehouse_path_str

__all__ = [
    "connect",
    "connect_read_only",
    "warehouse_path",
    "warehouse_path_str",
]
