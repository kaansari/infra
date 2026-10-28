#!/usr/bin/env python3
"""Read-only local TLS smoke checks. Never print OAuth state, cookies or tokens."""
import json
from pathlib import Path
import ssl
import socket
import subprocess
import urllib.request

root = Path(__file__).resolve().parents[1]
ca = root / '.run/k8s-local/tls/ca.crt'
context = ssl.create_default_context(cafile=str(ca))
# Chromium/curl resolve *.localhost to loopback; Python's macOS system resolver
# does not. Mirror that local-only lookup while retaining the real TLS SNI/name.
system_lookup = socket.getaddrinfo
def localhost_lookup(host, *args, **kwargs):
    return system_lookup('127.0.0.1' if host in ['auth.localhost', 'customer.localhost', 'app.localhost', 'admin.localhost'] else host, *args, **kwargs)
socket.getaddrinfo = localhost_lookup
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
for host in ['app', 'customer', 'admin']:
    with opener.open('https://'+host+'.localhost:8443/readyz', timeout=10) as response:
        if response.status != 200:
            raise SystemExit('FAIL: portal readiness for '+host)
        print('PASS: HTTPS proxy route '+host+', including verified backend gRPC connection')
issuer = 'https://localhost:8443/realms/ceerat'
with opener.open(issuer + '/.well-known/openid-configuration', timeout=10) as response:
    discovery = json.load(response)
    if discovery['issuer'] != issuer or not discovery['authorization_endpoint'].startswith(issuer + '/'):
        raise SystemExit('FAIL: canonical issuer mismatch')
    print('PASS: Keycloak HTTPS chain, hostname and canonical discovery issuer')
with opener.open('https://customer.localhost:8443/oauth/login', timeout=10) as response:
    body = response.read().decode()
    if response.status != 200 or not response.url.startswith(issuer + '/') or 'kc-form-login' not in body:
        raise SystemExit('FAIL: customer login did not reach the HTTPS Keycloak login form')
    print('PASS: customer OAuth redirect reaches the HTTPS Keycloak login form')
negative = subprocess.run(['openssl', 'verify', '-CAfile', str(ca), '-verify_hostname',
                           'incorrect.localhost', str(ca.parent / 'proxy.crt')],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if negative.returncode == 0:
    raise SystemExit('FAIL: incorrect certificate hostname was accepted')
print('PASS: incorrect TLS hostname is rejected')
import urllib.error
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None
initial=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context),NoRedirect())
try:
    initial.open('https://customer.localhost:8443/oauth/login',timeout=10)
    raise SystemExit('FAIL: expected OAuth redirect')
except urllib.error.HTTPError as response:
    cookies=response.headers.get_all('Set-Cookie') or []
    if response.code not in [302,303] or not cookies or not all('secure' in value.lower() for value in cookies):
        raise SystemExit('FAIL: OAuth state cookies must be Secure')
print('PASS: customer OAuth state cookies are Secure')
for path,host,expected in [('/', 'unexpected.localhost',421),('/admin/','auth.localhost:8443',404)]:
    request=urllib.request.Request('https://localhost:8443'+path,headers={'Host':host})
    try:
        opener.open(request,timeout=10)
        raise SystemExit('FAIL: forbidden proxy route accepted')
    except urllib.error.HTTPError as response:
        if response.code!=expected:raise SystemExit('FAIL: unexpected proxy rejection status')
print('PASS: unknown hosts and Keycloak administration are not publicly routed')
print('No credentials submitted; authenticated callback/account operations are outside this smoke check.')
