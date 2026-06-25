"""``src.transition`` — the Postgres -> DuckDB data-movement step.

This package is the *full-refresh landing* of the four source entities into
``raw.raw_*``. It ``ATTACH``-es Postgres READ-ONLY through DuckDB's ``postgres``
extension and copies each source entity into ``raw.raw_*`` with
``CREATE OR REPLACE TABLE ... AS SELECT``, preserving the three trailing lineage
columns (``_ingested_at``, ``_source_watermark``, ``_schema_drift``).

Public surface:
  - :func:`src.transition.ingest.land_all`    — full-refresh every entity.
  - :func:`src.transition.ingest.land_entity` — land one entity.
  - ``python -m src.transition.cli land``      — the CLI entrypoint.
"""

from __future__ import annotations

from src.transition.ingest import (
    EntitySpec,
    LandResult,
    land_all,
    land_entity,
)

__all__ = [
    "EntitySpec",
    "LandResult",
    "land_all",
    "land_entity",
]
