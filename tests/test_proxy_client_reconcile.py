import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('reconcile',ROOT/'k8-scripts/reconcile_proxy_clients.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ClientReconcileTest(unittest.TestCase):
    def test_google_credentials_preserve_broker_and_link_policy(self):
        original={'alias':'google','enabled':True,'storeToken':False,'firstBrokerLoginFlowAlias':'first broker login','config':{'clientId':'placeholder','clientSecret':'placeholder','defaultScope':'openid profile email','syncMode':'IMPORT'}}
        result=module.update_google(original,{'client_id':'test-id','client_secret':'test-secret'})
        self.assertEqual(result['config']['clientId'],'test-id')
        self.assertEqual(result['config']['clientSecret'],'test-secret')
        self.assertEqual(result['config']['defaultScope'],original['config']['defaultScope'])
        for key in ['enabled','storeToken','firstBrokerLoginFlowAlias']:
            self.assertEqual(result[key],original[key])
        self.assertEqual(original['config']['clientSecret'],'placeholder')
    def test_callbacks_are_exact_and_policy_is_preserved(self):
        original={'clientId':'ceerat-customer-ui','attributes':{'pkce.code.challenge.method':'S256'},'defaultClientScopes':['ceerat.preferences.read'],'protocolMappers':[{'name':'keep'}],'redirectUris':['http://localhost:3005/oauth/callback'],'webOrigins':['http://localhost:3005']}
        result=module.update_client(original,'customer')
        self.assertEqual(result['redirectUris'],['https://customer.localhost:8443/oauth/callback'])
        self.assertEqual(result['webOrigins'],['https://customer.localhost:8443'])
        for key in ['attributes','defaultClientScopes','protocolMappers']:
            self.assertEqual(result[key],original[key])
        self.assertEqual(original['redirectUris'],['http://localhost:3005/oauth/callback'])
        self.assertEqual(module.update_client(result,'customer'),result)
    def test_missing_pkce_is_not_silently_accepted(self):
        with self.assertRaises(ValueError):module.update_client({'clientId':'ceerat-customer-ui'},'customer')
if __name__=='__main__':unittest.main()
