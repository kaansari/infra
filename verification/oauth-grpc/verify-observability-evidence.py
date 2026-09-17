#!/usr/bin/env python3
"""Check sanitized local MCP and direct gRPC JSONL evidence before publishing."""

import argparse
import json
import re
import sys
from pathlib import Path

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
TRACE_ID = re.compile(r"^[0-9a-f]{32}$")
FORBIDDEN_KEYS = re.compile(r"authorization|cookie|password|secret|credential|api.?key|dsn|database_url|idempotency_key|request_body|response_body|raw_token|email|phone|address", re.I)
FORBIDDEN_VALUES = re.compile(r"Bearer\s+\S+|-----BEGIN\s+.*PRIVATE KEY-----|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", re.I)


def verify(rows):
    groups = {}
    for line_no, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            raise ValueError(f"line {line_no}: expected JSON object")
        for key, value in row.items():
            if key not in {"authorization_decision"} and FORBIDDEN_KEYS.search(key):
                raise ValueError(f"line {line_no}: forbidden field {key}")
            if FORBIDDEN_VALUES.search(str(value)):
                raise ValueError(f"line {line_no}: sensitive value in {key}")
        if row.get("msg") not in ("agent_gateway.tool_call", "grpc.request"):
            continue
        request_id, trace_id = row.get("request_id"), row.get("trace_id")
        if not isinstance(request_id, str) or not SAFE_ID.fullmatch(request_id):
            raise ValueError(f"line {line_no}: invalid request_id")
        if not isinstance(trace_id, str) or not TRACE_ID.fullmatch(trace_id) or trace_id == "0" * 32:
            raise ValueError(f"line {line_no}: invalid trace_id")
        groups.setdefault((request_id, trace_id), []).append(row)

    direct = [events for events in groups.values() if any(e.get("msg") == "grpc.request" and e.get("origin") == "direct" for e in events)]
    mcp = [events for events in groups.values() if any(e.get("msg") == "agent_gateway.tool_call" for e in events)]
    if not direct or not mcp:
        raise ValueError("missing direct gRPC or MCP evidence")
    for events in mcp:
        gateway = [e for e in events if e.get("msg") == "agent_gateway.tool_call"]
        downstream = [e for e in events if e.get("msg") == "grpc.request" and e.get("origin") == "mcp"]
        if any(e.get("outcome") in ("started", "completed") for e in gateway) and not downstream:
            raise ValueError("MCP execution has no matching authoritative gRPC decision")
        if any(e.get("authorization_decision") not in ("allowed", "denied", "failed", "not_evaluated") for e in downstream):
            raise ValueError("invalid gRPC authorization decision")
    return {"direct_traces": len(direct), "mcp_traces": len(mcp), "result": "PASS"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jsonl", type=Path, help="sanitized local gateway and service JSONL logs")
    args = parser.parse_args()
    try:
        rows = [json.loads(line) for line in args.jsonl.read_text().splitlines() if line.strip()]
        print(json.dumps(verify(rows), sort_keys=True))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"observability evidence failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
