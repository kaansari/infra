import importlib.util
import json
from pathlib import Path
import subprocess
import os
import tempfile
import signal
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('local_tls', ROOT / 'k8-scripts/local_tls.py')
local_tls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_tls)

class LocalTLSConfigurationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        rendered = subprocess.check_output(['kubectl', 'kustomize', str(ROOT / 'k8s')])
        cls.base = json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', 'print JSON.generate(YAML.load_stream(STDIN.read))'], input=rendered))

    def setUp(self):
        self.docs = local_tls.configure(self.base, '10.43.0.50', 'ceerat/services:dev', 'ceerat/apps:dev')
        self.deploys = {d['metadata']['name']: d for d in self.docs if d['kind'] == 'Deployment'}

    def test_portals_use_same_https_issuer_and_trust_ca_without_private_keys(self):
        for name in ['ceerat-customer-ui', 'ceerat-web-ui', 'ceerat-admin-ui']:
            pod = self.deploys[name]['spec']['template']['spec']
            env = {e['name']: e.get('value') for e in pod['containers'][0]['env']}
            self.assertEqual(env['SSL_CERT_FILE'], '/etc/ceerat/ca/ca.crt')
            self.assertEqual(env['CEERAT_GRPC_TLS_MODE'], 'tls')
            self.assertEqual(env['CEERAT_GRPC_TLS_SERVER_NAME'], local_tls.GRPC_NAME)
            self.assertEqual(pod['hostAliases'], [{'ip': '10.43.0.50', 'hostnames': ['auth.localhost', 'localhost']}])
            self.assertFalse(any('secret' in v for v in pod['volumes']))
        for d in self.docs:
            if d['kind'] == 'ConfigMap' and d['metadata']['name'] == 'ceerat-platform-config':
                self.assertEqual(d['data']['CEERAT_OAUTH_ISSUER'], local_tls.ISSUER)
                self.assertEqual(d['data']['CEERAT_OAUTH_AUDIENCE'], 'ceerat-api')

    def test_private_grpc_server_requires_certificate_and_clients_verify_hostname(self):
        for name in ['ceerat-user-service', 'ceerat-agent-service', 'ceerat-agent-gateway']:
            pod = self.deploys[name]['spec']['template']['spec']
            env = {e['name']: e.get('value') for e in pod['containers'][0]['env']}
            prefix = 'CEERAT_GRPC' if name == 'ceerat-user-service' else 'CEERAT_USER_SERVICE'
            self.assertEqual(env[prefix + '_TLS_MODE'], 'tls')
            self.assertEqual(env[prefix + '_TLS_CA_FILE'], '/etc/ceerat/ca/ca.crt')
            if name == 'ceerat-user-service':
                self.assertEqual(env[prefix + '_TLS_KEY_FILE'], '/etc/ceerat/tls/tls.key')
                init = pod['initContainers'][0]
                self.assertIn('bash /app/scripts/db-bootstrap-if-empty.sh', init['command'][2])
                self.assertIn('bash /app/scripts/db-preflight.sh', init['command'][2])
            else:
                self.assertEqual(env[prefix + '_TLS_SERVER_NAME'], local_tls.GRPC_NAME)
                self.assertFalse(any('secret' in v for v in pod['volumes']))

    def test_keycloak_uses_https_persistent_db_and_management_health(self):
        d = self.deploys['ceerat-keycloak']; c = d['spec']['template']['spec']['containers'][0]
        env = {e['name']: e.get('value') for e in c['env']}
        self.assertEqual(env['KC_HOSTNAME'], 'https://localhost:8443')
        self.assertEqual(env['KC_HTTP_ENABLED'], 'false')
        self.assertEqual(env['KC_DB'], 'postgres')
        self.assertEqual(c['args'][0], 'start')
        self.assertIn('--http-enabled=false', c['args'])
        self.assertEqual(c['readinessProbe']['httpGet']['scheme'], 'HTTPS')
        self.assertEqual(c['readinessProbe']['httpGet']['port'], 9000)
        self.assertEqual(c['readinessProbe']['httpGet']['path'], '/health/ready')
        self.assertIn('--import-realm', c['args'])
        self.assertIn('startupProbe', c)

    def test_local_rollout_does_not_require_two_replicas_or_surge_capacity(self):
        for d in self.deploys.values():
            self.assertEqual(d['spec']['replicas'], 1)
            self.assertEqual(d['spec']['strategy'], {'type': 'Recreate'})
        original = next(d for d in self.base if d['kind']=='Deployment' and d['metadata']['name']=='ceerat-customer-ui')
        self.assertEqual(original['spec']['replicas'], 2, 'must not mutate production/base input')

class PortForwardNamespaceTest(unittest.TestCase):
    def test_auth_forward_uses_backend_namespace(self):
        source = (ROOT/'k8-scripts/k8s-start.sh').read_text()
        start = source.index('start_port_forward() {')
        function = source[start:source.index('\n}\n', start)+3]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            kubectl = path/'kubectl'
            kubectl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$FORWARD_ARGS"\nsleep 30\n')
            kubectl.chmod(0o755)
            env = dict(os.environ, PATH=temp+':'+os.environ['PATH'], FORWARD_ARGS=str(path/'args'))
            script = function + '\nLOG_DIR="'+temp+'"\nPORT_FORWARD_PID_FILE="'+temp+'/pids"\n' + \
                     'start_port_forward auth ceerat-keycloak 8443:8443 https://auth.localhost:8443 ceerat-backend\n'
            pid = None
            try:
                subprocess.check_output(['bash','-c',script], env=env)
                pid = int((path/'pids').read_text().strip())
                for _ in range(50):
                    if (path/'args').exists():break
                    time.sleep(.1)
                self.assertEqual((path/'args').read_text().strip(), '-n ceerat-backend port-forward svc/ceerat-keycloak 8443:8443')
            finally:
                if pid:
                    try: os.killpg(pid, signal.SIGTERM)
                    except ProcessLookupError: pass

class DetachedForwardLifetimeTest(unittest.TestCase):
    def test_forward_survives_parent_shell_exit(self):
        source = (ROOT/'k8-scripts/k8s-start.sh').read_text()
        start = source.index('start_port_forward() {')
        function = source[start:source.index('\n}\n', start)+3]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp); kubectl = path/'kubectl'
            kubectl.write_text('#!/bin/sh\nsleep 30\n'); kubectl.chmod(0o755)
            env = dict(os.environ, PATH=temp+':'+os.environ['PATH'])
            script = function+'\nLOG_DIR="'+temp+'"\nPORT_FORWARD_PID_FILE="'+temp+'/pids"\nstart_port_forward auth ceerat-keycloak 8443:8443 https://auth.localhost:8443 ceerat-backend\n'
            pid = None
            try:
                subprocess.check_output(['bash','-c',script], env=env)
                pid = int((path/'pids').read_text().strip())
                self.assertEqual(os.getpgid(pid), pid, 'forward must have its own session/process group')
                os.kill(pid, 0)
            finally:
                if pid:
                    try: os.killpg(pid, signal.SIGTERM) if os.getpgid(pid)==pid else os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError: pass

if __name__ == '__main__': unittest.main()
