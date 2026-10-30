"""Standalone preparation CLI; does not execute bots, select parameters, or write game files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from calibration_plan import make_plan
from report_preflight import audit, read_object


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plan_parser = commands.add_parser("plan")
    plan_parser.add_argument("--first-seed", required=True)
    plan_parser.add_argument("--smoke", type=int, default=3)
    plan_parser.add_argument("--explore", type=int, default=100)
    plan_parser.add_argument("--confirm", type=int, default=150)
    plan_parser.add_argument("--output", type=Path, required=True)
    audit_parser = commands.add_parser("audit")
    audit_parser.add_argument("plan", type=Path)
    audit_parser.add_argument("reports", type=Path, nargs="+")
    audit_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            result = make_plan(args.first_seed, args.smoke, args.explore, args.confirm)
        else:
            registration, plan_hash, _plan_bytes = read_object(args.plan)
            result = audit(registration, args.reports)
            result["plan_sha256"] = plan_hash
        encoded = json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2) + "\n"
        with args.output.open("x", encoding="utf-8", newline="\n") as output:
            output.write(encoded)
        print(str(args.output))
        return 1 if result.get("summary_preflight_valid") is False else 0
    except (OSError, ValueError, RecursionError) as error:
        parser.exit(2, f"calibration preparation failed: {error}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
