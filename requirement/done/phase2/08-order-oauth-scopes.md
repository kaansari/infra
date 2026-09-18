# Phase 2 PR 08: Order OAuth scopes

Status: **COMPLETE — locally and live validated 2026-09-10**

Validation confirmed that reconciliation and the OAuth policy smoke test pass,
protected-resource metadata advertises all three order scopes, and a fresh
hosted ChatGPT grant receives the distinct requested permissions while retaining
the Phase 1 and product/cart scopes. No order tool was exposed by this PR.

Repository: `infra`  
Depends on: completed product/cart milestone

## Objective

Add optional, least-privilege order scopes to the dedicated ChatGPT and Codex
OAuth clients without granting them to unrelated clients:

```text
ceerat.orders.read
ceerat.orders.checkout
ceerat.orders.write
```

`read` covers quote/list/detail, `checkout` covers product-cart conversion, and
`write` covers bounded pending-order update and cancellation. None grants admin
pricing-rule, arbitrary status, payment, refund, fulfillment, or cross-customer
access.

## Builder gate

Run `ceerat-builder decide-owner`, `evidence request`, `rbac check`, and
`check drift` for the order lifecycle. Use the builder's public-AI security
profile for client assignment, consent, metadata, and redaction boundaries.

## Changes

- Add all three scopes to Keycloak realm reconciliation with clear consent text.
- Assign them as optional scopes only to `ceerat-mcp-chatgpt` and
  `ceerat-mcp-codex-dev`.
- Publish them from MCP protected-resource metadata.
- Extend reconciliation and OAuth-policy smoke tests.
- Do not assign order scopes to deprecated clients. Remove superseded client
  assignments from the canonical reconciliation rather than preserving a
  rollback scope path. Do not add a client secret per end user.


## Authorization semantics

- Publish and test an explicit tool/RPC-to-scope matrix. Scopes are independent;
  `checkout` and `write` do not silently imply `read`, and requesting one order
  scope must not add the others to the grant.
- `ceerat.orders.read` also covers the self-scoped operation-status read used to
  reconcile uncertain order writes; it does not permit mutation or inspection of
  raw idempotency records.
- Validate issuer, audience/resource, signature, expiry/not-before, and granted
  scopes at the gateway before private gRPC dispatch. Do not authorize from an
  ID token, unverified claims, client-supplied role, or request body.
- Refresh-token use must not escalate beyond the originally consented optional
  scopes. Removing/revoking an order scope must take effect on newly validated
  access tokens and be covered by smoke tests.
- Preparation confirmation is not authorization. A confirm request must pass
  current OAuth validation again even when the preparation was created under a
  previously valid grant.

## Tests and acceptance

- Reconciliation is idempotent and never logs admin/client secrets or tokens.
- Authorized clients can request each scope; unregistered clients cannot.
- Existing Phase 1 and product/cart scopes remain unchanged.
- A fresh authorization grant shows distinct order permissions and decoded
  access-token scopes contain exactly the requested grants.
- Missing scopes later map to `INSUFFICIENT_SCOPE`, the exact required scope,
  `request_additional_scope`, and `not_started`.

- Wrong audience/resource, expired tokens, and revoked grants fail before gRPC
  dispatch and never consume a pending preparation.
- Token/scope logs contain only safe metadata (for example client ID, scope names,
  expiry, and request ID), never raw access/refresh tokens or authorization codes.

## Deployment checkpoint

Run live reconciliation before deploying order tools. Then verify
`/.well-known/oauth-protected-resource/mcp` advertises all three order scopes.
Disconnect/reconnect or otherwise obtain a new authorization grant and use
`get_authentication_status` to confirm the decoded scopes. Merely restarting a
chat does not update an existing OAuth grant. If confidential-client settings
change, verify the same secret is loaded by Keycloak, ChatGPT, and Render before
testing code exchange.

Update the infra OAuth runbook and scope inventory in this PR. Do not add order
tools yet.
