# Local HTTPS reverse proxy implementation plan

Goal: one local HTTPS entry point and a forwarding-only recovery command.
Spec: [local HTTPS reverse proxy](../specs/2026-10-27-local-https-reverse-proxy.md).
Architecture: local-only Nginx host routing; existing private gRPC TLS remains authoritative.
Stack: existing Go portals/Keycloak, Nginx, Python standard library, Kubernetes.

- [x] Add failing manifest tests for proxy-only exposure, correct callbacks,
      public CA/private key separation, verified Keycloak upstream and header/log policy.
- [x] Add proxy configuration/manifests to `k8-scripts/local_tls.py`, separate
      proxy certificate issuance, stable proxy Service discovery and exact realm callbacks.
- [x] Add idempotent local-only client reconciliation preserving unrelated client policy.
- [x] Test and implement detached supervised forwarding in `k8-scripts/forward.py`;
      wire Make targets and local startup to it without build/deploy dependencies.
- [x] Update read-only smoke verification and README for HTTPS hostnames, recovery,
      stop/status commands and boundaries.
- [x] Validate tests and actual Nginx config; deploy locally, reconcile existing
      clients, and verify TLS/callback/cookie/forward lifetime and reconnect behavior.
- [x] Request independent code review; resolve important findings before reporting completion.

Review focus: wrong host rejection; stale callback allowlists on existing realms;
OAuth state/cookies in logs; upstream certificate verification; stale PID or
unrelated port ownership; forwarding restart after pod replacement.
