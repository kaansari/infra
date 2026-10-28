"""Local-only reverse proxy resources, consumed by local_tls.py."""
from pathlib import Path
import hashlib

NAME = 'ceerat-web-proxy'
NAMESPACE = 'ceerat-frontend'
IMAGE = 'nginx:stable-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951'

def service():
    return {'apiVersion':'v1','kind':'Service','metadata':{'name':NAME,'namespace':NAMESPACE},
            'spec':{'selector':{'app.kubernetes.io/name':NAME},'ports':[{'name':'https','port':8443,'targetPort':'https'}]}}

def resources(root):
    labels={'app.kubernetes.io/name':NAME}
    pod={'securityContext':{'runAsNonRoot':True,'runAsUser':101,'runAsGroup':101,'fsGroup':101},
         'automountServiceAccountToken':False,
         'containers':[{'name':NAME,'image':IMAGE,'command':['nginx','-g','daemon off;'],
                        'ports':[{'name':'https','containerPort':8443},{'name':'health','containerPort':8080}],
                        'securityContext':{'readOnlyRootFilesystem':True,'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},
                        'volumeMounts':[{'name':'config','mountPath':'/etc/nginx/nginx.conf','subPath':'nginx.conf','readOnly':True},
                                        {'name':'tls','mountPath':'/etc/ceerat/tls','readOnly':True},
                                        {'name':'ca','mountPath':'/etc/ceerat/ca','readOnly':True},
                                        {'name':'tmp','mountPath':'/tmp'}],
                        'readinessProbe':{'httpGet':{'path':'/healthz','port':'health'},'periodSeconds':5},
                        'livenessProbe':{'httpGet':{'path':'/healthz','port':'health'},'periodSeconds':10},
                        'resources':{'requests':{'cpu':'25m','memory':'32Mi'},'limits':{'cpu':'500m','memory':'128Mi'}}}],
         'volumes':[{'name':'config','configMap':{'name':'ceerat-proxy-config'}},
                    {'name':'tls','secret':{'secretName':'ceerat-proxy-tls'}},
                    {'name':'ca','configMap':{'name':'ceerat-local-ca'}},{'name':'tmp','emptyDir':{}}]}
    return [service(),
            {'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'ceerat-proxy-config','namespace':NAMESPACE},
             'data':{'nginx.conf':(Path(root)/'k8s/local-proxy/nginx.conf').read_text()}},
            {'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':NAME,'namespace':NAMESPACE},
             'spec':{'replicas':1,'strategy':{'type':'Recreate'},'selector':{'matchLabels':labels},'template':{'metadata':{'labels':labels,'annotations':{'ceerat.local/proxy-config-sha256':hashlib.sha256((Path(root)/'k8s/local-proxy/nginx.conf').read_bytes()).hexdigest()}},'spec':pod}}}]
