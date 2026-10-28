import importlib.util
import json
import hashlib
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('local_tls',ROOT/'k8-scripts/local_tls.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class ReverseProxyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text=subprocess.check_output(['kubectl','kustomize',str(ROOT/'k8s')])
        cls.base=json.loads(subprocess.check_output(['ruby','-ryaml','-rjson','-e','print JSON.generate(YAML.load_stream(STDIN.read))'],input=text))

    def test_proxy_has_one_https_service_and_separate_private_key(self):
        docs=module.configure(self.base,'10.43.0.99','ceerat/services:dev','ceerat/apps:dev')
        proxy=next(d for d in docs if d['kind']=='Deployment' and d['metadata']['name']=='ceerat-web-proxy')
        pod=proxy['spec']['template']['spec'];c=pod['containers'][0]
        config=(ROOT/'k8s/local-proxy/nginx.conf').read_bytes()
        self.assertEqual(proxy['spec']['template']['metadata']['annotations']['ceerat.local/proxy-config-sha256'],hashlib.sha256(config).hexdigest())
        self.assertTrue(pod['securityContext']['runAsNonRoot'])
        self.assertEqual(pod['securityContext']['fsGroup'],101)
        self.assertTrue(c['securityContext']['readOnlyRootFilesystem'])
        self.assertTrue(any(v.get('secret',{}).get('secretName')=='ceerat-proxy-tls' for v in pod['volumes']))
        svc=next(d for d in docs if d['kind']=='Service' and d['metadata']['name']=='ceerat-web-proxy')
        self.assertEqual([(p['port'],p['targetPort']) for p in svc['spec']['ports']],[(8443,'https')])

    def test_portal_callbacks_are_exact_https_urls_and_use_proxy_for_issuer(self):
        docs=module.configure(self.base,'10.43.0.99','ceerat/services:dev','ceerat/apps:dev')
        for name,host,key in [('ceerat-web-ui','app','WEB'),('ceerat-customer-ui','customer','CUSTOMER'),('ceerat-admin-ui','admin','ADMIN')]:
            d=next(d for d in docs if d['kind']=='Deployment' and d['metadata']['name']==name)
            pod=d['spec']['template']['spec'];env={e['name']:e.get('value') for e in pod['containers'][0]['env']}
            self.assertEqual(env['CEERAT_'+key+'_OAUTH_REDIRECT_URL'],'https://'+host+'.localhost:8443/oauth/callback')
            self.assertEqual(pod['hostAliases'],[{'ip':'10.43.0.99','hostnames':['auth.localhost', 'localhost']}])

    def test_proxy_validates_keycloak_and_does_not_log_oauth_queries(self):
        text=(ROOT/'k8s/local-proxy/nginx.conf').read_text()
        for hostname in ['auth','customer','app','admin']:
            self.assertIn(('server_name localhost auth.localhost;' if hostname=='auth' else 'server_name '+hostname+'.localhost;'),text)
        self.assertIn('proxy_ssl_verify on;',text)
        self.assertIn('proxy_ssl_name ceerat-keycloak.ceerat-backend.svc.cluster.local;',text)
        self.assertIn('proxy_set_header Host $http_host;',text)
        self.assertIn('proxy_set_header X-Forwarded-Proto https;',text)
        self.assertIn('access_log off;',text)
        self.assertIn('error_log /dev/null;',text)
        self.assertIn('return 421;',text)

if __name__=='__main__':unittest.main()
