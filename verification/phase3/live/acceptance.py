#!/usr/bin/env python3
"""Read-only live preflight and strict operator-reviewed two-client evidence gate."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
INFRA = HERE.parents[2]
SUPPORTED = {
    'contract': '69613314fd44dafb7c8724bd795af6996893d3be',
    'service': 'fddee2c12bad4c33e826c7bd639e3201617678c0',
    'gateway': '4cca58df129480624b6ea76fa43593fe6879e9d9',
}
CASES = ('discovery definitions empty_state create_preview create_confirm read_projections replay '
         'changed_payload_conflict stale_update fresh_update_preview fresh_update_confirm version_increments '
         'customer_isolation independent_logical_key_preview independent_logical_key_confirm delete_preview '
         'delete_confirm deletion_absent unknown_prepare unknown_confirm unknown_status token_refresh '
         'scope_denial revocation rate_limit dependency_failure prompt_fixture cleanup txse_presentation '
         'txse_explicit_override txse_entitlement_denial txse_safety_fields').split()
CONFIRMATIONS = {'create_confirm', 'fresh_update_confirm', 'independent_logical_key_confirm', 'delete_confirm', 'unknown_confirm'}
OPERATORS = ('deployed_tuple database_preflight keycloak_policy private_rpc hosted_versions '
             'logs_privacy builder_gates supported_replay_procedure controlled_failure_procedure').split()
STATUSES = {'PASS', 'FAIL', 'MANUAL_REQUIRED'}
ERRORS = {'NONE', 'UNAUTHENTICATED', 'INSUFFICIENT_SCOPE', 'PERMISSION_DENIED', 'INVALID_ARGUMENT',
          'NOT_FOUND', 'CONFLICT', 'RATE_LIMITED', 'DEPENDENCY_UNAVAILABLE', 'OUTCOME_UNKNOWN', 'ALREADY_EXISTS',
          'PRECONDITION_FAILED', 'IDEMPOTENCY_CONFLICT', 'GRANT_REVOKED', 'FORBIDDEN', 'TOKEN_EXPIRED', 'INTERNAL', 'IDENTITY_VERIFICATION_REQUIRED'}
STATES = {'not_started', 'prepared', 'completed', 'failed', 'dispatching', 'outcome_unknown'}
EXPECTED = {case: ({'completed'}, {'NONE'}) for case in CASES}
for _case, _codes in {
    'changed_payload_conflict': {'IDEMPOTENCY_CONFLICT'},
    'stale_update': {'CONFLICT', 'PRECONDITION_FAILED'},
    'customer_isolation': {'NOT_FOUND', 'PRECONDITION_FAILED', 'INVALID_ARGUMENT'},
    'deletion_absent': {'NOT_FOUND'},
    'scope_denial': {'INSUFFICIENT_SCOPE', 'FORBIDDEN'},
    'revocation': {'UNAUTHENTICATED', 'GRANT_REVOKED'},
    'rate_limit': {'RATE_LIMITED'},
    'dependency_failure': {'DEPENDENCY_UNAVAILABLE'},
    'txse_entitlement_denial': {'FORBIDDEN', 'INSUFFICIENT_SCOPE'},
}.items():
    EXPECTED[_case] = ({'not_started'}, _codes)
EXPECTED['unknown_confirm'] = ({'outcome_unknown'}, {'OUTCOME_UNKNOWN'})


class InvalidEvidence(Exception):
    pass


def require(condition):
    if not condition:
        raise InvalidEvidence('invalid_redacted_evidence')


def exact(value, keys):
    require(isinstance(value, dict) and set(value) == set(keys))


def parse_evidence(raw):
    require(len(raw.encode('utf-8')) <= 256 * 1024)
    def closed_pairs(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result
    return validate(json.loads(raw, object_pairs_hook=closed_pairs))


def template():
    return {'schema_version': 1, 'supported_tuple': dict(SUPPORTED),
            'operator': {name: {'status': 'MANUAL_REQUIRED'} for name in OPERATORS},
            'clients': {name: {'app_version_id': '', 'fresh_consent': False, 'reconnected': False,
                               'operator_reviewed': False,
                               'checks': {case: {'status': 'MANUAL_REQUIRED'} for case in CASES}}
                        for name in ('chatgpt', 'codex')}}


def validate(report):
    exact(report, ('schema_version', 'supported_tuple', 'operator', 'clients'))
    require(report['schema_version'] == 1 and type(report['schema_version']) is int)
    require(report['supported_tuple'] == SUPPORTED)
    exact(report['operator'], OPERATORS)
    for check in report['operator'].values():
        exact(check, ('status',))
        require(check['status'] in STATUSES)
    exact(report['clients'], ('chatgpt', 'codex'))
    for client in report['clients'].values():
        exact(client, ('app_version_id', 'fresh_consent', 'reconnected', 'operator_reviewed', 'checks'))
        require(isinstance(client['app_version_id'], str) and re.fullmatch(r'[A-Za-z0-9_-]{0,128}', client['app_version_id']) is not None)
        for name in ('fresh_consent', 'reconnected', 'operator_reviewed'):
            require(type(client[name]) is bool)
        exact(client['checks'], CASES)
        for name, check in client['checks'].items():
            allowed = {'status', 'request_ids', 'operation_state', 'error_code', 'profile_version', 'resource_version', 'count', 'write_count', 'preview_count', 'confirmed_write_count'}
            if name in CONFIRMATIONS:
                allowed.add('human_confirmed')
            if name == 'replay':
                allowed.add('replayed')
            if name == 'cleanup':
                allowed.update(('original_state_restored', 'initial_count', 'final_count'))
            require(isinstance(check, dict) and set(check).issubset(allowed) and 'status' in check)
            require(check['status'] in STATUSES)
            for key, value in check.items():
                if key == 'request_ids':
                    require(isinstance(value, list) and len(value) <= 30)
                    require(all(isinstance(item, str) and re.fullmatch(r'(?:req_[0-9a-f]{32}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})', item) for item in value))
                elif key == 'operation_state':
                    require(value in STATES)
                elif key == 'error_code':
                    require(value in ERRORS)
                elif key in ('human_confirmed', 'replayed', 'original_state_restored'):
                    require(type(value) is bool)
                elif key != 'status':
                    require(type(value) is int and 0 <= value <= 2**53 - 1)
    return report


def can_freeze(report):
    validate(report)
    if any(check['status'] != 'PASS' for check in report['operator'].values()):
        return False
    for client in report['clients'].values():
        if not client['app_version_id'] or not all(client[key] for key in ('fresh_consent', 'reconnected', 'operator_reviewed')):
            return False
        for name, check in client['checks'].items():
            if check['status'] != 'PASS' or not check.get('request_ids'):
                return False
            states, codes = EXPECTED[name]
            if check.get('operation_state') not in states or check.get('error_code') not in codes:
                return False
            if name in CONFIRMATIONS and check.get('human_confirmed') is not True:
                return False
            if name in CONFIRMATIONS and check.get('write_count', 0) < 1:
                return False
            writes = check.get('write_count', 0)
            if writes and (check.get('confirmed_write_count') != writes or check.get('preview_count') != writes):
                return False
        if client['checks']['replay'].get('replayed') is not True:
            return False
        cleanup = client['checks']['cleanup']
        if cleanup.get('original_state_restored') is not True or 'initial_count' not in cleanup or cleanup.get('final_count') != cleanup['initial_count']:
            return False
    return True


def write_private(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write('\n')


def fetch(origin, path, payload=None, bearer=''):
    headers = {'Accept': 'application/json'}
    if bearer:
        headers['Authorization'] = 'Bearer ' + bearer
    data = None if payload is None else json.dumps(payload).encode()
    if data:
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(origin + path, data=data, headers=headers)
    # Never follow redirects carrying credentials to a different endpoint.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, hdrs, newurl):
            return None
    try:
        ca_file = os.environ.get('CEERAT_PR09_CA_FILE')
        if not ca_file and Path('/etc/ssl/cert.pem').is_file():
            ca_file = '/etc/ssl/cert.pem'
        context = ssl.create_default_context(cafile=ca_file)
        with urllib.request.build_opener(NoRedirect, urllib.request.HTTPSHandler(context=context)).open(request, timeout=20) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
            require(len(raw) <= 2 * 1024 * 1024)
            return response.status, json.loads(raw)
    except urllib.error.HTTPError as error:
        return error.code, {}


def preflight(origin, bearer=''):
    parsed = urllib.parse.urlsplit(origin)
    require(parsed.scheme == 'https' and parsed.hostname and parsed.path in ('', '/') and not parsed.query and not parsed.fragment and not parsed.username and not parsed.password)
    origin = origin.rstrip('/')
    checks = {}
    def check(name, function):
        try:
            checks[name] = 'PASS' if function() else 'FAIL'
        except Exception:
            checks[name] = 'FAIL'
    check('liveness', lambda: fetch(origin, '/healthz')[0] == 200)
    def metadata():
        code, value = fetch(origin, '/.well-known/oauth-protected-resource')
        return code == 200 and value.get('resource') == origin + '/mcp' and {'ceerat.preferences.read', 'ceerat.preferences.write'}.issubset(set(value.get('scopes_supported', [])))
    check('preference_scopes_metadata', metadata)
    check('anonymous_readiness_denied', lambda: fetch(origin, '/readyz')[0] == 401)
    expected = []
    for file in ('preference_tools_snapshot.json', 'preference_write_tools_snapshot.json'):
        expected.extend(json.loads((INFRA.parent / 'apps-repo/ai/ceerat-agent-gateway/internal/gateway' / file).read_text()))
    def schemas():
        code, value = fetch(origin, '/mcp', {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list', 'params': {}}, bearer)
        actual = value.get('result', {}).get('tools', [])
        require(isinstance(actual, list) and all(isinstance(tool, dict) and isinstance(tool.get('name'), str) for tool in actual))
        require(len({tool['name'] for tool in actual}) == len(actual))
        wanted = {tool['name']: tool for tool in expected}
        selected = {tool['name']: tool for tool in actual if tool.get('name', '').startswith('preferences_')}
        return code == 200 and selected == wanted
    check('exact_preference_schemas', schemas)
    if bearer:
        check('authenticated_private_readiness', lambda: fetch(origin, '/readyz', bearer=bearer)[0] == 200)
    else:
        checks['authenticated_private_readiness'] = 'MANUAL_REQUIRED'
    return {'schema_version': 1, 'generated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'contains_credentials': False, 'checks': checks,
            'status': 'FAIL' if 'FAIL' in checks.values() else 'MANUAL_REQUIRED'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('template', 'preflight', 'validate', 'freeze-check'))
    parser.add_argument('--input', type=Path)
    parser.add_argument('--output', type=Path, default=INFRA / '.verification/phase3-live.json')
    parser.add_argument('--gateway', default='https://ceerat-agent-gateway.onrender.com')
    args = parser.parse_args()
    try:
        if args.action == 'template':
            write_private(args.output, template())
            print('MANUAL_REQUIRED')
            return 0
        if args.action == 'preflight':
            report = preflight(args.gateway, os.environ.get('CEERAT_PR09_ACCESS_TOKEN', ''))
            write_private(args.output, report)
            print(json.dumps(report))
            return 1 if report['status'] == 'FAIL' else 2
        require(args.input is not None)
        require(args.input.stat().st_size <= 256 * 1024)
        report = parse_evidence(args.input.read_text())
        if args.action == 'freeze-check':
            passed = can_freeze(report)
            print('PASS' if passed else 'MANUAL_REQUIRED')
            return 0 if passed else 2
        print('VALID_REDACTED_EVIDENCE')
        return 0
    except Exception:
        print('INVALID_REDACTED_EVIDENCE')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
