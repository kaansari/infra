# Phase 2 PR 03: Explicit self-cart gRPC contract

Repository: `contracts-repo`  
Depends on: Phase 2 PR 02  
Domain owner: `service.ServiceManager`

## Objective

Add explicit customer-self-service cart RPCs so an authenticated ChatGPT user
can reach their cart without any request field selecting a user or customer:

```text
GetMyCart
AddMyCartItem
UpdateMyCartItem
RemoveMyCartItem
ClearMyCart
```

Delete the existing customer-ID-shaped `GetCart`, `AddCartItem`,
`UpdateCartItem`, `RemoveCartItem`, and `ClearCart` RPCs and request messages.
This is a new system: no alternate cart relationship or second ownership path
is retained. Reserve removed protobuf field numbers/names to prevent accidental
wire-field reuse, but do not keep the removed methods callable.

## Request contracts

`GetMyCartRequest` is empty. Mutation requests contain only the required
product/variant/item identifiers, bounded quantity or notes where applicable,
an idempotency key, and expected cart version. They must never contain
`customer_id`, `user_id`, tenant, role, scope, price, discount, inventory
override, totals, or another authority-bearing field. `Cart.version` is returned
after every successful read or mutation.

## Security and contract cleanup

- Add all five protected methods to `KnownGRPCMethods`.
- Grant them only to the `customer` role initially; never add them to
  `DefaultPublicMethods`.
- Remove all five old cart methods from `KnownGRPCMethods`, role permissions,
  contract inventory, and generated descriptors.
- Preserve interceptor order `JWT -> RBAC -> logging -> handler`.
- Regenerate Go protobuf/gRPC code and update contract/service inventories.

## Builder-agent gate

Run the common workflow in [README](README.md), plus:

```bash
ceerat-builder inventory contracts --output json
ceerat-builder impact contract service.ServiceManager --add "self-scoped cart RPCs" --output json
ceerat-builder proto-commands service --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder evidence request "GetMyCart AddMyCartItem UpdateMyCartItem RemoveMyCartItem ClearMyCart" --output json
```

## Acceptance

Descriptor tests prove the five new methods exist and the five old methods do
not. Security tests prove the new RPCs are protected, customer-authorized, and
not public. Generated code is reproducible and contract tests/build/vet pass.
Temporary contract/service inventory drift is recorded
until PR 04 supplies the implementation; it is not silently accepted at the
Phase 2 aggregate gate.

This PR adds no runtime behavior and does not expose gRPC publicly.

## Contract integration tests

- Compile generated clients against service and gateway modules.
- Use an in-process gRPC server to prove authenticated customer context reaches
  every new method and unauthenticated calls fail before handler execution.
- Assert descriptors contain only the new self-cart RPC names.
- Run contract/service drift after generated code and inventories are updated.
- Prove the logging interceptor observes every new full gRPC method name while
  request messages expose no identity selector or credential.
