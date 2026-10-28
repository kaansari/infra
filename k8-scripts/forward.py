#!/usr/bin/env python3
"""Restore one supervised, loopback-only proxy tunnel; never build or deploy."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import ssl
import subprocess
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=Path(__file__).resolve()
STATE=ROOT/'.run/k8s-local'
RECORD=STATE/'forward.json'

def forward_command(context):
    if context not in ['colima','docker-desktop']:raise ValueError('Forwarding is limited to colima/docker-desktop')
    return ['kubectl','--context',context,'-n','ceerat-frontend','port-forward','--address','localhost','svc/ceerat-web-proxy','8443:8443']

def process_args(pid):
    try:return shlex.split(subprocess.check_output(['ps','-p',str(int(pid)),'-o','command='],stderr=subprocess.DEVNULL).decode().strip())
    except (subprocess.CalledProcessError,ValueError):return []

def owns_manager(pid):
    args=process_args(pid)
    return str(SCRIPT) in args and 'run' in args

def owns_child(pid,context):
    try:expected=forward_command(context)
    except ValueError:return False
    args=process_args(pid)
    return bool(args) and Path(args[0]).name=='kubectl' and args[1:]==expected[1:]

def stop_orphan(data):
    pid=data.get('child_pid')
    if pid and owns_child(pid,data.get('context')):
        try:os.kill(pid,signal.SIGTERM)
        except ProcessLookupError:pass

def legacy_owned(args):
    if not args or Path(args[0]).name!='kubectl' or 'port-forward' not in args:return False
    services={'svc/ceerat-keycloak':'8443:8443','svc/ceerat-customer-ui':'3005:3005','svc/ceerat-web-ui':'3000:3000','svc/ceerat-admin-ui':'3010:3010'}
    return any(service in args and mapping in args for service,mapping in services.items()) and '-n' in args and args[args.index('-n')+1] in ['ceerat-backend','ceerat-frontend']

def record():
    try:return json.loads(RECORD.read_text())
    except (OSError,ValueError):return {}

def save(data):
    temp=RECORD.with_suffix('.tmp');temp.write_text(json.dumps(data));os.chmod(str(temp),0o600);temp.replace(RECORD)

def urls():
    for host in ['customer','app','admin']:print('  https://'+host+'.localhost:8443')
    print('  https://localhost:8443 (authentication)')

def cleanup_legacy():
    path=ROOT/'k8-scripts/.run/k8s-port-forwards.pid'
    if not path.exists():return
    for text in path.read_text().splitlines():
        if text.isdigit() and legacy_owned(process_args(int(text))):
            try:os.kill(int(text),signal.SIGTERM)
            except ProcessLookupError:pass
    path.unlink()

def stop():
    cleanup_legacy()
    data=record();pid=data.get('pid')
    if not pid or not owns_manager(pid):
        stop_orphan(data)
        if RECORD.exists():RECORD.unlink()
        print('No supervisor running; any recorded owned orphan tunnel was stopped');return
    os.kill(pid,signal.SIGTERM)
    for _ in range(50):
        if not owns_manager(pid):break
        time.sleep(.1)
    else:raise RuntimeError('Proxy supervisor did not stop; no unrelated process was killed')
    print('Stopped the managed proxy tunnel')

def tunnel_healthy():
    try:
        context=ssl.create_default_context(cafile=str(STATE/'tls/ca.crt'))
        with socket.create_connection(('127.0.0.1',8443),timeout=2) as raw:
            with context.wrap_socket(raw,server_hostname='localhost'):
                return True
    except (OSError,ssl.SSLError):return False

def monitor_tunnel(child,stopping):
    failures=0
    while child.poll() is None and not stopping.wait(5):
        failures=0 if tunnel_healthy() else failures+1
        if failures>=3:
            print('Proxy TLS probe failed repeatedly; replacing stale tunnel',flush=True)
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
            return

def supervise(context):
    command=forward_command(context)
    lock=open(STATE/'forward.lock','a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:raise SystemExit('A proxy supervisor is already running')
    stopping=threading.Event()
    signal.signal(signal.SIGTERM,lambda *_:stopping.set())
    signal.signal(signal.SIGINT,lambda *_:stopping.set())
    child=None
    try:
        while not stopping.is_set():
            child=subprocess.Popen(command,stdin=subprocess.DEVNULL,start_new_session=True)
            save({'pid':os.getpid(),'child_pid':child.pid,'context':context})
            monitor_tunnel(child,stopping)
            if not stopping.is_set():
                print('Proxy tunnel ended; reconnecting in two seconds',flush=True)
                stopping.wait(2)
    finally:
        if child and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        if record().get('pid')==os.getpid():RECORD.unlink()
        lock.close()

def start(context):
    forward_command(context)
    subprocess.check_call(['kubectl','--context',context,'-n','ceerat-frontend','rollout','status','deploy/ceerat-web-proxy','--timeout=120s'])
    data=record()
    if data.get('pid') and owns_manager(data['pid']):
        if data.get('context')!=context:raise RuntimeError('A tunnel for another local context is already running; stop it first')
        print('Proxy supervisor is already running; it reconnects automatically');urls();return
    stop_orphan(data)
    cleanup_legacy()
    time.sleep(.25)
    for host in ['127.0.0.1','::1']:
        with socket.socket(socket.AF_INET6 if ':' in host else socket.AF_INET) as listener:
            try:listener.bind((host,8443))
            except OSError:raise RuntimeError('Port 8443 is occupied by an unowned listener; it was left unchanged')
    with open(STATE/'forward.log','ab',buffering=0) as log:
        manager=subprocess.Popen(['python3',str(SCRIPT),'run','--context',context],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    for _ in range(80):
        if manager.poll() is not None:raise RuntimeError('Proxy supervisor exited; inspect .run/k8s-local/forward.log')
        try:
            with socket.create_connection(('127.0.0.1',8443),timeout=.25):
                print('Proxy tunnel running; it will reconnect after pod replacement');urls();return
        except OSError:time.sleep(.25)
    raise RuntimeError('Proxy tunnel is not listening yet; supervisor is retrying; inspect .run/k8s-local/forward.log')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['start','run','stop','status','cleanup-legacy'],nargs='?',default='start')
    parser.add_argument('--context',default=os.environ.get('K8S_CONTEXT'))
    args=parser.parse_args()
    STATE.mkdir(parents=True,exist_ok=True);os.chmod(str(STATE),0o700)
    if args.action=='cleanup-legacy':cleanup_legacy();return
    if args.action=='stop':stop();return
    if args.action=='status':
        data=record()
        active=data.get('pid') and owns_manager(data['pid'])
        connected=data.get('child_pid') and owns_child(data['child_pid'],data.get('context'))
        print(('Supervisor running; tunnel '+('active' if connected else 'reconnecting')+' (context '+data['context']+')') if active else 'Not running')
        return
    context=args.context or subprocess.check_output(['kubectl','config','current-context']).decode().strip()
    if args.action=='run':supervise(context);return
    with open(STATE/'forward-start.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        start(context)

if __name__=='__main__':
    try:main()
    except (RuntimeError,ValueError,subprocess.CalledProcessError) as error:raise SystemExit(str(error))
