# Preference MCP read tools implementation plan

Implement PR06 inline in the existing gateway, preserving existing tool order and envelopes.

1. Add failing inventory/strict-schema tests for five authenticated, read-only tools.
2. Extend canonical gateway policies and vendor the existing preference contract.
3. Add a narrow private gRPC reader, closed flat inputs validated by contract validators, and explicit public projections. Keep exact numeric values, omit owner/database/definition metadata, and treat text as untrusted data. TXSE receives compact presentation/query defaults only.
4. Verify strict decoding, scopes/challenges, revocation, limits, failures, malformed responses, safe audit metadata, prompt text, and a real gRPC two-user boundary. Test consumer precedence against a mock TXSE response.
5. Update discovery, catalog snapshots and operational documentation. Run GOWORK=off tests/build plus builder app/context/drift checks, review the diff, and record results.

Hosted deployment remains gated on authenticated private read smoke, protected-resource scopes/live tools/list, and hosted app schema refresh. Local completion does not assert these live gates passed.

## Execution ledger

- Inventory test observed failing with zero preference tools, then passing with five.
- Ruling: preserve existing gateway Service mocks by adding a narrow optional PreferenceReader interface. Missing adapter fails closed; the concrete client implements only the five read forwards on that surface.
- Ruling: use existing contract validators and vendored preference package plus cached protobuf timestamp compatibility alias; do not refresh unrelated contracts.
- Ruling: real-gRPC ownership fixture verifies bearer forwarding and boundary isolation; private production SQL matching remains in its owning service's tests. Hosted acceptance stays explicitly outstanding.
- All implementation tasks complete. Canonical policies, schemas/projections, discovery, inventory, README and regression/integration tests updated.
- Required gateway tests/build, full race suite, changed-package race rerun, canonical contract checks and all builder gates passed.
- Fresh review identified a weak TXSE precedence assertion and missing inventory domain mapping. Both corrected and verified by the reviewer; no remaining review blockers.
