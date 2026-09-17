import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("evidence", Path(__file__).with_name("verify-observability-evidence.py"))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)

TRACE = "4bf92f3577b34da6a3ce929d0e0e4736"


class EvidenceTest(unittest.TestCase):
    def test_correlated_direct_and_mcp(self):
        rows = [
            {"msg": "grpc.request", "request_id": "req_direct", "trace_id": TRACE, "origin": "direct", "authorization_decision": "denied", "category": "scope"},
            {"msg": "agent_gateway.tool_call", "request_id": "req_mcp", "trace_id": TRACE, "origin": "mcp", "outcome": "completed", "decision_stage": "gateway_early"},
            {"msg": "grpc.request", "request_id": "req_mcp", "trace_id": TRACE, "origin": "mcp", "authorization_decision": "allowed", "category": "handler"},
        ]
        self.assertEqual(evidence.verify(rows), {"direct_traces": 1, "mcp_traces": 1, "result": "PASS"})

    def test_missing_authoritative_decision_fails(self):
        rows = [
            {"msg": "grpc.request", "request_id": "req_direct", "trace_id": TRACE, "origin": "direct"},
            {"msg": "agent_gateway.tool_call", "request_id": "req_mcp", "trace_id": TRACE, "outcome": "completed"},
        ]
        with self.assertRaisesRegex(ValueError, "matching authoritative"):
            evidence.verify(rows)

    def test_secret_and_pii_rejected(self):
        base = {"msg": "grpc.request", "request_id": "req_direct", "trace_id": TRACE, "origin": "direct"}
        for leak in ({"authorization": "Bearer synthetic-secret"}, {"message": "person@example.test"}, {"idempotency_key": "private"}):
            with self.subTest(leak=leak), self.assertRaises(ValueError):
                evidence.verify([dict(base, **leak)])


if __name__ == "__main__":
    unittest.main()
