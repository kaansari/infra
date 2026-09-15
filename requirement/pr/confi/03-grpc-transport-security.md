# Confi PR 03: gRPC transport security

Depends on: Confi PR 02 and OAuth/gRPC PR 04

## Objective

Protect OAuth bearer tokens and gRPC payloads in transit while keeping local
development explicit and constrained.

## Work

- Require TLS 1.2+ for any publicly reachable direct gRPC endpoint.
- Bind plaintext local gRPC only to loopback and make production reject
  plaintext/public listener combinations.
- Document and verify Render private-network protection for gateway-to-service
  traffic. Add TLS or mTLS when traffic can cross an untrusted boundary.
- Configure hostname verification, trusted roots, certificate renewal, minimum
  protocol/cipher policy, and failure behavior.
- Keep OAuth validation, scopes, RBAC, and ownership mandatory under TLS; TLS is
  not authorization.
- Add probes for valid TLS, wrong host, untrusted/expired certificate, plaintext
  downgrade, and oversized metadata.

## Acceptance

- Public gRPC cannot be reached over plaintext.
- Valid TLS direct gRPC OAuth call succeeds.
- Invalid certificate and downgrade attempts fail before bearer-token handling.
- Private MCP-to-gRPC transport controls are documented and verified.
- No private key or bearer token appears in logs/evidence.

## Out of scope

Browser TLS configuration, custom certificate UI, and using mTLS as an end-user
identity replacement.

