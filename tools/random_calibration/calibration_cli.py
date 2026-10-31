"""Standalone preparation CLI; does not execute bots, select parameters, or write game files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from calibration_plan import make_plan
from report_preflight import audit, read_object
from cohort_inventory import compare, inventory
from cohort_evidence import verify


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
    index_parser = commands.add_parser("index")
    index_parser.add_argument("plan", type=Path)
    index_parser.add_argument("runs", type=Path)
    index_parser.add_argument("--phase", choices=["smoke", "explore", "confirm"], required=True)
    index_parser.add_argument("--variant", required=True)
    index_parser.add_argument("--output", type=Path, required=True)
    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("plan", type=Path)
    compare_parser.add_argument("inventories", type=Path, nargs="+")
    compare_parser.add_argument("--output", type=Path, required=True)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("plan", type=Path)
    verify_parser.add_argument("inventory", type=Path)
    verify_parser.add_argument("summaries", type=Path, nargs="+")
    verify_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            result = make_plan(args.first_seed, args.smoke, args.explore, args.confirm)
        else:
            registration, plan_hash, _plan_bytes = read_object(args.plan)
            if args.command == "audit":
                result = audit(registration, args.reports)
            elif args.command == "index":
                result = inventory(registration, plan_hash, args.runs, args.phase, args.variant)
            elif args.command == "compare":
                result = compare(registration, plan_hash, args.inventories)
            else:
                result = verify(registration, plan_hash, args.inventory, args.summaries)
            result["plan_sha256"] = plan_hash
        encoded = json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2) + "\n"
        if args.command in ("index", "compare", "verify") and len(encoded.encode("utf-8")) > 8 * 1024 * 1024:
            raise ValueError("cohort output exceeds 8 MiB")
        with args.output.open("x", encoding="utf-8", newline="\n") as output:
            output.write(encoded)
        print(str(args.output))
        gates = ("summary_preflight_valid", "seed_inventory_complete", "seed_pairing_complete", "identity_link_complete")
        return 1 if any(result.get(key) is False for key in gates) else 0
    except (OSError, ValueError, RecursionError) as error:
        parser.exit(2, f"calibration preparation failed: {error}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
