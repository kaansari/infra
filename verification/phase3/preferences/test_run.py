import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


class HarnessTests(unittest.TestCase):
    def load_runner(self):
        spec = importlib.util.spec_from_file_location("pr08_runner", Path(__file__).with_name("run.py"))
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        return runner

    def test_go_result_never_copies_sensitive_output(self):
        runner = self.load_runner()
        secret = "fixture-password-token-SQL-hostname"
        events = [{"Action": "output", "Output": secret},
                  {"Action": "pass", "Test": "TestPR08Privacy"},
                  {"Action": "pass"}]
        result = runner.go_evidence("\n".join(json.dumps(e) for e in events), True)
        self.assertEqual(result, {"tests_passed": ["TestPR08Privacy"], "required_skips": []})
        self.assertNotIn(secret, json.dumps(result))

    def test_required_database_tests_must_not_skip(self):
        runner = self.load_runner()
        result = runner.go_evidence(json.dumps({"Action": "skip", "Test": "TestOwnershipPostgres"}), True)
        self.assertEqual(result["required_skips"], ["TestOwnershipPostgres"])

    def test_zero_integration_tests_fail_closed(self):
        runner = self.load_runner()
        with self.assertRaises(runner.GateFailure):
            runner.require_integration({"tests_passed": [], "required_skips": []})

    def test_partial_integration_cannot_satisfy_matrix(self):
        runner = self.load_runner()
        with self.assertRaises(runner.GateFailure):
            runner.require_integration({"tests_passed": ["TestPR08IdentityAuthorizationAndReadiness"], "required_skips": []})

    def test_durable_gateway_skips_are_required(self):
        runner = self.load_runner()
        for name in ("TestPreferenceDurableRestartAndHorizontalConfirmation", "TestPreferenceDurableOperationAndExpiryBinding"):
            evidence = runner.go_evidence(json.dumps({"Action": "skip", "Test": name}), True)
            self.assertEqual(evidence["required_skips"], [name])

    def test_missing_gateway_database_tests_fail_closed(self):
        runner = self.load_runner()
        with self.assertRaises(runner.GateFailure):
            runner.require_owning_suite("gateway", {"tests_passed": ["TestReadinessAuthenticatedPrivateRead"], "required_skips": []})

    def test_complete_parent_inventory_passes(self):
        runner = self.load_runner()
        runner.require_integration({"tests_passed": sorted(runner.REQUIRED_INTEGRATION), "required_skips": []})
        for name, expected in runner.REQUIRED_OWNING.items():
            runner.require_owning_suite(name, {"tests_passed": sorted(expected), "required_skips": []})

    def test_failure_coordinates_exclude_diagnostic_contents(self):
        runner = self.load_runner()
        secret = "private-credential-and-note"
        evidence = runner.go_evidence(json.dumps({"Action": "output", "Output": "integration_test.go:23: " + secret}), True)
        self.assertEqual(evidence["failure_locations"], [{"file": "integration_test.go", "line": 23}])
        self.assertNotIn(secret, json.dumps(evidence))

    def test_report_schema_excludes_raw_execution_data(self):
        runner = self.load_runner()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "result.json"
            runner.write_report(target, {"schema_version": 1, "status": "failed", "checks": []})
            self.assertEqual(json.loads(target.read_text())["status"], "failed")


if __name__ == "__main__":
    unittest.main()
