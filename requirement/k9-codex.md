# Codex Prompt: K8s Ingress and Visibility Upgrade

Read `infra/requirement/k3.md` and implement the best local Kubernetes visibility/access path for the existing Ceerat K8s setup.

## Goal

Improve the local Kubernetes developer experience so I am no longer blind to:

- app logs
- pod health
- deployment status
- ingress/routing
- service exposure
- database access
- local browser URLs

Do not replace the current `infra/k8s` structure. Extend it cleanly.

## Current Context

The repo already has:

- Kubernetes manifests under `infra/k8s`
- `k8s-start.sh`, `k8s-stop.sh`, `k8s-status.sh`
- `make k8-build`, `make k8-deploy`, `make k8-render`
- frontend services:
  - `ceerat-web-ui` on port `3000`
  - `ceerat-customer-ui` on port `3005`
  - `ceerat-admin-ui` on port `3010`
- backend services:
  - `ceerat-user-service`
  - `ceerat-agent-service`
- data services:
  - Postgres
  - Typesense

The current ingress manifest uses a `gce` annotation, which is not ideal for local K3s/Colima. Prefer a local-friendly ingress strategy.

## Important Clarification

If the requirement says “install K3,” verify whether the local cluster is already K3s. Colima Kubernetes commonly runs K3s. Do not install a second cluster if the current one is already K3s.

For visibility, prefer:

- `k9s` for live Kubernetes management
- `stern` for streaming logs across pods
- improved `k8s-status.sh`
- local ingress through Traefik if available, otherwise Nginx ingress
- clear README instructions

## Implementation Tasks

1. Inspect the current cluster assumptions in scripts and manifests.

2. Update ingress support:
   - Detect or document whether `traefik` ingress class exists.
   - If Traefik exists, support `ingressClassName: traefik`.
   - If no ingress class exists, document/install Nginx ingress as the fallback.
   - Remove or avoid local use of `kubernetes.io/ingress.class: gce`.
   - Keep app hostnames:
     - `app.ceerat.local`
     - `customer.ceerat.local`
     - `admin.ceerat.local`

3. Add local visibility helpers:
   - Add a script such as `k8s-logs.sh` or extend existing scripts to make common logs easy:
     - all Ceerat pods
     - backend logs
     - frontend logs
     - user-service logs
     - customer-ui logs
     - admin-ui logs
     - web-ui logs
   - Use `kubectl logs` as the baseline.
   - If `stern` is installed, optionally use it for better multi-pod logs.
   - Do not require `stern` for basic functionality.

4. Improve `k8s-status.sh`:
   - show current context
   - show ingress classes
   - show nodes
   - show Ceerat pods grouped by namespace
   - show services
   - show ingress
   - show recent Ceerat events
   - show quick URLs/port-forward hints

5. Add optional K9s documentation:
   - Install:
     - `brew install k9s`
   - Run:
     - `k9s`
   - Explain that K9s is the recommended live dashboard for local K8s.

6. Update `README.md`:
   - Explain ClusterIP vs Ingress vs port-forward.
   - Explain when to use `./k8s-start.sh --local`.
   - Explain how to test ingress hostnames.
   - Explain `/etc/hosts` entries if needed.
   - Add log visibility commands.
   - Add K9s and Stern recommendations.
   - Add troubleshooting for ingress class missing or `EXTERNAL-IP` pending.

7. Keep current deployment image rules:
   - one `ceerat-apps-repo` image
   - one `ceerat-services-repo` image
   - Postgres as separate official image
   - do not include `atscrawler` in K8s

## Acceptance Criteria

- `make k8-render` still works.
- Existing `./k8s-start.sh --local` still works.
- `./k8s-status.sh` gives useful visibility without extra tools.
- There is a clear command to stream logs for each major app/service.
- README explains how to access:
  - web UI
  - customer UI
  - admin UI
  - Postgres from a DB plugin
  - logs and events
- Ingress guidance works for local K3s/Colima using Traefik when available.
- No backend/database service is exposed publicly by default.
- No direct DB access from apps/agents is introduced.

## Verification Commands

Run as much as possible:

```bash
bash -n k8s-start.sh
bash -n k8s-stop.sh
bash -n k8s-status.sh
test -f k8s-logs.sh && bash -n k8s-logs.sh

make k8-render K8S_REGISTRY=ceerat IMAGE_TAG=dev

kubectl get ingressclass
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A