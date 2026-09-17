Yes. I reviewed the gateway against both the contracts repo and the service repo from the previous two reviews. The gateway is actually stronger than the service in several areas—especially around MCP argument validation, confirmation flows, idempotency, audit redaction, and ownership binding—but I found several important cross-repo inconsistencies.

I do **not** see an obvious “any caller can bypass authentication” type of gateway flaw. The bigger risks are around token/session lifecycle, duplicated authorization policy, concurrency, and the three repos disagreeing about identity and OAuth semantics.

| Priority        | Finding                                                                       | Impact                                                                       |
| --------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **High**        | Gateway → service gRPC uses plaintext while forwarding the exact bearer token | Token exposure/replay risk unless transport is independently encrypted       |
| **High**        | Connection-local revoke triggers Keycloak session-wide revoke                 | Sibling clients can end up in inconsistent revocation state                  |
| **High**        | `orders_quote_cart` requires the wrong OAuth scope in gateway                 | Gateway and canonical contracts have already drifted                         |
| **High**        | Gateway overwrites configured `ceerat_user_id` with OAuth `sub`               | Identity semantics are inconsistent and configuration is effectively ignored |
| **High**        | Profile optimistic concurrency has a TOCTOU race                              | A newer profile update can still be overwritten                              |
| **High**        | Contracts dependency still uses old module identity                           | Same split-contract problem found in the other repos                         |
| **Medium/High** | Audience expectations differ between gateway and service                      | Requires implicit dual-audience access tokens                                |
| **Medium/High** | Revoking an agent connection has no explicit confirmation                     | Destructive, potentially session-wide operation is one-click/tool-call       |
| **Medium**      | Full profile PII is stored in gateway preparation state                       | More sensitive data retained than necessary                                  |
| **Medium**      | `/readyz` doesn't actually verify downstream dependencies                     | Gateway can report ready while incapable of serving tools                    |
| **Medium**      | Gateway duplicates authorization/business policy                              | More scope/business-rule drift is likely                                     |
| **Medium**      | Money becomes `float64` in cart-clear preparation                             | Breaks your otherwise good Money abstraction                                 |
| **Medium**      | Preference scopes advertised before PreferenceService exists                  | Clients can request unusable privileges                                      |
| **Medium**      | Runtime creates/changes DB schema itself                                      | Weaker migration discipline than the service repo                            |
| **Low/Medium**  | JSON-RPC parser is less strict than your tool argument parser                 | Protocol hardening opportunity                                               |

## 1. Exact bearer tokens are sent over insecure gRPC

This is one of the first things I would address.

In:

`internal/platform/client.go`

the downstream connection uses:

```go
grpc.NewClient(
    address,
    grpc.WithTransportCredentials(
        insecure.NewCredentials(),
    ),
)
```

Then requests attach:

```go
authorization: Bearer <exact inbound token>
```

So the architecture is effectively:

```text
ChatGPT/MCP client
       │ HTTPS
       ▼
CEERAT Gateway
       │ plaintext gRPC + exact OAuth bearer token
       ▼
CEERAT User Service
```

The service repo we reviewed earlier also creates its gRPC server without TLS.

If this traffic is protected by a service mesh, encrypted private overlay, or equivalent infrastructure, the practical exposure may be reduced. But the application itself does not enforce that.

Because you are forwarding an **actual reusable bearer token**, I would use TLS/mTLS between the gateway and user service rather than relying only on network location.

This is especially important because your architecture correctly avoids creating a second artificial authentication system—the downstream service independently validates the same token. That's good, but it means that token is valuable.

---

# 2. Connection revocation has inconsistent scope

This is probably the most interesting gateway-specific security problem.

A gateway connection is identified roughly as:

```text
session_id + client_id
```

From `internal/gateway/state.go`:

```go
return p.SessionID + ":" + p.ClientID
```

So you might have:

```text
Keycloak session ABC
    ├── ABC:chatgpt
    ├── ABC:codex
    └── ABC:other-client
```

That makes sense.

But `revoke_my_agent_connection` does two different things.

Locally, it marks **one connection** revoked.

Then `internal/revocation/keycloak.go` invokes Keycloak's session deletion endpoint:

```text
/admin/realms/{realm}/sessions/{sessionID}
```

which revokes the **entire Keycloak session**.

So:

```text
local gateway state:
    chatgpt → revoked
    codex   → active

Keycloak:
    entire session → revoked
```

Those two models disagree.

It gets worse because the gateway validates JWTs offline. An access token that has already been issued can remain cryptographically valid until its expiration time.

That means the sibling Codex connection can potentially still look:

```text
gateway DB → active
JWT signature → valid
exp → valid
```

even though the corresponding Keycloak SSO session has been destroyed.

I would pick one semantic.

If `revoke_my_agent_connection` actually means:

> revoke this Keycloak login session

then atomically mark **every local connection with the same `session_id`** revoked.

If you really want per-agent-client revocation, then don't use a Keycloak session-wide revocation endpoint; revoke the relevant client grant/token family instead.

The current implementation sits uncomfortably between the two.

---

# 3. I found actual OAuth scope drift

This is important because it validates the concern from the contracts review about maintaining authorization policy in multiple places.

The canonical contracts repo says:

```text
/order.OrderManager/QuoteMyCartPricing
    → ceerat.orders.checkout
```

But the gateway says:

`internal/gateway/server.go`

```go
case "orders_quote_cart",
     "orders_operation_status":
    return "ceerat.orders.read"
```

So gateway believes:

```text
orders_quote_cart
    → ceerat.orders.read
```

while the service/contracts policy says:

```text
orders_quote_cart
    → ceerat.orders.checkout
```

Even the gateway test currently codifies the wrong value.

Fortunately, because the user service independently enforces OAuth scopes, this doesn't appear to create a privilege escalation. A token containing only `ceerat.orders.read` should eventually be rejected downstream.

But the user/client experience becomes:

```text
Gateway:
✓ you have enough permission

Service:
✗ insufficient scope
```

More importantly, this proves the architecture now has **two competing policy sources**.

I would not maintain:

```text
requiredScope()
```

by hand in the gateway.

The gateway should derive or verify this against the canonical contracts policy.

At minimum, have a test that says:

```text
for every gateway tool:
    resolve downstream gRPC method
    compare gateway required scope
    with security.MethodScopePolicies
```

That test would have caught this immediately.

---

# 4. Your configured CEERAT identity gets overwritten

The JWT validator does something reasonable.

It reads:

```text
sub
```

and also reads the configurable CEERAT identity claim:

```text
ceerat_user_id
```

using something roughly equivalent to:

```go
UserID:  userID,
Subject: sub,
```

But after validation, `server.go` does:

```go
principal.UserID = principal.Subject
```

So regardless of what:

```text
CEERAT_USER_ID_CLAIM
```

contained, the gateway effectively changes:

```text
UserID = OAuth subject
```

That makes the configurable user-ID claim mostly meaningless.

This matters because the gateway uses this identity for things including:

```text
preparation ownership
connection ownership
rate limiting
audit identity
get_current_user
```

Meanwhile, the user service maps:

```text
issuer + OAuth subject
        ↓
internal CEERAT User ID
```

Those are not necessarily identical identifiers.

I would define this explicitly as two fields:

```text
OAuthSubject
CEERATUserID
```

and never silently substitute one for the other.

If gateway state is intentionally supposed to be keyed by the stable OAuth subject, that's completely defensible. Just call it `Subject`, not `UserID`.

---

# 5. Profile update concurrency isn't actually atomic

I like the gateway's profile prepare/confirm design conceptually.

It does:

```text
Read profile
     ↓
capture updated_at/resource_version
     ↓
prepare changes
     ↓
user confirms
     ↓
read profile again
     ↓
verify version hasn't changed
     ↓
UpdateMyCustomerProfile
```

That looks safe, but there is still a race between:

```text
second read
```

and:

```text
actual update
```

For example:

```text
T1 Gateway reads version 100
T2 Gateway confirms version still 100
T3 Another client updates profile → version 101
T4 Gateway sends full profile based on version 100
T5 service overwrites version 101
```

The service repo doesn't currently receive an:

```text
expected_version
```

with `UpdateMyCustomerProfile`, nor does it perform something equivalent to:

```sql
UPDATE ...
WHERE id = ?
AND version = ?
```

So the gateway's optimistic locking is advisory rather than atomic.

This needs to be fixed at the **contracts/service level**, not by adding another gateway check.

Something like:

```protobuf
UpdateMyCustomerProfileRequest {
    CustomerProfilePatch patch = 1;
    string expected_version = 2;
}
```

and the service performs the conditional update transactionally.

This is another example where the gateway is attempting to compensate for a missing service-level guarantee.

---

# 6. The old contracts-module problem exists here too

The gateway `go.mod` still depends on:

```go
github.com/kaansari/ceerat-platform/packages/ceerat-contracts
```

with a local replacement.

But your contracts repo now declares:

```go
module github.com/kaansari/ceerat-contracts
```

So all three repos are currently carrying the same migration inconsistency.

Gateway imports and vendored files continue using:

```text
github.com/kaansari/ceerat-platform/packages/ceerat-contracts
```

For the proto files I compared, the vendored copies appear to match the uploaded contracts **today**, so I didn't find evidence that your gateway currently has an older schema snapshot.

But this setup makes future drift very easy.

There are effectively three dependency mechanisms:

```text
canonical standalone repo
local replace directive
vendored copy
```

I would choose one canonical module identity and one reproducible dependency strategy.

---

# 7. Gateway and service disagree about OAuth audience

This one may be intentional, but right now the architecture isn't clear enough.

Your canonical contracts/security package uses:

```text
ceerat-api
```

as the protected API audience.

The user service expects that audience.

The gateway, however, validates tokens against the MCP resource URL, conceptually:

```text
https://agents.ceerat.com/mcp
```

and configuration explicitly requires:

```text
Audience == ResourceURL
```

Then the gateway forwards that exact same token to the service.

Therefore the same token must apparently contain:

```json
"aud": [
    "https://agents.ceerat.com/mcp",
    "ceerat-api"
]
```

for both components to accept it.

If your Keycloak mapper deliberately issues both audiences, this works.

But it is an implicit architectural requirement, and parts of the README talk as though the same `ceerat-api` token is used throughout.

I would explicitly decide whether you want:

```text
one delegated token with both audiences
```

or:

```text
gateway resource token
        ↓ token exchange
ceerat-api downstream token
```

The first is considerably simpler and may be perfectly appropriate here. Just enforce and test it as part of the OAuth contract.

---

# 8. Connection revocation should probably require confirmation

Your gateway does a particularly good job around dangerous order operations.

You have things like:

```text
prepare
     ↓
preview
     ↓
explicit confirmation
     ↓
dispatch
     ↓
operation tracking
```

And even logout requires confirmation.

But:

```text
revoke_my_agent_connection
```

takes a connection ID and executes immediately.

That's inconsistent, especially because—as discussed above—it can actually revoke an entire shared Keycloak session.

For an agent-driven MCP tool, I would require at least:

```json
{
    "connection_id": "...",
    "confirmed": true
}
```

or preferably a prepare/confirm flow if the session can affect several clients.

MCP `destructiveHint` is useful metadata, but it isn't a security boundary.

---

# 9. Gateway stores more profile PII than it needs

A profile preparation currently stores the entire profile as JSON in PostgreSQL, including potentially:

```text
email
phone
billing address
shipping address
other address details
```

The preparation only needs to live around ten minutes, but cleanup is primarily tied to startup and expired records can remain much longer.

You really only need:

```text
authenticated owner
client/session binding
expected profile version
normalized requested changes
expiry
```

There is no strong reason for the gateway to persist a complete copy of the customer's profile.

This would also help simplify the update model:

```text
gateway stores patch
        ↓
service atomically applies patch
```

instead of:

```text
gateway stores full resource
        ↓
gateway eventually replaces full resource
```

That's both safer for privacy and better for concurrency.

---

# 10. `/readyz` isn't really readiness

The readiness handler checks roughly:

```go
Platform != nil
Validator != nil
Limiter != nil
```

But `grpc.NewClient()` is lazy.

So:

```text
Platform != nil
```

doesn't prove the user service is reachable.

It also doesn't establish that:

```text
Postgres is currently reachable
JWKS can be refreshed
downstream gRPC can make a call
```

The gateway can return:

```text
200 Ready
```

while every meaningful MCP call fails.

I would keep `/healthz` as shallow liveness and make `/readyz` perform inexpensive dependency checks with short deadlines.

Your container health check currently targets `/healthz`, which is fine for **liveness**, but Kubernetes/ECS/etc. should use the real readiness endpoint separately.

---

# 11. Authorization/business logic is leaking into the gateway

Some duplication is unavoidable because the MCP layer needs tool metadata and user-friendly projections.

But there is more business logic here than I would like.

For example, the gateway maintains:

```text
supportedScopes
requiredScope
downstreamMethod
tool catalog metadata
```

independently.

That's how `orders_quote_cart` already drifted.

It also computes concepts such as product `availability` from inventory and independently verifies pricing equations.

For example, the gateway validates something conceptually like:

```text
total =
subtotal
- discount
+ shipping
+ tax
```

That works today.

But imagine you later introduce:

```text
service fee
credit
tip
insurance
adjustment
```

The service can correctly calculate the quote while the gateway starts rejecting it as invalid.

The gateway should enforce **security and structural invariants**.

The service should own **business truth**.

I would aim for:

```text
MCP Gateway
    authentication
    scope enforcement
    argument/schema validation
    confirmation
    idempotency propagation
    safe presentation

User Service
    ownership
    authorization again
    state transitions
    inventory truth
    pricing truth
    domain validation
```

That is the cleanest boundary.

---

# 12. Money briefly falls back to `float64`

Most of the gateway preserves your `Money` abstraction properly.

But cart-clear preparation uses a `float64` total and does approximately:

```go
float64(cart.Total.MinorUnits) / 100
```

That introduces two problems.

It assumes every currency has two fractional digits, and it throws away the currency itself.

You went through the effort of introducing:

```text
Money {
    minor_units
    currency
}
```

in the contracts repo. Keep that representation all the way through gateway state and MCP output.

---

# 13. Preference scopes are exposed before PreferenceService exists

The gateway advertises:

```text
ceerat.preferences.read
ceerat.preferences.write
```

among supported OAuth scopes.

But from the service review we just did:

```text
Preference protobufs      ✓
Preference DB/repository  ✓
Preference migrations     ✓
Preference gRPC handler   ✗
Preference registration   ✗
```

So clients can currently request permissions that can't actually be exercised.

I understand why you might advertise them in advance to avoid forcing another consent cycle later, but from least-privilege and product-consistency perspectives I would advertise scopes only when their corresponding functionality is deployed.

It also creates another example of the three repos getting ahead of one another.

---

# 14. Gateway database lifecycle is weaker than the service repo

The service repo has proper numbered/versioned migration machinery.

The gateway runs things resembling:

```text
CREATE SCHEMA
CREATE TABLE
ALTER TABLE
DELETE expired state
```

during normal application startup.

For an early-stage gateway that's perfectly understandable, but production eventually benefits from the same migration discipline as your service.

Ideally:

```text
deployment migration identity
        ↓
schema migrations
        ↓
gateway runtime identity
        ↓
DML only
```

Then the application doesn't need broad DDL permissions.

Cleanup of expired preparations/connections should also happen periodically rather than primarily when the process restarts.

---

## Things I specifically like in this gateway

There are a number of design choices here I would preserve.

Your tool argument validation is strict, including nested field allowlists. Request bodies are bounded. The gateway forwards the exact authenticated token rather than inventing a weaker internal identity header. The service independently authorizes requests. Access tokens aren't persisted in gateway preparation state. Audit information is redacted. Production state is durable in PostgreSQL rather than relying on memory. Checkout/update/cancel preparation is bound to user/client, expires, uses digest/idempotency concepts, and is atomically transitioned before dispatch. Cart mutations propagate expected versions and idempotency keys. Foreign resources are frequently mapped to `NotFound` rather than revealing their existence. Production public OAuth/MCP URLs require HTTPS. The container runs non-root.

Also, importantly, **the gateway does not expose the dangerous arbitrary `CreateMyOrder.status` functionality I found in the service**. Its order flow primarily works through cart checkout/preparation, so the gateway is not currently providing an easy MCP path to exploit that service-contract mistake. The service still needs fixing because other clients can call it directly.

## My recommended order of work

1. **Encrypt gateway → service gRPC**, because you're forwarding reusable OAuth bearer tokens.
2. **Fix session revocation semantics** so local connection revocation and Keycloak revocation affect the same scope.
3. **Eliminate OAuth policy duplication**, starting with correcting `orders_quote_cart` from `orders.read` to `orders.checkout`.
4. **Resolve the identity model**: OAuth `sub` versus internal CEERAT user ID versus `ceerat_user_id`.
5. **Make profile concurrency atomic in the service contract/database**, rather than depending on the gateway's read-before-update check.
6. **Finish the contracts module-path migration across all three repos**.
7. **Make the audience model explicit and integration-test a real token through gateway → service**.
8. Add confirmation to connection revocation, minimize stored profile PII, improve readiness, then clean up the duplicated business logic and migration/runtime concerns.

One architectural improvement could eliminate several of these problems at once: create a small **generated MCP policy/catalog layer from the protobuf contracts** containing the gRPC method, required OAuth scope, mutability classification, and perhaps confirmation requirement. The gateway could consume that rather than hand-maintaining another security matrix. Given the `orders_quote_cart` mismatch we already found, I think that would pay for itself quickly.

I also attempted the repository test path, but—as with the service repo—the available environment is **Go 1.23.2** while this gateway declares **Go 1.26.2**, so I couldn't complete a runtime `go test ./...` pass. This is therefore a source-level/static review.
