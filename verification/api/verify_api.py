#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from typing import Any


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
INFRA_DIR = SCRIPT_DIR.parents[1]
WORKSPACE = INFRA_DIR.parent
SCENARIOS_PATH = SCRIPT_DIR / "scenarios.json"
GRPC_ADDR = os.getenv("CEERAT_API_BASE_URL", "localhost:50051")
for scheme in ("http://", "https://"):
    if GRPC_ADDR.startswith(scheme):
        GRPC_ADDR = GRPC_ADDR[len(scheme):]
AGENT_URL = os.getenv("CEERAT_AGENT_BASE_URL", "http://localhost:8088").rstrip("/")
TOKEN_ENV = {
    "agent": "CEERAT_AGENT_TOKEN",
    "customer": "CEERAT_CUSTOMER_TOKEN",
    "admin": "CEERAT_ADMIN_TOKEN",
}
RUNTIME_TOKENS: dict[str, str] = {}
CONTRACTS_DIR = WORKSPACE / "contracts-repo" / "packages" / "ceerat-contracts"
PROTO_BY_PACKAGE = {
    name: f"proto/{name}/{name}.proto"
    for name in ("admin", "ai", "auth", "calendar", "career", "customer", "order", "service")
}


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def token_for(scenario: dict[str, Any]) -> str:
    literal = scenario.get("literal_token")
    if literal:
        return str(literal)
    profile = scenario.get("profile")
    if not profile:
        return ""
    primary = os.getenv(TOKEN_ENV[profile], "") or RUNTIME_TOKENS.get(profile, "")
    if primary:
        return primary
    if profile == "agent":
        return os.getenv("CEERAT_TOKEN", "")
    return ""


def local_settings() -> dict[str, str]:
    settings: dict[str, str] = {}
    env_path = INFRA_DIR / ".env"
    if env_path.exists():
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            try:
                settings[key.strip()] = shlex.split(value.strip())[0] if value.strip() else ""
            except (ValueError, IndexError):
                continue
    settings.update({key: value for key, value in os.environ.items() if value})
    return settings


def grpc_command(rpc: str, data: dict[str, Any], token: str = "") -> subprocess.CompletedProcess[str]:
    package = rpc.split(".", 1)[0]
    proto = PROTO_BY_PACKAGE.get(package)
    if not proto:
        raise ValueError(f"No protobuf descriptor configured for package {package}")
    command = ["grpcurl", "-plaintext", "-import-path", str(CONTRACTS_DIR), "-proto", proto]
    if token:
        command += ["-H", f"Authorization: Bearer {token}"]
    command += ["-d", json.dumps(data, separators=(",", ":")), GRPC_ADDR, rpc]
    return subprocess.run(command, text=True, capture_output=True, timeout=20, check=False)


def grpc_json(rpc: str, data: dict[str, Any], token: str = "") -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
    completed = grpc_command(rpc, data, token)
    try:
        parsed = json.loads(completed.stdout) if completed.stdout else {}
    except json.JSONDecodeError:
        parsed = {}
    return completed, parsed if isinstance(parsed, dict) else {}


def acquire_local_identities() -> dict[str, Any]:
    settings = local_settings()
    result: dict[str, Any] = {"status": "PASS", "profiles": {}}
    credentials = {
        "admin": (
            settings.get("VERIFY_API_ADMIN_EMAIL", settings.get("INITIAL_ADMIN_EMAIL", "admin@ceerat.local")),
            settings.get("VERIFY_API_ADMIN_PASSWORD", settings.get("INITIAL_ADMIN_PASSWORD", "admin123")),
        ),
        "agent": (
            settings.get("VERIFY_API_AGENT_EMAIL", "phase2.agent@ceerat.local"),
            settings.get("VERIFY_API_AGENT_PASSWORD", "phase2-agent-local-only"),
        ),
        "customer": (
            settings.get("VERIFY_API_CUSTOMER_EMAIL", "phase2.customer@ceerat.local"),
            settings.get("VERIFY_API_CUSTOMER_PASSWORD", "phase2-customer-local-only"),
        ),
    }

    def login(profile: str) -> bool:
        email, password = credentials[profile]
        completed, payload = grpc_json("auth.Auth/Auth", {"email": email, "password": password})
        token = payload.get("token", "")
        if completed.returncode == 0 and isinstance(token, str) and token:
            RUNTIME_TOKENS[profile] = token
            return True
        return False

    if os.getenv("CEERAT_ADMIN_TOKEN"):
        RUNTIME_TOKENS["admin"] = os.environ["CEERAT_ADMIN_TOKEN"]
    elif not login("admin"):
        result["profiles"]["admin"] = "unavailable"
    else:
        result["profiles"]["admin"] = "acquired"

    if os.getenv("CEERAT_CUSTOMER_TOKEN"):
        RUNTIME_TOKENS["customer"] = os.environ["CEERAT_CUSTOMER_TOKEN"]
    elif not login("customer"):
        email, password = credentials["customer"]
        completed, payload = grpc_json("auth.Auth/RegisterCustomer", {
            "firstName": "Phase Two", "lastName": "Customer", "company": "Ceerat Verification",
            "email": email, "password": password,
        })
        token = payload.get("token", {}).get("token", "") if isinstance(payload.get("token"), dict) else ""
        if completed.returncode == 0 and token:
            RUNTIME_TOKENS["customer"] = token
    result["profiles"]["customer"] = "acquired" if RUNTIME_TOKENS.get("customer") else "unavailable"

    if os.getenv("CEERAT_AGENT_TOKEN") or os.getenv("CEERAT_TOKEN"):
        RUNTIME_TOKENS["agent"] = os.getenv("CEERAT_AGENT_TOKEN", os.getenv("CEERAT_TOKEN", ""))
    elif not login("agent") and RUNTIME_TOKENS.get("admin"):
        email, password = credentials["agent"]
        grpc_json("admin.AdminService/CreateUser", {
            "name": "Phase Two Agent", "company": "Ceerat Verification", "email": email,
            "password": password, "role": "agent", "status": "active",
        }, RUNTIME_TOKENS["admin"])
        login("agent")
    result["profiles"]["agent"] = "acquired" if RUNTIME_TOKENS.get("agent") else "unavailable"
    if not RUNTIME_TOKENS:
        result["status"] = "SKIP"
    return result


def redact(value: str) -> str:
    redacted = value
    for env_name in (*TOKEN_ENV.values(), "CEERAT_TOKEN"):
        secret = os.getenv(env_name, "")
        if secret:
            redacted = redacted.replace(secret, "[REDACTED]")
    for secret in RUNTIME_TOKENS.values():
        if secret:
            redacted = redacted.replace(secret, "[REDACTED]")
    return redacted.replace("invalid-phase2-token", "[INVALID_TOKEN]")


def response_metadata(raw: bytes) -> dict[str, Any]:
    result: dict[str, Any] = {
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }
    try:
        parsed = json.loads(raw.decode("utf-8")) if raw else None
        if isinstance(parsed, dict):
            result["json_keys"] = sorted(parsed.keys())
            errors = parsed.get("errors")
            result["domain_error_count"] = len(errors) if isinstance(errors, list) else 0
        elif isinstance(parsed, list):
            result["json_type"] = "array"
            result["item_count"] = len(parsed)
    except (UnicodeDecodeError, json.JSONDecodeError):
        result["json_type"] = "invalid-or-non-json"
    return result


def run_http(scenario: dict[str, Any]) -> dict[str, Any]:
    token = token_for(scenario)
    if scenario.get("profile") and not token:
        return {"id": scenario["id"], "status": "SKIP", "reason": f"{TOKEN_ENV[scenario['profile']]} is not set"}
    headers = ["Accept: application/json"]
    if token:
        headers.append(f"Authorization: Bearer {token}")
    body = json.dumps(scenario.get("data", {}), separators=(",", ":")) if "data" in scenario else None
    if body is not None:
        headers.append("Content-Type: application/json")
    command = ["curl", "-sS", "--max-time", "10", "-X", scenario.get("method", "GET")]
    for header in headers:
        command += ["-H", header]
    if body is not None:
        command += ["--data", body]
    command += ["-w", "\n%{http_code}", AGENT_URL + scenario["path"]]
    try:
        completed = subprocess.run(command, capture_output=True, timeout=15, check=False)
    except Exception as exc:
        return {"id": scenario["id"], "status": "ERROR", "reason": redact(str(exc))}
    if completed.returncode != 0:
        return {"id": scenario["id"], "status": "ERROR", "reason": redact(completed.stderr.decode(errors="replace")[-1000:])}
    raw, separator, status_bytes = completed.stdout.rpartition(b"\n")
    if not separator or not status_bytes.isdigit():
        return {"id": scenario["id"], "status": "ERROR", "reason": "curl did not return an HTTP status"}
    status = int(status_bytes)
    expected = scenario["expected_status"]
    return {
        "id": scenario["id"],
        "status": "PASS" if status == expected else "FAIL",
        "expected_http_status": expected,
        "actual_http_status": status,
        "response": response_metadata(raw),
    }


def run_grpc(scenario: dict[str, Any]) -> dict[str, Any]:
    token = token_for(scenario)
    if scenario.get("profile") and not token:
        return {"id": scenario["id"], "status": "SKIP", "reason": f"{TOKEN_ENV[scenario['profile']]} is not set"}
    try:
        completed = grpc_command(scenario["rpc"], scenario.get("data", {}), token)
    except (ValueError, subprocess.SubprocessError) as exc:
        return {"id": scenario["id"], "status": "ERROR", "reason": redact(str(exc))}
    stdout = completed.stdout.encode()
    stderr = redact(completed.stderr)
    expected = scenario.get("expected", "ok")
    if expected == "ok":
        passed = completed.returncode == 0
        metadata = response_metadata(stdout)
        if metadata.get("domain_error_count", 0):
            passed = False
    else:
        expected_code = scenario.get("expected_code", "")
        passed = completed.returncode != 0 and expected_code in stderr
        metadata = response_metadata(stdout)
    result = {
        "id": scenario["id"],
        "status": "PASS" if passed else "FAIL",
        "rpc": scenario["rpc"],
        "expected": expected,
        "exit_code": completed.returncode,
        "response": metadata,
    }
    if scenario.get("expected_code"):
        result["expected_grpc_code"] = scenario["expected_code"]
    if not passed:
        result["diagnostic"] = stderr[-1000:]
    return result


def run_customer_profile_lifecycle(run_id: str) -> dict[str, Any]:
    token = RUNTIME_TOKENS.get("customer", "") or os.getenv("CEERAT_CUSTOMER_TOKEN", "")
    if not token:
        return {"id": "customer-profile-update-lifecycle", "status": "SKIP", "reason": "customer identity is unavailable"}
    rpc_get = "customer.CustomerService/GetMyCustomerProfile"
    rpc_update = "customer.CustomerService/UpdateMyCustomerProfile"
    before_call, before = grpc_json(rpc_get, {}, token)
    customer = before.get("customer", {})
    if before_call.returncode != 0 or not isinstance(customer, dict) or not customer.get("id"):
        return {"id": "customer-profile-update-lifecycle", "status": "FAIL", "stage": "read-before", "diagnostic": redact(before_call.stderr[-1000:])}
    address = customer.get("address", {}) if isinstance(customer.get("address"), dict) else {}
    shipping = customer.get("shippingAddress", {}) if isinstance(customer.get("shippingAddress"), dict) else {}
    billing = customer.get("billingAddress", {}) if isinstance(customer.get("billingAddress"), dict) else {}
    fixture_address = {"line1": "1 Verification Way", "city": "Chicago", "state": "IL", "country": "US", "postalCode": "60601"}
    if not all(shipping.get(key) for key in ("line1", "city", "state", "country", "postalCode")) or not all(billing.get(key) for key in ("line1", "city", "state", "country", "postalCode")):
        initialized = {
            "firstName": customer.get("firstName", "Phase Two"), "lastName": customer.get("lastName", "Customer"),
            "email": customer.get("email", ""), "phone": customer.get("phone", ""),
            "address": address, "shippingAddress": fixture_address, "billingAddress": fixture_address,
        }
        init_call, _ = grpc_json(rpc_update, initialized, token)
        before_call, before = grpc_json(rpc_get, {}, token)
        customer = before.get("customer", {})
        if init_call.returncode != 0 or before_call.returncode != 0 or not isinstance(customer, dict):
            return {"id": "customer-profile-update-lifecycle", "status": "FAIL", "stage": "initialize-fixture", "diagnostic": redact(init_call.stderr[-1000:])}
        address = customer.get("address", {}) if isinstance(customer.get("address"), dict) else {}
        shipping = customer.get("shippingAddress", {}) if isinstance(customer.get("shippingAddress"), dict) else {}
        billing = customer.get("billingAddress", {}) if isinstance(customer.get("billingAddress"), dict) else {}
    original = {
        "firstName": customer.get("firstName", ""), "lastName": customer.get("lastName", ""),
        "email": customer.get("email", ""), "phone": customer.get("phone", ""),
        "address": address, "shippingAddress": shipping, "billingAddress": billing,
    }
    marker = f"phase2-{run_id[-10:]}"
    changed = dict(original)
    changed["phone"] = marker
    update_call, _ = grpc_json(rpc_update, changed, token)
    read_call, after = grpc_json(rpc_get, {}, token)
    observed = after.get("customer", {}).get("phone", "") if isinstance(after.get("customer"), dict) else ""
    restore_call, _ = grpc_json(rpc_update, original, token)
    confirm_call, restored = grpc_json(rpc_get, {}, token)
    restored_phone = restored.get("customer", {}).get("phone", "") if isinstance(restored.get("customer"), dict) else ""
    passed = all(call.returncode == 0 for call in (update_call, read_call, restore_call, confirm_call)) and observed == marker and restored_phone == original["phone"]
    result = {
        "id": "customer-profile-update-lifecycle", "status": "PASS" if passed else "FAIL",
        "stages": {"update": update_call.returncode, "read_back": read_call.returncode, "restore": restore_call.returncode, "confirm_restore": confirm_call.returncode},
        "persistence_verified": observed == marker, "cleanup_verified": restored_phone == original["phone"],
    }
    if not passed:
        result["diagnostic"] = redact("\n".join(call.stderr[-400:] for call in (update_call, read_call, restore_call, confirm_call) if call.stderr))
    return result


def grpc_discovery() -> dict[str, Any]:
    token = next(iter(RUNTIME_TOKENS.values()), "") or next((os.getenv(name, "") for name in ("CEERAT_ADMIN_TOKEN", "CEERAT_AGENT_TOKEN", "CEERAT_CUSTOMER_TOKEN", "CEERAT_TOKEN") if os.getenv(name, "")), "")
    command = ["grpcurl", "-plaintext"]
    if token:
        command += ["-H", f"Authorization: Bearer {token}"]
    command += [GRPC_ADDR, "list"]
    completed = subprocess.run(command, text=True, capture_output=True, timeout=10, check=False)
    services = sorted(line.strip() for line in completed.stdout.splitlines() if line.strip() and not line.startswith("grpc."))
    status = "PASS" if completed.returncode == 0 and services else ("FAIL" if token else "SKIP")
    return {
        "status": status,
        "address": GRPC_ADDR,
        "service_count": len(services),
        "services": services,
        "diagnostic": redact(completed.stderr[-1000:]) if completed.returncode else "",
    }


def tools_result() -> dict[str, Any]:
    required = {name: shutil.which(name) for name in ("curl", "grpcurl", "python3")}
    return {"status": "PASS" if all(required.values()) else "FAIL", "tools": required}


def stack_healthy() -> bool:
    try:
        with urllib.request.urlopen(AGENT_URL + "/healthz", timeout=2) as response:
            http_ok = response.status == 200
    except Exception:
        http_ok = False
    try:
        host, port = GRPC_ADDR.rsplit(":", 1)
        with socket.create_connection((host, int(port)), timeout=2):
            grpc_ok = True
    except (OSError, ValueError):
        grpc_ok = False
    return http_ok and grpc_ok


def wait_for_stack(timeout_seconds: int = 30) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if stack_healthy():
            return True
        time.sleep(1)
    return stack_healthy()


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "all"
    if action not in {"tools", "read", "security", "write", "all"}:
        print("usage: verify_api.py {tools|read|security|write|all}", file=sys.stderr)
        return 2

    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    artifact_dir = INFRA_DIR / ".verification" / run_id
    artifact_dir.mkdir(parents=True, exist_ok=False)
    started_stack = False
    summary: dict[str, Any] = {"run_id": run_id, "started_at": now(), "action": action, "phase": 2, "results": []}

    tool_check = tools_result()
    summary["tools"] = tool_check
    if tool_check["status"] != "PASS":
        summary["verdict"] = "BLOCKED"
    elif action == "tools":
        summary["verdict"] = "PASS"
    else:
        if not stack_healthy() and os.getenv("VERIFY_API_START_STACK", "").lower() == "true":
            subprocess.run(["make", "start-stack"], cwd=INFRA_DIR, check=True)
            started_stack = True
        if not wait_for_stack():
            summary["verdict"] = "BLOCKED"
            summary["blocker"] = "Local gRPC and agent HTTP endpoints are not healthy. Start with `make start-stack` or set VERIFY_API_START_STACK=true."
        else:
            summary["identities"] = acquire_local_identities()
            summary["discovery"] = grpc_discovery()
            groups = [action] if action != "all" else ["read", "security", "write"]
            scenarios = json.loads(SCENARIOS_PATH.read_text(encoding="utf-8"))
            for group in groups:
                if group == "write" and os.getenv("VERIFY_API_MUTATIONS", "").lower() != "true":
                    summary["results"].append({"id": "write-scenarios", "status": "SKIP", "reason": "VERIFY_API_MUTATIONS=true is required"})
                    continue
                if group == "write" and not scenarios[group]:
                    result = run_customer_profile_lifecycle(run_id)
                    result["group"] = group
                    summary["results"].append(result)
                    continue
                for scenario in scenarios[group]:
                    result = run_http(scenario) if scenario["transport"] == "http" else run_grpc(scenario)
                    result["group"] = group
                    summary["results"].append(result)
            statuses = {item["status"] for item in summary["results"]}
            if "FAIL" in statuses or "ERROR" in statuses or summary["discovery"]["status"] == "FAIL":
                summary["verdict"] = "FAIL"
            elif "SKIP" in statuses or summary["discovery"]["status"] == "SKIP":
                summary["verdict"] = "INCONCLUSIVE"
            else:
                summary["verdict"] = "PASS"

    summary["started_stack"] = started_stack
    summary["finished_at"] = now()
    output_path = artifact_dir / "summary.json"
    output_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"verdict": summary["verdict"], "artifact": str(output_path), "counts": {status: sum(1 for item in summary["results"] if item["status"] == status) for status in ("PASS", "FAIL", "ERROR", "SKIP")}}, indent=2))

    if started_stack and os.getenv("VERIFY_API_KEEP_STACK", "").lower() != "true":
        subprocess.run(["make", "stop-stack"], cwd=INFRA_DIR, check=False)

    return 0 if summary["verdict"] in {"PASS", "INCONCLUSIVE"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
