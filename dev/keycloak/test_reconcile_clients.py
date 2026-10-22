"""Exercise local client reconciliation against a disposable Keycloak API fixture."""
import copy
import json
import os
from pathlib import Path
import subprocess
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[2]

class ReconcileClientsTest(unittest.TestCase):
    def test_existing_realm_gets_codex_client_and_optional_customer_scopes(self):
        realm = json.loads((ROOT / 'dev/keycloak/ceerat-realm.json').read_text())
        clients = {c['clientId']: dict(copy.deepcopy(c), id=c['clientId']) for c in realm['clients'] if c['clientId'] in ['ceerat-web-ui', 'ceerat-customer-ui']}
        scopes = {s['name']: dict(copy.deepcopy(s), id=s['name']) for s in realm['clientScopes']}
        for name in ['profile', 'email', 'offline_access']:
            scopes[name] = {'id': name, 'name': name}
        assigned = {}
        class API(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def respond(self, value=None, status=200):
                self.send_response(status); self.send_header('Content-Type', 'application/json'); self.end_headers()
                if value is not None: self.wfile.write(json.dumps(value).encode())
            def body(self):
                raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                return json.loads(raw) if raw else None
            def do_POST(self):
                if self.path.endswith('/token'):
                    self.rfile.read(int(self.headers.get('Content-Length', 0))); return self.respond({'access_token': 'fixture-token'})
                data = self.body()
                if self.path.endswith('/client-scopes'): scopes[data['name']] = dict(data, id=data['name'])
                elif self.path.endswith('/clients'): clients[data['clientId']] = dict(data, id=data['clientId'])
                else: return self.respond(status=404)
                self.respond(status=201)
            def do_GET(self):
                url = urlparse(self.path)
                if url.path.endswith('/client-scopes'): return self.respond(list(scopes.values()))
                if url.path.endswith('/clients'):
                    name = parse_qs(url.query).get('clientId', [None])[0]
                    return self.respond([c for c in clients.values() if not name or c['clientId'] == name])
                self.respond(status=404)
            def do_PUT(self):
                parts = self.path.split('/'); data = self.body()
                if 'optional-client-scopes' in parts:
                    assigned.setdefault(parts[5], set()).add(parts[-1])
                elif '/clients/' in self.path:
                    clients[data['clientId']] = dict(data, id=parts[-1])
                elif '/client-scopes/' in self.path:
                    scopes[data['name']] = dict(data, id=parts[-1])
                else: return self.respond(status=404)
                self.respond(status=204)
        server = ThreadingHTTPServer(('127.0.0.1', 0), API)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown)
        env = dict(os.environ, CEERAT_KEYCLOAK_SERVER=f'http://127.0.0.1:{server.server_port}', CEERAT_KEYCLOAK_ADMIN_PASSWORD='fixture-only', CEERAT_KEYCLOAK_REALM='ceerat', CEERAT_MCP_RESOURCE='http://localhost:8090/mcp')
        for _ in range(2):
            result = subprocess.run(['ruby', str(ROOT / 'dev/keycloak/reconcile-browser-clients.rb')], env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ceerat-mcp-codex-dev', clients)
        client = clients['ceerat-mcp-codex-dev']
        self.assertTrue(client['publicClient']); self.assertTrue(client['standardFlowEnabled'])
        self.assertFalse(client['directAccessGrantsEnabled']); self.assertFalse(client['serviceAccountsEnabled'])
        self.assertEqual(client['attributes']['pkce.code.challenge.method'], 'S256')
        self.assertEqual(client['redirectUris'], ['http://127.0.0.1:*', 'http://localhost:*'])
        expected = set(client['optionalClientScopes']) - {'offline_access'}
        self.assertTrue(expected <= assigned['ceerat-mcp-codex-dev'])
        self.assertFalse(any('.admin' in name for name in expected))
        audiences = {m.get('config', {}).get('included.custom.audience') for m in client['protocolMappers']}
        self.assertIn('http://localhost:8090/mcp', audiences); self.assertIn('ceerat-api', audiences)

if __name__ == '__main__': unittest.main()
