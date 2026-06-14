# Infra: start/stop stack

This folder contains helper scripts to start a local development stack for Ceerat.

Files:
- `start-stack.sh` — waits for a Postgres instance (local by default) and launches services (user service, agent, web UI) using `go run` in the background. Logs are written to `logs/` and PIDs are stored in `pids`.
- `stop-stack.sh` — stops background processes recorded in `pids` and removes the Postgres Docker container if one was started by the script.

Usage:

Make the scripts executable:

```bash
chmod +x infra/start-stack.sh infra/stop-stack.sh
```

Start the stack (defaults can be overridden via environment variables). By default the script expects a local Postgres installation and will not start Docker.

To use the local DB (default):

```bash
infra/start-stack.sh
```

To explicitly start a Postgres Docker container instead set `USE_LOCAL_DB=false`:

```bash
USE_LOCAL_DB=false infra/start-stack.sh
```

Or customize env vars inline:

```bash
ROOT_DIR="/path/to/your/ceerat-workspace" DB_PASSWORD=secret infra/start-stack.sh
```

Stop the stack:

```bash
infra/stop-stack.sh
```

Notes:
- The scripts assume the workspace layout where `services-repo`, `apps-repo`, and `contracts-repo` are in the same parent directory.
- The scripts start processes with `go run .` — if you prefer built binaries, replace the `go run` lines in `start-stack.sh` with `go build` + `./binary` runs.
- You can edit `ROOT_DIR` environment variable if your repositories are in a different path.

## Kubernetes

The Kubernetes manifests live in `infra/k8s`. The deploy flow builds two Ceerat images:

- `ceerat-apps-repo` for the app and agent binaries.
- `ceerat-services-repo` for the user service.

Postgres runs as an in-cluster StatefulSet using `postgres:16-alpine`.

### Start a Local Cluster

Colima is the local cluster path for this workspace:

```bash
./k8s-start.sh
```

Start the cluster, deploy Ceerat, and open local browser ports:

```bash
./k8s-start.sh --local
```

This starts these background port-forwards:

```text
web:      http://localhost:3000
customer: http://localhost:3005
admin:    http://localhost:3010
```

Port-forward logs are written to `logs/k8s-port-forward-*.log`, and PIDs are stored under `.run/`.

The local seed admin account is:

```text
email:    admin@ceerat.local
password: admin123
```

If you use Docker Desktop instead, enable Kubernetes in Docker Desktop settings, then switch to its context:

```bash
K8S_DRIVER=docker-desktop ./k8s-start.sh
```

You can also use Make aliases:

```bash
make start-k8
make status-k8
make stop-k8
```

### Test the Manifests

Render the manifests without applying them:

```bash
make k8-render K8S_REGISTRY=ceerat IMAGE_TAG=dev
```

Build the two local images:

```bash
make k8-build K8S_REGISTRY=ceerat IMAGE_TAG=dev
```

### Deploy

For a local cluster using locally built images:

```bash
make k8-deploy K8S_REGISTRY=ceerat IMAGE_TAG=dev
```

For a remote registry, set `PROJECT_ID` and `REGION`, and push before apply:

```bash
make k8-deploy PROJECT_ID=my-gcp-project REGION=us-central1 IMAGE_TAG=dev PUSH=true
```

### Check the Deployment

```bash
./k8s-status.sh
kubectl get pods -A
kubectl get svc -A
```

`./k8s-status.sh` prints the current context, ingress classes, nodes, Ceerat pods grouped by namespace, services, ingress resources, recent Ceerat events, and quick local access hints.

### Live Visibility

Recommended local dashboard:

```bash
brew install k9s
k9s
```

K9s is the fastest way to inspect pods, deployments, restarts, events, logs, and shells inside the local cluster.

Stream Ceerat logs with the repo helper:

```bash
./k8s-logs.sh backend
./k8s-logs.sh frontend
./k8s-logs.sh user-service
./k8s-logs.sh customer-ui
./k8s-logs.sh admin-ui
./k8s-logs.sh web-ui
./k8s-logs.sh all --no-follow
```

`k8s-logs.sh` uses `kubectl logs` by default. If `stern` is installed, namespace and all-pod views use it for better multi-pod streaming:

```bash
brew install stern
stern -n ceerat-backend ceerat-user-service
stern -n ceerat-frontend ceerat-customer-ui
```

Useful raw Kubernetes checks:

```bash
kubectl -n ceerat-frontend logs deploy/ceerat-web-ui --tail=50
kubectl -n ceerat-frontend logs deploy/ceerat-customer-ui --tail=50
kubectl -n ceerat-frontend logs deploy/ceerat-admin-ui --tail=50
kubectl -n ceerat-backend logs deploy/ceerat-user-service --tail=50
kubectl -n ceerat-backend get events --sort-by=.metadata.creationTimestamp
kubectl -n ceerat-frontend get events --sort-by=.metadata.creationTimestamp
```

### Local Browser Access

The Ceerat services are `ClusterIP` services, so they are only reachable inside Kubernetes until you port-forward them. For local development, prefer port-forwarding over ingress. Ingress, public hostnames, load balancers, and HTTPS belong to production or production-like environments.

If `http://localhost:3000` shows nothing, start a port-forward first.

Use the quick local mode:

```bash
./k8s-start.sh --local
```

Or port-forward each UI manually:

```bash
kubectl -n ceerat-frontend port-forward svc/ceerat-web-ui 3000:3000
```

Then open:

```text
http://localhost:3000
```

Customer UI:

```bash
kubectl -n ceerat-frontend port-forward svc/ceerat-customer-ui 3005:3005
```

```text
http://localhost:3005
```

Admin UI:

```bash
kubectl -n ceerat-frontend port-forward svc/ceerat-admin-ui 3010:3010
```

```text
http://localhost:3010
```

If a local port is already in use, change only the left side of the mapping:

```bash
kubectl -n ceerat-frontend port-forward svc/ceerat-web-ui 3001:3000
```

Then open `http://localhost:3001`.

If the customer UI shows `The application is currently offline`, first confirm the port-forward is running:

```bash
curl http://localhost:3005/health
sed -n '1,40p' logs/k8s-port-forward-customer.log
```

If `curl` cannot connect, restart the local port-forwards:

```bash
SKIP_BUILD=true SKIP_DEPLOY=true ./k8s-start.sh --local
```

If `curl` works but the browser still shows the offline page, clear the cached service worker page with a hard refresh or by opening the site in a private/incognito window. In Chrome, you can also use DevTools > Application > Service workers > Unregister for `localhost:3005`, then reload.

Port-forward the user service gRPC endpoint:

```bash
kubectl -n ceerat-backend port-forward svc/ceerat-user-service 50051:50051
```

### Production Ingress

Ingress is the production path for browser traffic. Use it when you are deploying Ceerat behind a real ingress controller, load balancer, DNS, and HTTPS certificate. Do not use ingress as the primary local debugging tool; use `./k8s-start.sh --local`, `k9s`, and `./k8s-logs.sh` for local work.

The ingress manifest uses:

```yaml
ingressClassName: traefik
```

This is suitable when the production or production-like cluster uses Traefik. If the target cluster uses Nginx ingress, change the class to `nginx` in the production overlay or patch the deployed ingress.

Check what your cluster has:

```bash
kubectl get ingressclass
kubectl get ingress -A
```

Production hostnames should map through DNS to the ingress/load balancer address. Example hostnames:

```text
https://app.ceerat.com
https://customer.ceerat.com
https://admin.ceerat.com
```

For a production-like local smoke test only, you may map local hostnames in `/etc/hosts` to the ingress address:

```text
127.0.0.1 app.ceerat.local
127.0.0.1 customer.ceerat.local
127.0.0.1 admin.ceerat.local
```

If the production cluster does not have an ingress controller, install one through the platform's normal infrastructure process. Nginx ingress is a common fallback:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Then either change the manifest to `ingressClassName: nginx` or patch it locally:

```bash
kubectl -n ceerat-frontend patch ingress ceerat-web --type merge -p '{"spec":{"ingressClassName":"nginx"}}'
```

If the ingress controller service shows `EXTERNAL-IP` as `pending`, the cluster does not have a load balancer implementation. In production, fix this through the cloud load balancer or platform networking layer. In local development, use `./k8s-start.sh --local` instead.

Backend and data services should stay internal:

```text
postgres
typesense
ceerat-user-service
ceerat-agent-service
```

Do not expose them publicly by default.

### Database Access

Verify seeded database rows:

```bash
kubectl -n ceerat-data exec postgres-0 -- env PGPASSWORD=replace-me \
  psql -U ceerat -d ceerat \
  -c "SELECT email, role, status FROM users ORDER BY email;" \
  -c "SELECT count(*) AS services FROM services;"
```

Connect to the Kubernetes Postgres database from a VS Code database plugin:

```bash
kubectl -n ceerat-data port-forward svc/postgres 55434:5432
```

Use these connection settings:

```text
Host:     localhost
Port:     55434
Database: ceerat
User:     ceerat
Password: replace-me
SSL:      disable/off
```

The Kubernetes service IP is not reachable from VS Code directly because `postgres` is a `ClusterIP` service. Keep the port-forward terminal running while the plugin is connected.

If `55434` is already in use, choose a different local port:

```bash
kubectl -n ceerat-data port-forward svc/postgres 55435:5432
```

### Stop or Clean Up

Remove Ceerat resources from the current cluster:

```bash
SKIP_DELETE=false ./k8s-stop.sh
```

Stop the local Kubernetes cluster:

```bash
./k8s-stop.sh
```

Useful knobs:

```bash
K8S_DRIVER=docker-desktop ./k8s-start.sh
SKIP_BUILD=true ./k8s-start.sh
SKIP_DEPLOY=true ./k8s-start.sh
STOP_CLUSTER=false ./k8s-stop.sh
```

If `kubectl get svc -A` fails with this error:

```text
Unable to connect to the server: x509: certificate signed by unknown authority
```

`kubectl` is probably pointed at a stale or remote context. Switch back to the local Colima context:

```bash
kubectl config current-context
kubectl config use-context colima
kubectl get svc -A
```

If the `colima` context does not exist yet, start Colima with Kubernetes enabled:

```bash
colima start --kubernetes
kubectl config use-context colima
kubectl get svc -A
```

For Docker Desktop, stop Kubernetes from Docker Desktop settings.

## Optional Typesense Job Search

Imported ATS jobs remain stored in Postgres as the source of truth. Typesense is an optional derived search index owned by `ceerat-user-service`; the crawler and browser apps do not write to Typesense directly.

Start a local Typesense instance:

```bash
TYPESENSE_API_KEY=dev_typesense_key docker compose -f infra/docker-compose.typesense.yml up -d
```

`start-stack.sh` starts Typesense when Docker is available. It supports legacy `docker-compose`, the modern `docker compose` plugin, and a plain `docker run` fallback named `ceerat-typesense` when Compose is not installed.

If Docker itself is not running or not reachable, Typesense startup is skipped and the user service falls back to database-backed job search unless Typesense env vars are provided. To skip Typesense intentionally:

```bash
TYPESENSE_DISABLED=true infra/start-stack.sh
```

Enable indexing/search when starting the stack:

```bash
TYPESENSE_HOST=localhost \
TYPESENSE_PORT=8108 \
TYPESENSE_PROTOCOL=http \
TYPESENSE_API_KEY=dev_typesense_key \
TYPESENSE_COLLECTION_JOBS=jobs \
infra/start-stack.sh
```

If any Typesense env var is missing, the user service logs job search as disabled and falls back to database-backed job search.

Indexing behavior:
- `career.JobService/ImportATSJobs` saves jobs to Postgres first.
- After a successful save/update, `ceerat-user-service` normalizes and upserts the saved job into Typesense.
- Typesense errors are logged and do not fail the import.

Rebuild the index from Postgres:

```bash
curl -X POST http://localhost:8081/api/admin/jobs/search-index/rebuild \
  -H "Authorization: Bearer $CEERAT_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recreate":true}'
```

The rebuild response returns counts only: processed, succeeded, and failed.
