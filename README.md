# Infra: start/stop stack

This folder contains helper scripts to start a local development stack for Ceerat.

For source-level documentation across contracts, services, gateways, and apps,
follow the [Go workspace and pkgsite guide](docs/go-documentation.md).

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

## Production setup: Keycloak, OAuth, and admin seeding

Use the production flow when the stack is deployed to Render or another shared environment. The important rule is that production environment values must be explicit and environment-specific; do not reuse a local or test realm with a production issuer or client configuration.

### Production identity model

There are three distinct identities to keep separate:

- Keycloak server admin: the login used to manage the realm itself.
- Ceerat app admin: a user inside the `ceerat` realm that can access the admin portal.
- Ceerat customer or agent users: users who authenticate through OAuth and are provisioned by the user service based on the client ID and policy.

The Ceerat backend does not grant admin access based on email alone. The first admin seed is bound by:

- `INITIAL_ADMIN_EMAIL`
- `INITIAL_ADMIN_ISSUER`
- `INITIAL_ADMIN_SUBJECT`
- `INITIAL_ADMIN_CLIENT_ID`

The seed uses the exact Keycloak `sub` value, not the email or username.

### Production checklist

Before deploying or starting a production-like environment, ensure:

1. The Keycloak realm is created and configured for the target environment.
2. The OAuth issuer matches the actual realm URL, for example:
   ```env
   CEERAT_OAUTH_ISSUER=https://<your-keycloak-host>/realms/ceerat
   ```
3. The browser client definitions match the live redirect URIs exactly:
   - `ceerat-admin-ui`
   - `ceerat-web-ui`
   - `ceerat-customer-ui`
4. The Google or social identity provider is configured and uses the correct client ID and secret for that environment.
5. The initial admin user exists in the realm, is email-verified, and has its Keycloak user ID recorded.
6. The backend is started with the admin seed values, such as:
   ```env
   INITIAL_ADMIN_EMAIL=admin@ceerat.local
   INITIAL_ADMIN_ISSUER=https://<your-keycloak-host>/realms/ceerat
   INITIAL_ADMIN_SUBJECT=<exact-keycloak-user-id>
   INITIAL_ADMIN_CLIENT_ID=ceerat-admin-ui
   ```
7. The app and backend are restarted after those values are added.

### Production login behavior

- The Keycloak server admin password and the Ceerat app admin password are different.
- A Google or social login can only be used for the app role it is provisioned for. A Google identity used for a customer flow must map to a customer account, not to an admin or agent account.
- A new social-only user does not automatically become an admin. The app service provisions users based on the client and policy, and the admin must be explicitly seeded or bound.
- When the admin seed is created, the issuer and subject are the authoritative binding. Email-only matching is never sufficient.

### Production deployment quick checklist

Use this as the short release checklist before opening the production app:

```text
1. Configure the target Keycloak realm and keep the production issuer distinct from local or test issuers.
2. Ensure the exact browser redirect URIs exist for ceerat-admin-ui, ceerat-web-ui, and ceerat-customer-ui.
3. Configure Google or other social providers with the production client ID and secret.
4. Create the Ceerat app admin user in the realm and capture the exact Keycloak user ID.
5. Set INITIAL_ADMIN_EMAIL, INITIAL_ADMIN_ISSUER, INITIAL_ADMIN_SUBJECT, and INITIAL_ADMIN_CLIENT_ID in the backend environment.
6. Restart the backend/user-service and browser UIs after the values are added.
7. Sign in with the admin user through the Ceerat app, not the Keycloak server admin account.
8. Verify customer social sign-in uses ceerat-customer-ui, and web/agent sign-in uses ceerat-web-ui with agent/pending provisioning.
```

## Development / local setup: Keycloak and the Ceerat admin account

The local stack is intentionally similar to production, but uses a local Keycloak container and loopback URLs.

There are two different admin identities in the local stack, and this is easy to confuse:

- The Keycloak server admin is the login you use at `http://localhost:8080/admin/` to manage the realm. This is the administrator for Keycloak itself; the password is generated locally and stored in `.run/keycloak-admin-password` by `start-stack.sh`.
- The Ceerat app admin is a user inside the `ceerat` realm used to sign in to the Ceerat app. It is not the same thing as the Keycloak server admin. It is created by the bootstrap helper or by a manual user setup in the realm.

The imported realm file in `dev/keycloak/ceerat-realm.json` sets up the OAuth clients and realm configuration, but it does not automatically create the app admin account. The app admin must be created in the `ceerat` realm and bound by its exact Keycloak `sub` value via `INITIAL_ADMIN_ISSUER` and `INITIAL_ADMIN_SUBJECT`.

### Bootstrap the local Ceerat admin user

```bash
cd infra
make start-stack
ruby dev/keycloak/bootstrap-local-admin.rb
cat .run/admin-login-password
```

This helper creates or updates `admin@ceerat.local`, verifies and enables it, sets a non-temporary password, and prints the four values needed for the backend seed:

```env
INITIAL_ADMIN_EMAIL=admin@ceerat.local
INITIAL_ADMIN_ISSUER=http://localhost:8080/realms/ceerat
INITIAL_ADMIN_SUBJECT=<Keycloak-user-id>
INITIAL_ADMIN_CLIENT_ID=ceerat-admin-ui
```

Add those values to `infra/.env` (or export them in your shell) before restarting the stack.

### Local `.env` example

```env
# Core local stack
CEERAT_ENV=development

# Postgres
CEERAT_DB_HOST=localhost
CEERAT_DB_PORT=55434
CEERAT_DB_USER=postgres
CEERAT_DB_PASSWORD=postgres
CEERAT_DB_NAME=postgres

# Keycloak / OAuth
CEERAT_KEYCLOAK_PORT=8080
CEERAT_OAUTH_ISSUER=http://localhost:8080/realms/ceerat

# App admin seed
INITIAL_ADMIN_EMAIL=admin@ceerat.local
INITIAL_ADMIN_ISSUER=http://localhost:8080/realms/ceerat
INITIAL_ADMIN_SUBJECT=<exact-keycloak-user-sub>
INITIAL_ADMIN_CLIENT_ID=ceerat-admin-ui

# Optional explicit browser values
CEERAT_WEB_OAUTH_CLIENT_ID=ceerat-web-ui
CEERAT_WEB_OAUTH_REDIRECT_URL=http://localhost:3000/oauth/callback
CEERAT_ADMIN_OAUTH_CLIENT_ID=ceerat-admin-ui
CEERAT_ADMIN_OAUTH_REDIRECT_URL=http://localhost:3010/oauth/callback

# Optional Typesense
TYPESENSE_DISABLED=true
```

For local-only domains such as `ceerat.local`, Keycloak can mark the email as verified directly in the user settings. This is the expected behavior for non-public or test domains: the app does not require a publicly routable email domain to work locally.

The important values are `CEERAT_OAUTH_ISSUER` and the admin seed values. `INITIAL_ADMIN_SUBJECT` must be the exact Keycloak `sub` value for the admin user, not just the email address.

Then restart the stack:

```bash
make stop-stack
make start-stack
```

### Manual local setup

If you do not use the helper, create the user manually in the `ceerat` realm in the Keycloak admin UI:

1. Log in as the Keycloak server admin at `http://localhost:8080/admin/`.
2. In the `ceerat` realm, create a user with email `admin@ceerat.local`.
3. Mark the email as verified and set a password. This is expected for local/test domains like `ceerat.local` because the app is using Keycloak-managed local identities, not a real public email provider.
4. Copy the user's Keycloak ID (`sub`), then set the env vars above.
5. Restart the user service and UI stack so the backend seed binds the admin account.

### Local social login behavior

- Social login is still tied to the Keycloak identity and the client policy.
- A social login for the customer portal must be configured for the `ceerat-customer-ui` client and match the customer identity path.
- A social login for the web/agent portal is provisioned as an `agent/pending` account and is not automatically an admin.
- The same strict principle used in production applies locally: the user service provisions based on the client and the exact identity binding, not by email alone.

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

By default, the Ceerat frontend services are `ClusterIP` services. They are internal to Kubernetes until you choose an access mode.

Use LoadBalancer exposure when you want the browser ports available without background `kubectl port-forward` processes:

```bash
./k8s-start.sh --expose
```

This exposes the frontend apps through Kubernetes Services:

```text
web:      http://localhost:3000
customer: http://localhost:3005
admin:    http://localhost:3010
```

On local Colima/k3s, this uses the cluster's local service load balancer. On a cloud or production-like cluster, it may allocate real external load balancers depending on the platform. Keep backend and data services internal by default.

If your cluster does not support LoadBalancer Services, use the quick port-forward mode:

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

Ingress is the hostname-based production path for browser traffic. Use it when you are deploying Ceerat behind a real ingress controller, load balancer, DNS, and HTTPS certificate. For local browser access, use `./k8s-start.sh --expose` when your cluster supports LoadBalancer Services, or `./k8s-start.sh --local` as the port-forward fallback.

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

If the ingress controller service shows `EXTERNAL-IP` as `pending`, the cluster does not have a load balancer implementation for ingress. In production, fix this through the cloud load balancer or platform networking layer. In local development, use `./k8s-start.sh --expose` for service-level LoadBalancer access, or `./k8s-start.sh --local` if LoadBalancer Services are unavailable.

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

If `kubectl` points at the `colima` context but fails with a refused local API server port, for example:

```text
The connection to the server 127.0.0.1:60902 was refused
```

the Colima VM may be running while its Kubernetes API server or kubeconfig port is stale. `./k8s-start.sh` now restarts Colima Kubernetes automatically when it detects this. To recover manually:

```bash
colima kubernetes stop
colima kubernetes start
kubectl config use-context colima
kubectl cluster-info
```

For Docker Desktop, stop Kubernetes from Docker Desktop settings.

## Optional Typesense Search

Jobs and products remain stored in Postgres as the source of truth. Typesense is an optional derived search index owned by `ceerat-user-service`; crawlers and browser apps do not write to Typesense directly.

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
TYPESENSE_COLLECTION_PRODUCTS=products \
infra/start-stack.sh
```

If required Typesense connection variables are missing, the user service falls back to database-backed job and product search.

Indexing behavior:
- `career.JobService/ImportATSJobs` saves jobs to Postgres first.
- After a successful save/update, `ceerat-user-service` normalizes and upserts the saved job into Typesense.
- Typesense errors are logged and do not fail the import.
- Seeded and batch-upserted products are indexed into the `products` collection; product search falls back to Postgres if Typesense is unavailable.

Rebuild the index from Postgres:

```bash
grpcurl -plaintext \
  -H "Authorization: Bearer $CEERAT_ADMIN_TOKEN" \
  -d '{"recreate":true}' \
  localhost:50051 \
  admin.AdminService/RebuildJobSearchIndex
```

The rebuild response returns counts only: processed, succeeded, and failed.
