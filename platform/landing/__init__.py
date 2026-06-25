"""C2 landing module — Postgres -> DuckDB ``raw.raw_*`` via the postgres extension.

Replaces the Dagster ``platform.ingestion`` asset graph with a small plain-Python
*full-refresh landing* step. It ``ATTACH``-es Postgres READ-ONLY through DuckDB's
``postgres`` extension and copies the four source entities into ``raw.raw_*`` with
``CREATE OR REPLACE TABLE ... AS SELECT``, preserving the C2 contract columns
(``_ingested_at``, ``_source_watermark``, ``_schema_drift``).

Public surface:
  - :func:`platform.landing.ingest.land_all`    — full-refresh every entity.
  - :func:`platform.landing.ingest.land_entity` — land one entity.
  - ``python -m platform.landing.cli land``     — the CLI the meetup runs.

This is a proper subpackage marker so absolute imports
(``from platform.warehouse.connection import connect``) keep working despite the
``platform`` stdlib shadow handled in :mod:`platform`.
"""

from __future__ import annotations

from platform.landing.ingest import (
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
