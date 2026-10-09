import importlib.util
import json
from pathlib import Path
import unittest


def load():
    spec = importlib.util.spec_from_file_location('acceptance', Path(__file__).with_name('acceptance.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fill_client(client, module):
    client.update({'app_version_id': 'test-version', 'fresh_consent': True, 'reconnected': True, 'operator_reviewed': True})
    for case, check in client['checks'].items():
        check.update({'status': 'PASS', 'request_ids': ['11111111-1111-4111-8111-111111111111']})
        check.update({'operation_state': next(iter(module.EXPECTED[case][0])), 'error_code': next(iter(module.EXPECTED[case][1]))})
        if case in module.CONFIRMATIONS:
            check['human_confirmed'] = True
            check.update({'write_count': 1, 'confirmed_write_count': 1, 'preview_count': 1})
    client['checks']['replay']['replayed'] = True
    client['checks']['cleanup'].update({'original_state_restored': True, 'initial_count': 0, 'final_count': 0})


class AcceptanceTests(unittest.TestCase):
    def test_automated_preflight_does_not_close_clients(self):
        m = load()
        report = m.template()
        for check in report['operator'].values():
            check['status'] = 'PASS'
        self.assertFalse(m.can_freeze(report))

    def test_one_client_cannot_close_milestone(self):
        m = load()
        report = m.template()
        for check in report['operator'].values():
            check['status'] = 'PASS'
        fill_client(report['clients']['codex'], m)
        self.assertFalse(m.can_freeze(report))

    def test_missing_confirmation_and_cleanup_fail(self):
        m = load()
        report = m.template()
        for check in report['operator'].values():
            check['status'] = 'PASS'
        for client in report['clients'].values():
            fill_client(client, m)
        self.assertTrue(m.can_freeze(report))
        report['clients']['chatgpt']['checks']['create_confirm']['human_confirmed'] = False
        self.assertFalse(m.can_freeze(report))
        report['clients']['chatgpt']['checks']['create_confirm']['human_confirmed'] = True
        report['clients']['codex']['checks']['cleanup']['status'] = 'MANUAL_REQUIRED'
        self.assertFalse(m.can_freeze(report))

    def test_private_fields_and_unbounded_values_are_rejected(self):
        m = load()
        for field in ('token', 'preparation_id', 'preference_id', 'value', 'key', 'email', 'note', 'page_token', 'idempotency_key'):
            report = m.template()
            report['clients']['codex']['checks']['discovery'][field] = 'secret'
            with self.assertRaises(m.InvalidEvidence):
                m.validate(report)
        report = m.template()
        report['clients']['codex']['checks']['discovery']['error_code'] = 'SQL credential hostname'
        with self.assertRaises(m.InvalidEvidence):
            m.validate(report)

    def test_missing_case_and_forged_client_fail_closed(self):
        m = load()
        report = m.template()
        del report['clients']['chatgpt']['checks']['cleanup']
        with self.assertRaises(m.InvalidEvidence):
            m.validate(report)
        report = m.template()
        report['clients']['other'] = report['clients'].pop('codex')
        with self.assertRaises(m.InvalidEvidence):
            m.validate(report)

    def test_actual_gateway_request_id_is_accepted(self):
        m = load()
        report = m.template()
        report['clients']['codex']['checks']['discovery']['request_ids'] = ['req_' + 'a' * 32]
        m.validate(report)

    def test_unconfirmed_cleanup_write_cannot_freeze(self):
        m = load()
        report = m.template()
        for check in report['operator'].values():
            check['status'] = 'PASS'
        for client in report['clients'].values():
            fill_client(client, m)
        report['clients']['codex']['checks']['cleanup'].update({'write_count': 2, 'confirmed_write_count': 1, 'preview_count': 2})
        self.assertFalse(m.can_freeze(report))

    def test_duplicate_fields_and_oversized_evidence_are_rejected(self):
        m = load()
        raw = json.dumps(m.template()).replace('"schema_version": 1', '"schema_version": 1, "schema_version": 1')
        with self.assertRaises(m.InvalidEvidence):
            m.parse_evidence(raw)
        with self.assertRaises(m.InvalidEvidence):
            m.parse_evidence(' ' * (256 * 1024 + 1))

    def test_current_gateway_error_codes_are_recordable(self):
        m = load()
        for code in ('PRECONDITION_FAILED', 'IDEMPOTENCY_CONFLICT', 'GRANT_REVOKED', 'FORBIDDEN', 'TOKEN_EXPIRED', 'INTERNAL'):
            report = m.template()
            report['clients']['codex']['checks']['changed_payload_conflict']['error_code'] = code
            m.validate(report)

    def test_readonly_preflight_matches_current_schema_and_never_closes(self):
        from unittest.mock import patch
        m = load()
        origin = 'https://fixture.invalid'
        tools = []
        for filename in ('preference_tools_snapshot.json', 'preference_write_tools_snapshot.json'):
            tools.extend(json.loads((m.INFRA.parent / 'apps-repo/ai/ceerat-agent-gateway/internal/gateway' / filename).read_text()))
        def fake_fetch(target, path, payload=None, bearer=''):
            self.assertEqual(target, origin)
            if path == '/healthz':
                return 200, {}
            if path == '/.well-known/oauth-protected-resource':
                return 200, {'resource': origin + '/mcp', 'scopes_supported': ['ceerat.preferences.read', 'ceerat.preferences.write']}
            if path == '/readyz':
                return (200 if bearer else 401), {}
            self.assertEqual(payload['method'], 'tools/list')
            return 200, {'result': {'tools': tools}}
        with patch.object(m, 'fetch', fake_fetch):
            report = m.preflight(origin, 'private-test-bearer')
        self.assertTrue(all(value == 'PASS' for value in report['checks'].values()))
        self.assertEqual(report['status'], 'MANUAL_REQUIRED')
        self.assertNotIn('private-test-bearer', json.dumps(report))

    def test_contradictory_unknown_and_failed_success_cannot_freeze(self):
        m = load()
        for case, change in (('unknown_confirm', {'operation_state': 'completed'}),
                             ('unknown_status', {'operation_state': 'outcome_unknown'}),
                             ('create_confirm', {'error_code': 'DEPENDENCY_UNAVAILABLE'})):
            report = m.template()
            for check in report['operator'].values():
                check['status'] = 'PASS'
            for client in report['clients'].values():
                fill_client(client, m)
            report['clients']['codex']['checks'][case].update(change)
            self.assertFalse(m.can_freeze(report))

    def test_duplicate_advertised_tools_fail_preflight(self):
        from unittest.mock import patch
        m = load()
        tools = []
        for filename in ('preference_tools_snapshot.json', 'preference_write_tools_snapshot.json'):
            tools.extend(json.loads((m.INFRA.parent / 'apps-repo/ai/ceerat-agent-gateway/internal/gateway' / filename).read_text()))
        duplicate = dict(tools[0])
        duplicate['inputSchema'] = {'type': 'object'}
        with patch.object(m, 'fetch', return_value=(200, {'result': {'tools': [duplicate] + tools}})):
            report = m.preflight('https://fixture.invalid')
        self.assertEqual(report['checks']['exact_preference_schemas'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
