"""CLI for the C2 landing module: ``python -m platform.landing.cli land``.

Mirrors the argparse shape of :mod:`src.gen.cli` (subparsers,
``set_defaults(func=...)``, ``main(argv) -> int``) so the repo stays consistent
and there is room for a future ``land --entity orders``. Run after ``make up`` +
``make seed``:

    uv run python -m platform.landing.cli land
"""

from __future__ import annotations

import argparse
import sys
from platform.landing import ingest


def _land(_: argparse.Namespace) -> int:
    results = ingest.land_all()
    for entity, result in results.items():
        drift = " schema_drift=TRUE" if result.schema_drift else ""
        print(
            f"landed {ingest.RAW_SCHEMA}.raw_{entity}: "
            f"{result.row_count:,} rows  watermark={result.source_watermark}{drift}"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="land",
        description="Land Postgres -> DuckDB raw.* (full refresh).",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("land", help="full-refresh all raw.raw_* tables").set_defaults(func=_land)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
