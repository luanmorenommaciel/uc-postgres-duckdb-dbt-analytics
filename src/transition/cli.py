"""CLI for ``src.transition`` (the Postgres -> DuckDB data-movement step):
``python -m src.transition.cli land``.

Mirrors the argparse shape of :mod:`src.gen.cli` (subparsers,
``set_defaults(func=...)``, ``main(argv) -> int``) so the repo stays consistent
and there is room for a future ``land --entity orders``. Run after ``make up`` +
``make seed``:

    uv run python -m src.transition.cli land
"""

from __future__ import annotations

import argparse
import sys

from src.transition import ingest


def _land(_: argparse.Namespace) -> int:
    """Run a full-refresh land of every ``raw.raw_*`` table and print a summary.

    Args:
        _: The parsed argparse namespace (unused; the ``land`` subcommand takes no
            options).

    Returns:
        Process exit code (``0`` on success).
    """
    results = ingest.land_all()
    for entity, result in results.items():
        drift = " schema_drift=TRUE" if result.schema_drift else ""
        print(
            f"landed {ingest.RAW_SCHEMA}.raw_{entity}: "
            f"{result.row_count:,} rows  watermark={result.source_watermark}{drift}"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the argparse parser with the ``land`` subcommand.

    Returns:
        The configured :class:`argparse.ArgumentParser`.
    """
    parser = argparse.ArgumentParser(
        prog="land",
        description="Land Postgres -> DuckDB raw.* (full refresh).",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("land", help="full-refresh all raw.raw_* tables").set_defaults(func=_land)
    return parser


def main(argv: list[str] | None = None) -> int:
    """Parse ``argv`` and dispatch to the selected subcommand.

    Args:
        argv: Optional argument vector; defaults to ``sys.argv[1:]`` when None.

    Returns:
        The subcommand's process exit code.
    """
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
