"""C4 warehouse substrate: the single DuckDB file path + connection helpers.

SOLE OWNER of the warehouse file. Exposes:
  - ``platform.warehouse.paths``      -> ``warehouse_path()`` / ``warehouse_path_str()``
  - ``platform.warehouse.connection`` -> ``connect()`` / ``connect_read_only()``

Every other component (C2 ingest, C3 dbt, C5 MCP, C4h harness, C8 probe) consumes
these helpers; none of them hardcode the path or reimplement the connection.
"""

from __future__ import annotations

from platform.warehouse.connection import connect, connect_read_only
from platform.warehouse.paths import warehouse_path, warehouse_path_str

__all__ = [
    "connect",
    "connect_read_only",
    "warehouse_path",
    "warehouse_path_str",
]
