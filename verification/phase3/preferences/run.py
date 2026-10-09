#!/usr/bin/env python3
"""PR08 local gate. Never uses an existing database or persists raw test output."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
INFRA = HERE.parents[2]
STACK = INFRA.parent
MODULES = {
    "contract": STACK / "contracts-repo/packages/ceerat-contracts",
    "service": STACK / "services-repo/services/ceerat-user-service",
    "gateway": STACK / "apps-repo/ai/ceerat-agent-gateway",
}
REQUIRED_INTEGRATION = {
    "TestPR08IdentityAuthorizationAndReadiness",
    "TestPR08TwoCustomersLifecycleAndReplay",
    "TestPR08LostReplyStatusWithoutRedispatch",
    "TestPR08ContractSchemaAndServiceSkew",
    "TestPR08MCPAuthorityMalformedPromptAndPagination",
    "TestPR08PostgresRestartReadinessAndDurability",
    "TestPR08TXSEFixturePreferenceIsolationAndIndependentFailure",
}
REQUIRED_OWNING = {
    "gateway": {"TestPreferenceDurableRestartAndHorizontalConfirmation", "TestPreferenceDurableOperationAndExpiryBinding",
                "TestReadinessAuthenticatedPrivateRead", "TestReadinessPrivateTimeoutAndLiveness"},
    "service": {"TestSecurityContextMinimizationAndOpaqueReferencesPostgres", "TestSecurityIdempotencyDependencyFailurePostgres",
                "TestSecurityReconciliationDependencyRecoveryAndAuditPrivacyPostgres",
                "TestWriteConcurrentConfirmAndLogicalCreatePostgres", "TestWriteUpdateUpdateAndUpdateDeleteRacesPostgres",
                "TestWriteDefinitionDisableRacePostgres", "TestWriteGRPCJWTScopesRBACAndOwnershipPostgres",
                "TestListFiltersAndBoundPaginationPostgres"},
    "contract": {"TestPreferenceAggregateResponseSizeFailsPrivately", "TestPreferenceJSONClosedUnionRejectsNullAndAmbiguity",
                 "TestPreferenceNestedJSONAuthorityRejectedBeforeDispatch"},
}
REQUIRED_PARENTS = REQUIRED_INTEGRATION | set().union(*REQUIRED_OWNING.values())


class GateFailure(Exception):
    pass


def go_evidence(output, required):
    passed, skipped, failed, locations = set(), set(), set(), set()
    for line in output.splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        # Retain source coordinates only, never diagnostic messages or values.
        for match in re.finditer(r"\b(fixture_test.go|integration_test.go|txse_boundary_test.go):([0-9]{1,5}):", event.get("Output", "")):
            locations.add((match.group(1), int(match.group(2))))
        name = event.get("Test", "")
        if not re.fullmatch(r"[A-Za-z0-9_/=-]{1,220}", name):
            continue
        if event.get("Action") == "pass":
            passed.add(name)
        if event.get("Action") == "fail":
            failed.add(name)
        if required and event.get("Action") == "skip" and (
                "Postgres" in name or name.startswith("TestPR08") or name.split("/")[0] in REQUIRED_PARENTS):
            skipped.add(name)
    evidence = {"tests_passed": sorted(passed), "required_skips": sorted(skipped)}
    if failed:
        evidence["tests_failed"] = sorted(failed)
    if locations:
        evidence["failure_locations"] = [{"file": name, "line": line} for name, line in sorted(locations)]
    return evidence


def require_integration(evidence):
    if not REQUIRED_INTEGRATION.issubset(set(evidence["tests_passed"])) or evidence["required_skips"]:
        raise GateFailure("integration_coverage_missing")


def require_owning_suite(name, evidence):
    if not REQUIRED_OWNING[name].issubset(set(evidence["tests_passed"])) or evidence["required_skips"]:
        raise GateFailure("owning_coverage_missing")


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def tuple_evidence():
    result = {}
    for name, module in MODULES.items():
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=str(module)).decode().strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--", "."], cwd=str(module)))
        digest = hashlib.sha256()
        for source in sorted(module.rglob("*")):
            relative = source.relative_to(module)
            if any(part in ("vendor", ".git", "bin", "__pycache__") for part in relative.parts):
                continue
            if source.is_file() and source.suffix in (".go", ".mod", ".sum", ".proto", ".sql"):
                digest.update(str(relative).encode())
                digest.update(source.read_bytes())
        result[name] = {"commit": commit, "dirty": dirty, "source_sha256": digest.hexdigest()}
    return result


class Runner:
    def __init__(self, report):
        self.report = report
        self.env = os.environ.copy()
        self.env.update({"PYTHONDONTWRITEBYTECODE": "1"})

    def check(self, name, command, cwd=INFRA, env=None, go=False, integration=False, owning=None, timeout=1800):
        print("PR08: " + name, flush=True)
        started = time.monotonic()
        effective = self.env.copy()
        effective.update(env or {})
        entry = {"name": name, "status": "failed"}
        self.report["checks"].append(entry)
        try:
            completed = subprocess.run(command, cwd=str(cwd), env=effective,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       timeout=timeout)
            output = completed.stdout.decode("utf-8", errors="replace")
            # Raw output never enters the report, logs or raised exceptions.
            if go:
                evidence = go_evidence(output, True)
                entry.update(evidence)
                if evidence["required_skips"]:
                    raise GateFailure("required_database_test_skipped")
                if integration:
                    require_integration(evidence)
                if owning:
                    require_owning_suite(owning, evidence)
            if completed.returncode:
                raise GateFailure("command_failed")
            entry["status"] = "passed"
        except subprocess.TimeoutExpired:
            entry["failure_code"] = "timeout"
            raise GateFailure("timeout")
        except GateFailure as error:
            entry["failure_code"] = str(error)
            raise
        finally:
            entry["seconds"] = round(time.monotonic() - started, 3)

    def run(self, pg_bin, focused, integration_only=False):
        self.check("harness_redaction_tests", ["python3", "-m", "unittest", "discover", "-s", str(HERE), "-p", "test_run.py"])
        self.check("proto", ["make", "proto"], MODULES["contract"])
        with tempfile.TemporaryDirectory(prefix="ceerat-pr08-") as temporary:
            private = Path(temporary)
            data = private / "data"
            marker = private / "owned-by-pr08"
            marker.write_text("disposable PR08 database\n")
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            pg_ctl = str(pg_bin / "pg_ctl")
            self.env["PATH"] = str(pg_bin) + os.pathsep + self.env.get("PATH", "")
            self.env.update({"DB_HOST": "127.0.0.1", "DB_PORT": str(port),
                             "DB_USER": "postgres", "DB_NAME": "ceerat_pr08", "DB_PASSWORD": "pr08-local",
                             "DB_SSLMODE": "disable", "DB_SCHEMA": "public"})
            dsn = "host=127.0.0.1 port={} user=postgres dbname=ceerat_pr08 sslmode=disable".format(port)
            self.env.update({"CEERAT_PR08_DATABASE_URL": dsn, "CEERAT_TEST_DATABASE_URL": dsn,
                             "CEERAT_TEST_POSTGRES_URL": dsn, "DATABASE_URL": dsn,
                             "CEERAT_PR08_PG_CTL": pg_ctl, "CEERAT_PR08_PG_DATA": str(data),
                             "CEERAT_PR08_PG_MARKER": str(marker)})
            self.check("disposable_init", [str(pg_bin / "initdb"), "-D", str(data), "-A", "trust", "-U", "postgres", "--no-locale", "-E", "UTF8"])
            try:
                self.check("disposable_start", [pg_ctl, "-D", str(data), "-l", str(private / "postgres.log"), "-o",
                                               "-F -h 127.0.0.1 -p {} -k {}".format(port, temporary), "-w", "start"])
                self.check("disposable_database", [str(pg_bin / "createdb"), "-h", "127.0.0.1", "-p", str(port), "-U", "postgres", "ceerat_pr08"])
                self.check("bootstrap", ["go", "run", "-mod=vendor", "./cmd/dbbootstrap"], MODULES["service"], {"GOWORK": "off"})
                self.check("migrations", ["bash", "scripts/db-migrate.sh"], MODULES["service"])
                self.check("preflight", ["bash", "scripts/db-preflight.sh"], MODULES["service"])
                for name, module in MODULES.items():
                    if integration_only:
                        continue
                    env = {"GOWORK": "off"}
                    args = ["-mod=vendor"] if name != "contract" else []
                    self.check(name + "_race", ["go", "test"] + args + ["-json", "-race", "-count=1", "./..."], module, env, go=True, owning=name)
                    self.check(name + "_build", ["go", "build"] + args + ["./..."], module, env)
                self.check("cross_repo_integration", ["go", "test", "-mod=mod", "-json", "-race", "-count=1", "./..."], HERE, {"GOWORK": "off"}, go=True, integration=True)
                for target in ("FuzzPreferenceClosedWire", "FuzzPreferenceLiteralText", "FuzzPreferenceExactNumbers",
                               "FuzzPreferenceScopeUnion", "FuzzPreferenceCollectionBounds", "FuzzPreferenceClosedRequestJSON"):
                    if integration_only:
                        continue
                    self.check("contract_" + target, ["go", "test", "./proto/preference", "-run=^$", "-fuzz=^" + target + "$", "-fuzztime=10s", "-parallel=2"], MODULES["contract"], {"GOWORK": "off"})
                for target in ("FuzzPreferenceMCPClosedUnions", "FuzzPreferenceMCPPromptStrings"):
                    if integration_only:
                        continue
                    self.check("gateway_" + target, ["go", "test", "-mod=vendor", "./internal/gateway", "-run=^$", "-fuzz=^" + target + "$", "-fuzztime=10s", "-parallel=2"], MODULES["gateway"], {"GOWORK": "off"})
                if not focused:
                    self.check("verify_platform", ["make", "verify-platform"])
                    for name, args in (("builder_rbac", ["rbac", "check"]), ("builder_apps", ["check", "apps"]),
                                       ("builder_drift", ["check", "drift"]),
                                       ("builder_preference", ["verify", "contract-and-service", "preference.PreferenceService"])):
                        self.check(name, ["ceerat-builder"] + args + ["--output", "json"], STACK / "ceerat-platform-builder-agent")
            finally:
                # This data directory was created above, never accepted from an environment variable.
                completed = subprocess.run([pg_ctl, "-D", str(data), "-m", "immediate", "-w", "stop"],
                                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                stopped = completed.returncode == 0 or not (data / "postmaster.pid").exists()
                self.report["checks"].append({"name": "disposable_cleanup", "status": "passed" if stopped else "failed"})
                if not stopped:
                    raise GateFailure("cleanup_failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", default=os.environ.get("CEERAT_PR08_PG_BIN", "/usr/local/opt/postgresql@14/bin"))
    parser.add_argument("--output", type=Path, default=HERE / "evidence/latest.json")
    parser.add_argument("--focused", action="store_true", help="Diagnostic run only; cannot satisfy the full gate")
    parser.add_argument("--integration-only", action="store_true", help="Diagnostic bootstrap and cross-repo tests only")
    args = parser.parse_args()
    args.focused = args.focused or args.integration_only
    report = {"schema_version": 1, "status": "failed", "gate": "diagnostic" if args.focused else "full",
              "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "tuple": tuple_evidence(), "checks": []}
    try:
        if not args.focused and any(revision["dirty"] for revision in report["tuple"].values()):
            report["checks"].append({"name": "committed_source_tuple", "status": "failed", "failure_code": "uncommitted_source"})
            raise GateFailure("uncommitted_source")
        if not all((Path(args.pg_bin) / name).is_file() for name in ("initdb", "pg_ctl", "createdb")):
            raise GateFailure("postgres_tools_missing")
        Runner(report).run(Path(args.pg_bin), args.focused, args.integration_only)
        if tuple_evidence() != report["tuple"]:
            report["checks"].append({"name": "source_tuple_stable", "status": "failed", "failure_code": "source_changed_during_gate"})
            raise GateFailure("source_changed_during_gate")
        report["checks"].append({"name": "source_tuple_stable", "status": "passed"})
        report["status"] = "diagnostic_passed" if args.focused else "passed"
    except (GateFailure, OSError, subprocess.SubprocessError):
        report["status"] = "failed"
    finally:
        report["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        write_report(args.output, report)
    print(json.dumps({"status": report["status"], "checks": len(report["checks"])}))
    return 0 if report["status"] in ("passed", "diagnostic_passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
