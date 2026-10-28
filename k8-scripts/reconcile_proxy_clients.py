#!/usr/bin/env python3
"""Register exact local-proxy callbacks without replacing client security policy."""
import base64
import copy
import http.client
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.parse

ROOT=Path(__file__).resolve().parents[1]
CLIENTS={'ceerat-web-ui':'app','ceerat-customer-ui':'customer','ceerat-admin-ui':'admin'}

def google_credentials():
    explicit=os.environ.get('CEERAT_GOOGLE_CLIENT_FILE')
    files=[Path(explicit)] if explicit else list(ROOT.glob('client_secret_*.apps.googleusercontent.com.json'))
    if not files:return None
    if len(files)!=1:raise ValueError('Set CEERAT_GOOGLE_CLIENT_FILE to select one Google credential file')
    web=json.loads(files[0].read_text()).get('web',{})
    if not web.get('client_id') or not web.get('client_secret'):
        raise ValueError('Google credential file must contain web client_id and client_secret')
    return web

def update_google(provider,credentials):
    result=copy.deepcopy(provider)
    result.setdefault('config',{}).update(clientId=credentials['client_id'],clientSecret=credentials['client_secret'])
    return result

def update_client(client,host):
    if client.get('attributes',{}).get('pkce.code.challenge.method')!='S256':
        raise ValueError('Local browser client must already enforce PKCE S256')
    result=copy.deepcopy(client)
    origin='https://'+host+'.localhost:8443'
    result.update(redirectUris=[origin+'/oauth/callback'],webOrigins=[origin])
    return result

def main():
    context=subprocess.check_output(['kubectl','config','current-context']).decode().strip()
    if context not in ['colima','docker-desktop']:raise SystemExit('Client reconciliation is local-cluster only')
    command=['kubectl','--context',context]
    secret=json.loads(subprocess.check_output(command+['-n','ceerat-backend','get','secret','ceerat-keycloak-admin','-o','json']))['data']
    username=base64.b64decode(secret['username']).decode();password=base64.b64decode(secret['password']).decode()
    ca=ROOT/'.run/k8s-local/tls/ca.crt';tls=ssl.create_default_context(cafile=str(ca))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
    with tempfile.TemporaryFile() as log:
        process=subprocess.Popen(command+['-n','ceerat-backend','port-forward','--address','127.0.0.1','svc/ceerat-keycloak',str(port)+':8443'],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        def request(method,path,body=None,token=None,form=False):
            connection=http.client.HTTPSConnection('auth.localhost',8443,context=tls,timeout=10)
            # Connect through the temporary local-only tunnel; preserve verified SNI.
            connection._create_connection=lambda address,timeout=10,source_address=None:socket.create_connection(('127.0.0.1',port),timeout,source_address)
            headers={}
            if token:headers['Authorization']='Bearer '+token
            if body is not None:
                headers['Content-Type']='application/x-www-form-urlencoded' if form else 'application/json'
                body=urllib.parse.urlencode(body) if form else json.dumps(body)
            try:
                connection.request(method,path,body,headers);response=connection.getresponse();data=response.read()
                if response.status not in [200,204]:raise RuntimeError('Local Keycloak reconciliation returned HTTP '+str(response.status))
                return json.loads(data) if data else None
            finally:connection.close()
        try:
            for attempt in range(40):
                if process.poll() is not None:raise RuntimeError('Temporary Keycloak tunnel failed; no credentials were sent')
                try:
                    token=request('POST','/realms/master/protocol/openid-connect/token',{'grant_type':'password','client_id':'admin-cli','username':username,'password':password},form=True)['access_token']
                    break
                except (ConnectionError,OSError):
                    if attempt==39:raise
                    time.sleep(.25)
            realm=request('GET','/admin/realms/ceerat',token=token)
            realm.setdefault('attributes',{})['frontendUrl']='https://localhost:8443'
            request('PUT','/admin/realms/ceerat',realm,token)
            print('Reconciled canonical localhost HTTPS realm URL')
            for client_id,host in CLIENTS.items():
                clients=request('GET','/admin/realms/ceerat/clients?clientId='+urllib.parse.quote(client_id),token=token)
                matches=[c for c in clients if c['clientId']==client_id]
                if len(matches)!=1:raise RuntimeError('Expected one local client '+client_id)
                original=matches[0];updated=update_client(original,host)
                if updated!=original:
                    request('PUT','/admin/realms/ceerat/clients/'+original['id'],updated,token)
                print('Reconciled exact HTTPS callback for '+client_id)
            credentials=google_credentials()
            if credentials:
                path='/admin/realms/ceerat/identity-provider/instances/google'
                provider=request('GET',path,token=token)
                updated=update_google(provider,credentials)
                request('PUT',path,updated,token)
                verified=request('GET',path,token=token)
                if verified.get('config',{}).get('clientId')!=credentials['client_id']:
                    raise RuntimeError('Google client ID verification failed')
                print('Reconciled Google credentials from local file; provider policy preserved')
                callback='https://localhost:8443/realms/ceerat/broker/google/endpoint'
                if callback not in credentials.get('redirect_uris',[]):
                    print('Google credential download lacks the HTTPS callback; register '+callback+' in Google Cloud Console')
        finally:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()

if __name__=='__main__':
    try:main()
    except Exception as error:
        # Never emit HTTP bodies, tokens, credential dictionaries or URLs with queries.
        raise SystemExit('Client reconciliation failed: '+str(error))
