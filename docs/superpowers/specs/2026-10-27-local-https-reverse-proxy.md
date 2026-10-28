# Local HTTPS reverse proxy

User request: replace separate customer-facing port forwards with one proxy for browser communication.

Use one local-only Nginx Deployment/Service on 8443. Host routing serves
`app.localhost`, `customer.localhost`, `admin.localhost`, and `localhost` (authentication).
Reuse the approved development CA; issue a proxy leaf containing those names.
The host reaches one loopback-only Kubernetes port-forward. No root CA rotation
or new trust-store change is needed.

Browser/OAuth traffic goes through this proxy. Portal OAuth backchannel calls
also resolve `localhost` to the proxy Service. The proxy verifies Keycloak's
upstream HTTPS certificate against the CA and service DNS name. Portal services
remain private HTTP behind the TLS termination point; private gRPC keeps its
existing direct TLS and service authorization. This is not a forward proxy for
arbitrary destinations, a replacement for service authorization, or production
ingress certification.

Alternatives: retaining four forwarded ports does not satisfy the single-entry
request. Installing a cluster-wide ingress controller is unnecessary for this
local scope. Subdomain routing preserves existing application paths and avoids
path-prefix rewrites. These are implementation defaults; the user was offered
an alternative preserving existing localhost ports.

Preserve Host and overwrite forwarding headers at the proxy; support upgrades
and bounded request/time limits. Reject unrecognized hosts, disable proxy access
logging of queries/cookies, and do not expose Keycloak management endpoints.

Portal callbacks become `https://<portal>.localhost:8443/oauth/callback`. Reconcile
these exact URLs and origins in the existing local Keycloak clients; do not rely
on realm import to update an existing realm and do not use wildcard callbacks.
Reconciliation must retain PKCE and existing scopes/permissions.

Add `make k8-forward` to restore only the shared port-forward, with a detached
supervisor that reconnects after a selected pod exits. Scope process ownership
and shutdown to recorded proxy processes; never kill unrelated listeners. Add
status/stop commands and integrate the same entry point into local startup.

Acceptance: rendered manifest/security tests; Nginx config validation; all four
HTTPS hosts; exact discovery issuer and OAuth redirect; Secure state cookies;
proxy verifies upstream TLS, private gRPC readiness stays healthy; a wrong host
is rejected; forwarding remains after the command exits and can be restored
without deployments or image builds. No credential-bearing output in evidence.

Google OAuth compatibility: authentication uses literal `localhost`, because Google
rejects the `auth.localhost` broker callback. The old host remains a proxy alias,
but the canonical issuer and Google callback use `https://localhost:8443`.
