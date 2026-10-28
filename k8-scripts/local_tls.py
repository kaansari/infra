#!/usr/bin/env python3
"""Generate the local-only TLS deployment; private material stays under .run/."""
import argparse
import base64
import copy
import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import proxy_resources

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.run/k8s-local'
ISSUER = 'https://localhost:8443/realms/ceerat'
GRPC_NAME = 'ceerat-user-service.ceerat-backend.svc.cluster.local'


def envset(container, values):
    env = {e['name']: e for e in container.get('env', [])}
    for key, value in values.items():
        env[key] = {'name': key, 'value': value} if isinstance(value, str) else {'name': key, 'valueFrom': value}
    container['env'] = list(env.values())


def db_env():
    return {key: {'configMapKeyRef': {'name': 'ceerat-db-config', 'key': key}}
            for key in ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_NAME']}


def configure(base, keycloak_ip, service_image, apps_image):
    docs = copy.deepcopy(base)
    for d in docs:
        kind, name = d['kind'], d['metadata']['name']
        if kind == 'ConfigMap' and name == 'ceerat-platform-config':
            d['data'].update(CEERAT_OAUTH_ISSUER=ISSUER, CEERAT_OAUTH_AUDIENCE='ceerat-api', CEERAT_ENV='local')
        if kind == 'Service' and name == 'ceerat-keycloak':
            d['spec']['ports'] = [{'name': 'https', 'port': 8443, 'targetPort': 'https'}]
        if kind != 'Deployment':
            continue
        d['spec']['replicas'] = 1
        d['spec']['strategy'] = {'type': 'Recreate'}
        pod = d['spec']['template']['spec']
        c = pod['containers'][0]
        if name != 'ceerat-keycloak':
            c['image'] = service_image if name == 'ceerat-user-service' else apps_image
        pod['hostAliases'] = [{'ip': keycloak_ip, 'hostnames': ['auth.localhost', 'localhost']}]
        pod.setdefault('volumes', []).append({'name': 'local-ca', 'configMap': {'name': 'ceerat-local-ca'}})
        c.setdefault('volumeMounts', []).append({'name': 'local-ca', 'mountPath': '/etc/ceerat/ca', 'readOnly': True})
        envset(c, {'SSL_CERT_FILE': '/etc/ceerat/ca/ca.crt', 'CEERAT_OAUTH_ISSUER': ISSUER, 'CEERAT_OAUTH_AUDIENCE': 'ceerat-api'})
        if name == 'ceerat-keycloak':
            c['args'] = ['start', '--import-realm', '--http-enabled=false']
            c['ports'] = [{'name': 'https', 'containerPort': 8443}, {'name': 'management', 'containerPort': 9000}]
            settings = {'KC_HTTP_ENABLED': 'false', 'KC_HTTPS_PORT': '8443', 'KC_HOSTNAME': 'https://localhost:8443',
                        'KC_HEALTH_ENABLED': 'true', 'KC_HTTPS_CERTIFICATE_FILE': '/etc/ceerat/tls/tls.crt',
                        'KC_HTTPS_CERTIFICATE_KEY_FILE': '/etc/ceerat/tls/tls.key', 'KC_DB': 'postgres',
                        'KC_DB_URL': 'jdbc:postgresql://postgres.ceerat-data.svc.cluster.local:5432/ceerat',
                        'KC_DB_SCHEMA': 'keycloak', 'KC_DB_USERNAME': 'ceerat',
                        'KC_DB_PASSWORD': {'secretKeyRef': {'name': 'ceerat-db-credentials', 'key': 'DB_PASSWORD'}}}
            envset(c, settings)
            for probe, path in [('readinessProbe','/health/ready'),('livenessProbe','/health/live')]:
                c[probe] = {'httpGet': {'path': path, 'port': 9000, 'scheme': 'HTTPS'}, 'periodSeconds': 10, 'timeoutSeconds': 5, 'failureThreshold': 6}
            c['startupProbe'] = {'httpGet': {'path': '/health/ready', 'port': 9000, 'scheme': 'HTTPS'}, 'periodSeconds': 5, 'failureThreshold': 90, 'timeoutSeconds': 5}
            c['resources'] = {'requests': {'cpu': '200m', 'memory': '512Mi'}, 'limits': {'cpu': '1500m', 'memory': '1Gi'}}
            pod['volumes'] += [{'name': 'server-tls', 'secret': {'secretName': 'ceerat-keycloak-tls'}},
                               {'name': 'realm-import', 'secret': {'secretName': 'ceerat-local-realm'}}]
            c['volumeMounts'] += [{'name': 'server-tls', 'mountPath': '/etc/ceerat/tls', 'readOnly': True},
                                  {'name': 'realm-import', 'mountPath': '/opt/keycloak/data/import', 'readOnly': True}]
            init = {'name': 'keycloak-schema', 'image': 'postgres:16-alpine', 'command': ['sh', '-ec',
                    'export PGPASSWORD="$DB_PASSWORD"; until pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME"; do sleep 2; done; psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS keycloak"']}
            envset(init, dict(db_env(), DB_PASSWORD={'secretKeyRef': {'name': 'ceerat-db-credentials', 'key': 'DB_PASSWORD'}}))
            pod['initContainers'] = [init]
        else:
            prefix = 'CEERAT_USER_SERVICE' if name in ['ceerat-agent-gateway', 'ceerat-agent-service'] else 'CEERAT_GRPC'
            envset(c, {prefix+'_TLS_MODE': 'tls', prefix+'_TLS_CA_FILE': '/etc/ceerat/ca/ca.crt', prefix+'_TLS_SERVER_NAME': GRPC_NAME})
            if name == 'ceerat-user-service':
                envset(c, {'CEERAT_GRPC_TLS_CERT_FILE': '/etc/ceerat/tls/tls.crt', 'CEERAT_GRPC_TLS_KEY_FILE': '/etc/ceerat/tls/tls.key'})
                pod['volumes'].append({'name': 'server-tls', 'secret': {'secretName': 'ceerat-grpc-tls'}})
                c['volumeMounts'].append({'name': 'server-tls', 'mountPath': '/etc/ceerat/tls', 'readOnly': True})
            if name == 'ceerat-user-service':
                init = {'name': 'database-migrations', 'image': service_image,
                        'command': ['bash', '-ec', 'until pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME"; do sleep 2; done; bash /app/scripts/db-bootstrap-if-empty.sh; bash /app/scripts/db-migrate.sh; bash /app/scripts/db-preflight.sh']}
                envset(init, dict(db_env(), DB_PASSWORD={'secretKeyRef': {'name': 'ceerat-db-credentials', 'key': 'DB_PASSWORD'}}))
                pod['initContainers'] = [init]
            if name == 'ceerat-agent-gateway':
                envset(c, {'CEERAT_OAUTH_JWKS_URL': ISSUER+'/protocol/openid-connect/certs', 'CEERAT_AUTHORIZATION_SERVER': ISSUER})
            if name in ['ceerat-customer-ui', 'ceerat-admin-ui', 'ceerat-web-ui']:
                host, key = {'ceerat-customer-ui': ('customer', 'CUSTOMER'), 'ceerat-web-ui': ('app', 'WEB'), 'ceerat-admin-ui': ('admin', 'ADMIN')}[name]
                envset(c, {'CEERAT_' + key + '_OAUTH_REDIRECT_URL': 'https://' + host + '.localhost:8443/oauth/callback'})
                c['readinessProbe'] = {'httpGet': {'path': '/readyz', 'port': 'http'}, 'periodSeconds': 5, 'timeoutSeconds': 5}
                c['livenessProbe'] = {'httpGet': {'path': '/healthz', 'port': 'http'}, 'periodSeconds': 10, 'timeoutSeconds': 5, 'failureThreshold': 6}
    docs.extend(proxy_resources.resources(ROOT))
    return docs


def run(args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def certs():
    STATE.mkdir(parents=True, exist_ok=True); os.chmod(str(STATE), 0o700)
    tls = STATE / 'tls'; tls.mkdir(exist_ok=True); os.chmod(str(tls), 0o700)
    ca = tls/'ca.crt'
    if not ca.exists():
        run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-days','365','-subj','/CN=CEERAT local Kubernetes CA',
             '-keyout',str(tls/'ca.key'),'-out',str(ca),'-addext','basicConstraints=critical,CA:TRUE',
             '-addext','keyUsage=critical,keyCertSign,cRLSign'], stderr=subprocess.DEVNULL)
    if subprocess.call(['openssl','x509','-checkend','86400','-noout','-in',str(ca)], stdout=subprocess.DEVNULL) != 0:
        raise SystemExit('Local CA is expiring; rotate it explicitly and approve browser trust before restarting')
    for name, names in [('keycloak', ['localhost','auth.localhost','ceerat-keycloak.ceerat-backend.svc.cluster.local']), ('grpc',[GRPC_NAME]), ('proxy',['localhost','auth.localhost','app.localhost','customer.localhost','admin.localhost'])]:
        if (tls/(name+'.crt')).exists() and subprocess.call(['openssl','x509','-checkend','604800','-noout','-in',str(tls/(name+'.crt'))], stdout=subprocess.DEVNULL) == 0 and all(subprocess.call(['openssl','verify','-CAfile',str(ca),'-verify_hostname',hostname,str(tls/(name+'.crt'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)==0 for hostname in names):
            continue
        ext=tls/(name+'.ext')
        ext.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName='+','.join('DNS:'+n for n in names)+'\n')
        run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN='+names[0],'-keyout',str(tls/(name+'.key')),'-out',str(tls/(name+'.csr'))],stderr=subprocess.DEVNULL)
        run(['openssl','x509','-req','-in',str(tls/(name+'.csr')),'-CA',str(ca),'-CAkey',str(tls/'ca.key'),'-CAcreateserial','-days','90','-extfile',str(ext),'-out',str(tls/(name+'.crt'))],stderr=subprocess.DEVNULL)
    for key in tls.glob('*.key'): os.chmod(str(key),0o600)
    for name in ['keycloak','grpc','proxy']:
        run(['openssl','verify','-CAfile',str(ca),'-verify_hostname',GRPC_NAME if name=='grpc' else 'auth.localhost',str(tls/(name+'.crt'))])
    return tls


def resource(kind, name, ns, data):
    return {'apiVersion':'v1','kind':kind,'metadata':{'name':name,'namespace':ns},'data':data}


def apply(kubectl, docs):
    run([kubectl,'apply','-f','-'],input=json.dumps({'apiVersion':'v1','kind':'List','items':docs}).encode())


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--kubectl',default='kubectl'); parser.add_argument('--registry',default='ceerat'); parser.add_argument('--tag',default='dev')
    args=parser.parse_args(); k=args.kubectl
    context=run([k,'config','current-context']).decode().strip()
    if context not in ['colima','docker-desktop']: raise SystemExit('Local TLS setup requires colima or docker-desktop context')
    tls=certs()
    yaml=run([k,'kustomize',str(ROOT/'k8s')])
    base=json.loads(run(['ruby','-ryaml','-rjson','-e','print JSON.generate(YAML.load_stream(STDIN.read))'],input=yaml))
    # Establish the stable service IP before configuring per-pod local hostname resolution.
    preliminary=[d for d in base if d['kind']=='Namespace'] + [proxy_resources.service()]
    apply(k,preliminary)
    ip=run([k,'-n','ceerat-frontend','get','svc','ceerat-web-proxy','-o','jsonpath={.spec.clusterIP}']).decode()
    docs=configure(base,ip,args.registry+'/ceerat-services-repo:'+args.tag,args.registry+'/ceerat-apps-repo:'+args.tag)
    digest = hashlib.sha256(b''.join((tls / name).read_bytes() for name in ['ca.crt', 'keycloak.crt', 'grpc.crt', 'proxy.crt'])).hexdigest()
    for d in docs:
        if d['kind'] == 'Deployment':
            d['spec']['template']['metadata'].setdefault('annotations', {})['ceerat.local/tls-bundle-sha256'] = digest
    for ns in ['ceerat-backend','ceerat-frontend']:
        docs.append(resource('ConfigMap','ceerat-local-ca',ns,{'ca.crt':(tls/'ca.crt').read_text()}))
    for name in ['keycloak','grpc','proxy']:
        secret=resource('Secret','ceerat-'+name+'-tls','ceerat-frontend' if name=='proxy' else 'ceerat-backend',
                        {'tls.crt':base64.b64encode((tls/(name+'.crt')).read_bytes()).decode(),
                         'tls.key':base64.b64encode((tls/(name+'.key')).read_bytes()).decode()})
        secret['type']='kubernetes.io/tls'; docs.append(secret)
    realm=json.loads((ROOT/'dev/keycloak/ceerat-realm.json').read_text())
    realm.setdefault('attributes',{})['frontendUrl']='https://localhost:8443'
    for client in realm['clients']:
        host = {'ceerat-web-ui':'app','ceerat-customer-ui':'customer','ceerat-admin-ui':'admin'}.get(client['clientId'])
        if host:
            client['redirectUris'] = ['https://' + host + '.localhost:8443/oauth/callback']
            client['webOrigins'] = ['https://' + host + '.localhost:8443']
        for mapper in client.get('protocolMappers',[]):
            if mapper.get('name')=='CEERAT MCP audience': mapper['config']['included.custom.audience']='http://localhost:8090/mcp'
    docs.append(resource('Secret','ceerat-local-realm','ceerat-backend',{'ceerat-realm.json':base64.b64encode(json.dumps(realm).encode()).decode()}))
    output=STATE/'resources.json'; output.write_text(json.dumps({'apiVersion':'v1','kind':'List','items':docs})); os.chmod(str(output),0o600)
    print('Local TLS manifests prepared at '+str(output)+'; CA '+str(tls/'ca.crt'))

if __name__=='__main__': main()
