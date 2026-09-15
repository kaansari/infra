# Confi PR 04: Administrative MFA and session policy

Depends on: Confi PR 01

## Objective

Protect Keycloak and CEERAT administrative access with strong authentication,
separate clients, and bounded sessions.

## Work

- Require MFA for Keycloak realm/master administrators and CEERAT admin users.
- Prefer phishing-resistant WebAuthn/passkeys; permit TOTP as documented
  recovery-compatible fallback if necessary.
- Use separate administrative OAuth clients and redirect allowlists.
- Apply shorter admin access/idle/max session limits and appropriate reauth for
  sensitive operations.
- Disable dormant/default administrators and prohibit shared admin accounts.
- Store recovery codes securely and test recovery without weakening MFA.
- Alert on repeated admin login failure, MFA reset, role escalation, client
  secret changes, and realm policy changes.

## Acceptance

- Admin login without required MFA cannot complete.
- Customer/agent OAuth clients cannot obtain admin authority.
- Current PostgreSQL RBAC remains authoritative after authentication.
- Admin logout/session revocation works and produces sanitized audit events.

## Out of scope

Granting roles from Google claims, shared accounts, SMS as the preferred factor,
and browser application redesign.

