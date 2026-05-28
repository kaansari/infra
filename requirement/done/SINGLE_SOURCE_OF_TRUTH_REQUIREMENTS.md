# Ceerat Security, RBAC, Admin UI, Registration, and AI Agent Requirements

## 1. Purpose

This document is the single source of truth consolidated from all Markdown requirement and implementation note files in the archive. It defines the expected behavior, architecture, data model, security rules, admin interfaces, AI-agent integration rules, acceptance criteria, and detailed instructions for Codex or another coding agent.


## 2. Product Goal

Secure the Ceerat platform by enforcing JWT authentication on protected gRPC methods, then layering role-based access control over authenticated calls. Add admin-only user and RBAC management screens, customer self-registration, safe admin bootstrap behavior, and AI-agent integration that respects the same authorization model.

The intended gRPC flow is:

```text
gRPC request
  -> JWT interceptor validates token
  -> authenticated user is injected into context
  -> RBAC interceptor checks user role against role_permissions
  -> handler executes only when allowed
```

---

## 3. Core Roles

The initial platform roles are:

```text
admin
agent
customer
```

### 3.1 Admin

Admins have full platform access. The admin role must support a wildcard permission:

```text
admin -> *
```

### 3.2 Agent

Agents are internal service users. Default agent permissions should include:

```text
/customer.CustomerService/CreateCustomer
/customer.CustomerService/GetCustomer
/customer.CustomerService/ListCustomers
/customer.CustomerService/UpdateCustomer
/service.ServiceManager/ListServices
/service.ServiceManager/AssignServiceToCustomer
/order.OrderManager/CreateOrder
/order.OrderManager/GetOrder
/order.OrderManager/ListOrders
/order.OrderManager/AddServiceToOrder
/order.OrderManager/UpdateOrderStatus
```

### 3.3 Customer

Customers are customer portal users. Default customer permissions should include:

```text
/customer.CustomerService/GetCustomer
/service.ServiceManager/ListServices
/order.OrderManager/GetOrder
/order.OrderManager/ListOrders
```

Customer users must be restricted to their own customer profile and their own orders.

---

## 4. User Model and Token Requirements

Add `role` support across the user domain, proto contract, persistence layer, JWT claims, and authenticated context.

Example proto shape:

```proto
message User {
    string id = 1;
    string name = 2;
    string company = 3;
    string email = 4;
    string password = 5;
    string token = 6;
    string role = 7;
}
```

Requirements:

1. Newly registered users default to role `customer`.
2. Seed at least one admin user for local development.
3. JWT claims must include role data.
4. Passwords and raw tokens must not be signed into JWT payloads except as the JWT itself.
5. `ValidateToken` must return enough user data for authorization:

```text
user_id
email
name
company
role
```

6. The authenticated context should expose:

```go
AuthenticatedUser{
    ID: userID,
    Email: email,
    Name: name,
    Role: role,
}
```

Handlers should read:

```go
user, ok := security.AuthenticatedUserFromContext(ctx)
```

---

## 5. JWT gRPC Security Requirements

All protected gRPC methods must validate caller JWTs before executing business logic.

### 5.1 Metadata Format

Protected gRPC calls must include:

```text
authorization: Bearer <jwt-token>
```

For compatibility, the interceptor should also accept:

```text
x-auth-token: <jwt-token>
```

Never log JWT token values, authorization headers, passwords, or credentials.

### 5.2 Public Method Allowlist

These methods must bypass JWT validation because they are needed before a JWT exists or for health checks:

```text
/auth.Auth/Auth
/auth.Auth/Create
/auth.Auth/Register
/auth.Auth/Login
/auth.Auth/ValidateToken
/grpc.health.v1.Health/Check
/health.Health/Check
```

`Register` and `Login` are compatibility names. In the current generated auth service, registration is `/auth.Auth/Create` and login is `/auth.Auth/Auth`.

### 5.3 Interceptor Behavior

Before executing a protected method:

```text
1. Read authorization metadata.
2. Extract Bearer token, or fallback to x-auth-token.
3. Validate token through user service token validation logic.
4. Inject authenticated user into context.
5. Continue if valid.
6. Reject missing or invalid tokens.
```

Error mapping:

```text
Missing token  -> codes.Unauthenticated
Invalid token  -> codes.Unauthenticated
Wrong resource -> codes.PermissionDenied
```

Use safe messages such as:

```text
authentication required
invalid token
access denied
```

### 5.4 Recommended Security Package

Use a shared reusable package, preferably under the existing repository security package location, such as:

```text
packages/ceerat-contracts/security
```

or, if the repository already uses it:

```text
pkg/security
```

Suggested files:

```text
jwt_interceptor.go
allowlist.go
auth_context.go
rbac_interceptor.go
rbac_cache.go
rbac_repository.go
rbac_context.go
grpc_methods.go
```

### 5.5 Token Validator Contract

Implement an interface equivalent to:

```go
type TokenValidator interface {
    ValidateToken(ctx context.Context, token string) (*AuthenticatedUser, error)
}
```

The user service may use its local token service to avoid making a recursive gRPC call to its own public `ValidateToken` method. Other gRPC servers may use a user-service-backed validator such as:

```go
security.NewUserServiceTokenValidator(authpb.NewAuthClient(conn))
```

### 5.6 Enablement

`ceerat-user-service` should apply JWT enforcement unless:

```env
JWT_AUTH_ENABLED=false
JWT_AUTH_ENABLED=0
JWT_AUTH_ENABLED=no
```

This bypass is only for temporary local development.

---

## 6. RBAC Authorization Requirements

Add RBAC authorization on top of the JWT security layer.

### 6.1 RBAC Model

Permissions are method-level gRPC permissions.

Example permission values:

```text
/customer.CustomerService/CreateCustomer
/customer.CustomerService/ListCustomers
/service.ServiceManager/ListServices
/order.OrderManager/CreateOrder
```

A role can have many permissions. A permission grants access to one gRPC full method name unless it is wildcard `*`.

### 6.2 Database Tables

Add migrations equivalent to:

```sql
CREATE TABLE roles (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE role_permissions (
    id UUID PRIMARY KEY,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    grpc_method TEXT NOT NULL,
    description TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(role_id, grpc_method)
);

ALTER TABLE users
ADD COLUMN role_id UUID NULL REFERENCES roles(id);

CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_role_permissions_role_id ON role_permissions(role_id);
CREATE INDEX idx_role_permissions_grpc_method ON role_permissions(grpc_method);
```

Seed initial roles:

```sql
INSERT INTO roles (id, name, description)
VALUES
(gen_random_uuid(), 'admin', 'Full platform administrator'),
(gen_random_uuid(), 'agent', 'Internal service agent'),
(gen_random_uuid(), 'customer', 'Customer portal user');
```

### 6.3 RBAC Cache

RBAC permissions must be cached in memory.

Cache shape:

```go
map[string]map[string]bool
```

Example:

```go
permissions["agent"]["/customer.CustomerService/CreateCustomer"] = true
permissions["admin"]["*"] = true
```

Requirements:

1. Load permissions from DB on service startup.
2. Support wildcard `*`.
3. Provide:

```go
func (c *RBACCache) Refresh(ctx context.Context) error
```

4. Add optional periodic refresh:

```env
RBAC_CACHE_REFRESH_INTERVAL=60s
```

5. Add manual admin-only cache refresh:

```http
POST /api/admin/rbac/cache/refresh
```

### 6.4 RBAC Interceptor Contract

Suggested contract:

```go
type PermissionChecker interface {
    IsAllowed(ctx context.Context, role string, grpcMethod string) (bool, error)
    Refresh(ctx context.Context) error
}

type RBACInterceptor struct {
    checker PermissionChecker
    publicMethods map[string]bool
}

func NewRBACInterceptor(
    checker PermissionChecker,
    publicMethods []string,
) *RBACInterceptor
```

### 6.5 RBAC Enforcement Logic

For every gRPC request:

```text
1. Is method public?
   - yes: allow
2. Is user authenticated?
   - no: return codes.Unauthenticated
3. Does user role have permission for info.FullMethod or wildcard *?
   - yes: allow
   - no: return codes.PermissionDenied
```

Suggested denial:

```go
return nil, status.Error(codes.PermissionDenied, "role is not allowed to access this service")
```

### 6.6 Interceptor Order

JWT must run before RBAC:

```go
grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        jwtInterceptor.Unary(),
        rbacInterceptor.Unary(),
    ),
)
```

Reason:

```text
JWT identifies the user.
RBAC authorizes the user's role.
```

If logging middleware exists, chain it after authorization unless the repository has a stronger existing convention.

---

## 7. Known gRPC Methods

Maintain a known list of gRPC methods for the admin RBAC UI.

Suggested file:

```text
pkg/security/grpc_methods.go
```

Example:

```go
var KnownGRPCMethods = []string{
    "/customer.CustomerService/CreateCustomer",
    "/customer.CustomerService/GetCustomer",
    "/customer.CustomerService/ListCustomers",
    "/customer.CustomerService/UpdateCustomer",
    "/service.ServiceManager/CreateService",
    "/service.ServiceManager/ListServices",
    "/service.ServiceManager/AssignServiceToCustomer",
    "/order.OrderManager/CreateOrder",
    "/order.OrderManager/GetOrder",
    "/order.OrderManager/ListOrders",
}
```

The admin UI should display this list, preferably as checkboxes or another easy assignment control.

---

## 8. Customer Self-Registration Requirements

Public registration must create both:

```text
users record
linked customers record
```

### 8.1 Registration Form

The web UI registration page must collect:

```text
first name
last name
company
email
phone
password
address fields
```

### 8.2 Registration Flow

After successful registration:

```text
1. Auth.Create creates the user.
2. The returned JWT is used to call CustomerService.CreateCustomer.
3. The customer profile is linked to the new user's ID.
4. The user is logged in.
```

### 8.3 Customer Security Rules

If authenticated role is `customer`:

1. `CustomerService.CreateCustomer` must force `customer.user_id` to the authenticated user ID.
2. The service must check whether that user already has a customer profile.
3. If a profile exists, return `PermissionDenied`.
4. A customer-role user cannot create additional customer records.
5. Orders can only be created for that customer's own customer profile.
6. Attempts to create orders for another customer must return access denied, not found, or permission denied.

Agents and admins may create multiple customers only if RBAC permissions allow them.

---

## 9. Admin User Management and RBAC UI Requirements

Add admin-only dashboard pages:

```text
/admin/users
/admin/rbac
```

Both require a logged-in user with role:

```text
admin
```

### 9.1 User Management Features

The `/admin/users` page must support:

```text
Create user
View users
Update user name/company/email
Update user role
Reset user password
```

Web UI endpoints:

```http
GET    /api/admin/users
POST   /api/admin/users
PATCH  /api/admin/users/{id}
PATCH  /api/admin/users/{id}/password
DELETE /api/admin/users/{id}
```

The delete endpoint is intentionally disabled in the user service until a deactivate or soft-delete design exists.

### 9.2 RBAC Management Features

The `/admin/rbac` page must support:

```text
View roles
Create role
Edit role
Delete role
View known gRPC service methods
Assign gRPC service methods to roles
Remove role permissions
Assign role to user
Refresh RBAC cache
```

Web UI endpoints:

```http
GET    /api/admin/roles
POST   /api/admin/roles
PATCH  /api/admin/roles/{id}
DELETE /api/admin/roles/{id}

GET    /api/admin/role-permissions
POST   /api/admin/role-permissions
DELETE /api/admin/role-permissions/{id}

GET    /api/admin/rbac/methods
POST   /api/admin/rbac/cache/refresh
```

Also support, where already present or preferred by repository conventions:

```http
GET    /api/admin/roles/{id}/permissions
POST   /api/admin/roles/{id}/permissions
DELETE /api/admin/roles/{id}/permissions/{permissionId}

PATCH  /api/admin/users/{id}/role
```

All admin endpoints must require:

```text
valid JWT
role = admin
```

### 9.3 Admin API Example Payloads

Create role:

```json
{
  "name": "dispatcher",
  "description": "Can schedule and assign services"
}
```

Add permission:

```json
{
  "grpc_method": "/order.OrderManager/CreateOrder",
  "description": "Create customer orders"
}
```

Assign user role:

```json
{
  "role_id": "role-uuid"
}
```

### 9.4 Admin HTTP Bridge

Because generated Go protobuf files may not yet include the newly declared RBAC CRUD methods, keep or implement a small admin HTTP bridge inside `ceerat-user-service`.

Default admin API:

```text
http://localhost:8081
```

Environment variables:

```env
CEERAT_USER_ADMIN_PORT=8081
CEERAT_ADMIN_API_BASE_URL=http://localhost:8081
```

The web UI proxies admin dashboard actions through the admin HTTP bridge. The bridge must validate the caller JWT and require `role=admin`.

Recommended follow-up after protobuf regeneration: move bridge methods into first-class gRPC methods if desired.

### 9.5 Admin Role Gate Fix

The web UI must not falsely block valid admins because of stale or missing session role data.

`requireAdmin` should:

```text
1. Accept local session when session.User.Role == admin.
2. Otherwise call the user-service admin API, for example ListRoles, with the current JWT.
3. Let the user-service admin API make the authoritative admin decision from the current database role.
```

The real security decision belongs in `ceerat-user-service`, not only in the web UI.

---

## 10. Admin Bootstrap and Role Freshness

If `/admin/users` or `/admin/rbac` returns:

```json
{"error":"Admin role is required."}
```

the logged-in user may not be resolving to the `admin` role.

Requirements:

1. Promote the configured bootstrap admin email to the `admin` role on startup.
2. Make the admin HTTP bridge verify the current persisted database role instead of relying only on the role embedded in an older JWT.
3. After changing a user's role, the user should log out and log back in so the browser receives a fresh JWT with the latest role claim.
4. The gRPC RBAC interceptor may still use the authenticated role from JWT context, so fresh login after role changes remains important.

Default seeded admin:

```text
email: admin@ceerat.local
password: admin123
```

Override with:

```env
RBAC_SEED_ADMIN_EMAIL=your-admin@example.com
RBAC_SEED_ADMIN_PASSWORD=change-me
```

Restart the user service after setting these values.

---

## 11. AI Agent Integration Requirements

The repository includes an AI agent service at:

```text
ai/ceerat-agent-service
```

The agent is an HTTP service that:

```text
1. Receives chat requests from the web app or API clients.
2. Validates the current Ceerat JWT with auth.Auth/ValidateToken.
3. Extracts authenticated user.id from the JWT payload.
4. Uses OpenAI tool calling to decide which platform action to run.
5. Executes work through existing Ceerat gRPC APIs.
```

The agent must not write directly to the database.

### 11.1 Agent Architecture

```text
Browser / Web UI
  |
  | POST /api/agent/chat
  v
ceerat-web-ui
  |
  | POST /agent/chat with Authorization: Bearer <JWT>
  v
ceerat-agent-service
  |
  | auth.ValidateToken
  | customer.CreateCustomer
  | customer.ListCustomers
  | service.ListServices
  | service.AssignServiceToCustomer
  v
ceerat-user-service gRPC
  |
  v
Postgres
```

### 11.2 Agent Environment Variables

Agent service:

```bash
export OPENAI_API_KEY="sk-your-key"
export OPENAI_MODEL="gpt-4.1-mini"
export CEERAT_USER_SERVICE_ADDR="localhost:50051"
export PORT="8088"
```

Web UI hook:

```bash
export CEERAT_AGENT_BASE_URL="http://localhost:8088"
```

Stack script variables:

```bash
export OPENAI_API_KEY="sk-your-key"
export OPENAI_MODEL="gpt-4.1-mini"
export CEERAT_AGENT_PORT="8088"
```

### 11.3 Agent Tools

Initial exposed tools:

```text
create_customer
list_customers
list_services
assign_service_to_customer
```

New tools should be added in:

```text
ai/ceerat-agent-service/internal/agent/tools.go
```

Each tool should call:

```text
ai/ceerat-agent-service/internal/platform/client.go
```

and that client should call existing gRPC APIs.

### 11.4 Agent Security

1. The agent must not ask for or store passwords.
2. The web UI must pass the existing Ceerat JWT to the agent.
3. The agent must validate the JWT.
4. The agent must pass the JWT as metadata to platform gRPC tool calls.
5. RBAC must naturally apply to agent actions.
6. Handle `codes.PermissionDenied` with a friendly message:

```text
You do not have permission to perform that action.
```

Example:

```text
Customer role asks AI agent: "Create a service"
  -> AI agent calls CreateService
  -> RBAC denies service call
  -> Agent replies with a friendly permission error
```

---

## 12. Logging Requirements

Add structured authorization logs.

Allowed log examples:

```json
{
  "event": "rbac.allowed",
  "user_id": "user-id",
  "role": "agent",
  "method": "/order.OrderManager/CreateOrder"
}
```

```json
{
  "event": "rbac.denied",
  "user_id": "user-id",
  "role": "customer",
  "method": "/order.OrderManager/CreateOrder"
}
```

```json
{
  "event": "rbac.cache.refreshed",
  "role_count": 3,
  "permission_count": 24
}
```

Never log:

```text
JWT token
password
authorization header
sensitive credentials
```

---

## 13. Files and Areas to Add or Update

Adapt paths to the existing repository layout.

Core security:

```text
packages/ceerat-contracts/security/jwt_interceptor.go
packages/ceerat-contracts/security/allowlist.go
packages/ceerat-contracts/security/auth_context.go
packages/ceerat-contracts/security/rbac_interceptor.go
packages/ceerat-contracts/security/rbac_cache.go
packages/ceerat-contracts/security/rbac_repository.go
packages/ceerat-contracts/security/grpc_methods.go
```

or equivalent:

```text
pkg/security/...
```

User service:

```text
services/ceerat-user-service/main.go
services/ceerat-user-service/admin_http.go
services/ceerat-user-service/migrations/20260505_rbac.sql
```

Contracts:

```text
packages/ceerat-contracts/proto/auth/auth.proto
packages/ceerat-contracts/proto/**/*.proto
```

Web UI:

```text
apps/ceerat-web-ui/internal/apiclient/admin.go
apps/ceerat-web-ui/internal/apiclient/client.go
apps/ceerat-web-ui/internal/config/config.go
apps/ceerat-web-ui/internal/server/server.go
apps/ceerat-web-ui/main.go
apps/ceerat-web-ui/web/templates/admin_users.html
apps/ceerat-web-ui/web/templates/rbac.html
apps/ceerat-web-ui/web/static/admin-users.js
apps/ceerat-web-ui/web/static/rbac.js
```

AI agent:

```text
ai/ceerat-agent-service
ai/ceerat-agent-service/internal/agent/tools.go
ai/ceerat-agent-service/internal/platform/client.go
```

Tests and documentation:

```text
tests/security/jwt_interceptor_test.go
docs/grpc-security.md
docs/rbac-security.md
```

---

## 14. Protobuf and Tooling Requirements

`packages/ceerat-contracts/proto/auth/auth.proto` must include:

```proto
string role = 7;
```

Full RBAC CRUD RPCs may already be declared in `auth.proto`, but generated Go files may be stale. Regenerate protobuf bindings in a proper development environment.

Recommended command:

```bash
cd packages/ceerat-contracts
make proto
```

Then wire generated RBAC CRUD client methods into:

```text
apps/ceerat-web-ui/internal/apiclient
```

If the environment lacks `protoc`, `buf`, or the required Go toolchain, do not fake generated files. Keep the HTTP bridge approach and document the follow-up.

---

## 15. Run and Test Commands

The repository notes mention Go `1.26.2`.

Recommended commands in a development environment with required tooling:

```bash
cd packages/ceerat-contracts
make proto
go test ./...

cd ../../services/ceerat-user-service
go test ./...

cd ../../apps/ceerat-web-ui
go test ./...
```

Full stack:

```bash
export OPENAI_API_KEY="sk-your-key"
make start-stack
```

Manual services:

```bash
go run ./services/ceerat-user-service
```

```bash
export OPENAI_API_KEY="sk-your-key"
export CEERAT_USER_SERVICE_ADDR="localhost:50051"
go run ./ai/ceerat-agent-service
```

```bash
export CEERAT_AGENT_BASE_URL="http://localhost:8088"
go run ./apps/ceerat-web-ui
```

---

## 16. Manual Acceptance Test Scenarios

### 16.1 JWT Security

1. Call a protected gRPC method without token.
2. Expected: `codes.Unauthenticated`.
3. Call with invalid token.
4. Expected: `codes.Unauthenticated`.
5. Call public auth or health method without token.
6. Expected: allowed.

### 16.2 RBAC

1. Admin accesses any protected method.
2. Expected: allowed through wildcard.
3. Agent accesses configured agent method.
4. Expected: allowed.
5. Customer accesses restricted method.
6. Expected: `codes.PermissionDenied`.
7. Unknown role accesses protected method.
8. Expected: denied.
9. Refresh RBAC cache after permission change.
10. Expected: new permissions are applied.

### 16.3 Customer Registration

1. Start the stack.
2. Open `/register`.
3. Enter customer details.
4. Submit registration.
5. Confirm user row is created with `role = customer`.
6. Confirm customer row is created with `customers.user_id = users.id`.
7. Log in as that customer.
8. Confirm dashboard lists only that user's customer profile.
9. Try to create another customer through the API.
10. Expected: `PermissionDenied`.
11. Create an order for the customer's own profile.
12. Expected: order is created.
13. Try to create an order for another customer ID.
14. Expected: access denied, not found, or permission denied.

### 16.4 Admin UI

1. Log in as seeded admin.
2. Open `/admin/users`.
3. Expected: page loads.
4. Create or update a user.
5. Expected: operation succeeds.
6. Change a user's role.
7. Expected: persisted role changes.
8. Open `/admin/rbac`.
9. Expected: roles and known methods appear.
10. Add and remove permissions.
11. Refresh cache.
12. Expected: RBAC decisions reflect updates.
13. Log in as non-admin and open `/admin/rbac`.
14. Expected: denied.

### 16.5 AI Agent

1. Log in through the platform.
2. Use the dashboard AI Agent panel.
3. Ask to list customers.
4. Expected: agent validates JWT and calls gRPC with JWT metadata.
5. Ask for an action not permitted by current role.
6. Expected: friendly permission denial.
7. Confirm the agent did not write directly to DB.

---

## 17. Automated Test Requirements

Add tests for:

```text
JWT interceptor allows public methods.
JWT interceptor rejects missing token.
JWT interceptor rejects invalid token.
JWT interceptor accepts authorization: Bearer token.
JWT interceptor accepts x-auth-token.
Authenticated user is injected into context.
JWT validation happens before RBAC.
Public methods bypass RBAC.
Admin role can access all methods through wildcard.
Agent role can access configured methods.
Customer role is denied restricted methods.
Unknown role is denied.
Missing role is denied.
Wildcard permission works.
RBAC cache loads from DB.
RBAC cache refresh updates permissions.
Admin can create role.
Admin can update role.
Admin can delete role when allowed by business rules.
Admin can add/remove permissions.
Non-admin cannot access RBAC dashboard APIs.
Admin can list users.
Admin can create users.
Admin can update user name/company/email.
Admin can update user role.
Admin can reset user password.
Delete user endpoint remains disabled unless soft-delete exists.
Customer registration creates user and linked customer.
Customer cannot create second customer profile.
Customer cannot access another customer/order.
AI agent passes JWT to gRPC tools.
AI agent returns friendly PermissionDenied errors.
Sensitive values are never logged.
```

---

## 18. Final Acceptance Criteria

The overall work is complete when:

```text
Protected gRPC calls require JWT.
Public auth and health methods bypass JWT.
Authenticated user is injected into context.
Users have roles.
Newly registered users become customers.
JWT validation returns user role.
JWT claims include role.
RBAC permissions are stored in DB.
RBAC permissions are cached in memory.
Admin wildcard permission works.
RBAC cache refresh works.
Each protected gRPC call checks role permission.
Unauthorized role receives PermissionDenied.
Admin can manage users from dashboard.
Admin can manage roles and permissions from dashboard.
Admin can assign roles to users.
Admin dashboard is hidden from non-admin users.
Admin HTTP bridge validates current persisted DB role.
Seeded bootstrap admin is promoted to admin role on startup.
AI agent validates JWT and passes JWT to gRPC calls.
AI agent respects RBAC automatically.
Permission errors are user-friendly.
Logs show RBAC decisions safely.
Tests pass.
Generated protobuf files are regenerated when tooling is available.
```

---

# Detailed Instructions for Codex

## A. First inspect the repository

1. Identify the actual security package location. Prefer existing `packages/ceerat-contracts/security`; otherwise use existing `pkg/security`.
2. Identify existing auth proto names and generated service full method names.
3. Identify existing user model, repository, migration, and service startup patterns.
4. Identify existing web UI router, session, template, static JS, and API proxy patterns.
5. Identify existing AI agent service and gRPC platform client patterns.
6. Do not invent parallel architectures where an existing convention already exists.

## B. Implement JWT security first

1. Add or update JWT unary interceptor.
2. Add stream interceptor only if the repository uses streaming or it is straightforward.
3. Implement public method allowlist.
4. Parse `authorization: Bearer <token>`.
5. Support `x-auth-token`.
6. Validate via local token validator in `ceerat-user-service`.
7. Validate via user-service auth client for other services.
8. Inject `AuthenticatedUser` into context.
9. Ensure protected handlers prefer authenticated user ID over request `user_id` for production traffic.
10. Add tests before moving to RBAC.

## C. Implement role support

1. Add `role` to auth proto user message.
2. Add role to domain models and DTOs.
3. Add role to JWT claims and ValidateToken response.
4. Remove password/token from any signed user payload.
5. Default new registered users to `customer`.
6. Add or update migrations for `roles`, `role_permissions`, and `users.role_id`.
7. Seed `admin`, `agent`, and `customer`.
8. Seed local admin user with override environment variables.
9. Promote configured bootstrap admin email to admin on startup.

## D. Implement RBAC

1. Add permission repository interfaces.
2. Implement RBAC cache with wildcard support.
3. Load cache on startup.
4. Add optional refresh interval.
5. Add admin-only manual refresh endpoint.
6. Add RBAC interceptor.
7. Chain JWT before RBAC.
8. Bypass RBAC for public methods.
9. Return `Unauthenticated` when no authenticated user exists.
10. Return `PermissionDenied` when role lacks permission.
11. Add structured safe logs for allowed, denied, and cache refresh events.

## E. Implement customer self-registration

1. Update registration form fields.
2. Create user via `Auth.Create`.
3. Use returned JWT to call `CustomerService.CreateCustomer`.
4. Link customer profile to authenticated user ID.
5. Force customer user ID server-side for `customer` role.
6. Deny duplicate customer profile creation for customer role.
7. Ensure order logic only permits customer's own profile.
8. Add tests.

## F. Implement admin UI and bridge

1. Add `/admin/users`.
2. Add `/admin/rbac`.
3. Add admin-only nav item visibility.
4. Add admin endpoints in web UI.
5. Implement or keep `ceerat-user-service` admin HTTP bridge.
6. Bridge must validate JWT and check current DB role is admin.
7. Web UI `requireAdmin` should accept known admin session but fallback to bridge authorization with current JWT.
8. Implement user management features except hard delete.
9. Implement role and permission management features.
10. Implement known gRPC method listing.
11. Implement cache refresh button and endpoint.
12. Add tests for admin and non-admin access.

## G. Implement AI agent authorization behavior

1. Keep agent DB-free.
2. Validate incoming bearer token with `auth.Auth/ValidateToken`.
3. Store validated token/user on agent request/session context only as needed.
4. Pass JWT metadata to all gRPC tool calls.
5. Add friendly handling for `codes.PermissionDenied`.
6. Do not ask users for passwords in chat.
7. Add tests or integration checks for denied tool actions.

## H. Regenerate protobuf files only when tooling exists

1. Run:

```bash
cd packages/ceerat-contracts
make proto
```

2. If unavailable, do not hand-write large generated files.
3. Keep minimal compatibility patches only where unavoidable.
4. Document the follow-up clearly.
5. After regeneration, wire RBAC CRUD gRPC clients into the web UI and consider replacing the admin HTTP bridge.

## I. Security constraints

1. Never log JWTs.
2. Never log passwords.
3. Never log authorization headers.
4. Never trust client-submitted user IDs over authenticated context for production traffic.
5. Do not rely solely on web UI role gates.
6. Enforce admin checks inside `ceerat-user-service`.
7. Preserve public auth and health endpoints.
8. Keep `JWT_AUTH_ENABLED=false` as a local-only temporary bypass.

## J. Suggested Codex prompt

```text
Implement the consolidated Ceerat security requirements from SINGLE_SOURCE_OF_TRUTH_REQUIREMENTS.md.

First inspect the repository and follow existing package, migration, routing, and testing conventions.

Implement JWT authentication for protected gRPC calls using a shared interceptor. Public auth and health methods must bypass authentication. Protected calls must accept authorization: Bearer <jwt> and x-auth-token. Validate tokens through the user service or local token service, inject AuthenticatedUser into context, and never log token values.

Add role support across auth proto, domain models, persistence, JWT claims, ValidateToken, and authenticated context. Default new registrations to customer. Seed admin, agent, and customer roles. Seed/promote the configured bootstrap admin user. Use RBAC_SEED_ADMIN_EMAIL and RBAC_SEED_ADMIN_PASSWORD overrides.

Implement RBAC authorization after JWT. Store role permissions in roles and role_permissions tables, support wildcard "*", cache permissions in memory, load the cache on startup, support optional RBAC_CACHE_REFRESH_INTERVAL, and expose an admin-only cache refresh endpoint. JWT interceptor must run before RBAC. Public methods bypass RBAC. Missing auth returns codes.Unauthenticated; valid users without permission return codes.PermissionDenied.

Add admin-only /admin/users and /admin/rbac pages and APIs. The admin bridge in ceerat-user-service must validate JWT and verify the current persisted database role is admin. Web UI requireAdmin should accept session admin but fallback to the bridge so stale session role data does not falsely block admins. User deletion should remain disabled unless a soft-delete design is implemented.

Add customer self-registration that creates both a user and linked customer profile. Customer-role users can have only one customer profile, cannot create profiles for other users, and can only create orders for their own customer profile.

Ensure the AI agent validates the Ceerat JWT, never writes directly to DB, passes JWT metadata to gRPC tool calls, and returns a friendly message for codes.PermissionDenied.

Regenerate protobuf bindings with make proto only if the required tooling exists. If tooling is unavailable, keep the HTTP bridge and document the follow-up instead of fabricating generated files.

Add tests for JWT, RBAC, cache refresh, admin APIs, customer self-registration, customer data isolation, and AI-agent permission errors. Ensure logs are structured and never include JWTs, passwords, or authorization headers.
```
