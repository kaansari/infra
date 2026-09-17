I reviewed the repository as a contract/API codebase, not just individual files. There are some good patterns here, but I found several things I would fix—one of them is **critical**.

### Main findings

| Severity     | Finding                                                                                      | Why it matters                                                                                                                                         |
| ------------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Critical** | Module/import path is split between two versions of the same contracts repo                  | Can compile against an older copy of itself, create incompatible Go types, hide contract drift, and potentially cause duplicate protobuf registrations |
| **High**     | `CreateMyOrderRequest` lets a customer specify `status`                                      | A self-service caller should never choose an authoritative order lifecycle state                                                                       |
| **High**     | Several customer/self APIs still accept `customer_id` / `user_id`                            | Creates horizontal-authorization risk and contradicts the safer `GetMy...` pattern                                                                     |
| **High**     | gRPC methods are manually duplicated across proto + KnownGRPCMethods + RBAC + OAuth policies | Easy to forget one location; current global test does not prove every actual RPC has a policy                                                          |
| **High**     | Create/update requests reuse full resource objects                                           | Clients can send server-owned fields and updates have ambiguous proto3 presence semantics                                                              |
| **Medium**   | Domain DTOs + ~884 lines of mappers largely duplicate protobuf models                        | Three representations must stay synchronized and some have already drifted                                                                             |
| **Medium**   | Error contracts are repeated and inconsistent                                                | Seven `Error` definitions use different shapes/types                                                                                                   |
| **Medium**   | Time representation is inconsistent                                                          | Some APIs use `google.protobuf.Timestamp`, most use arbitrary strings                                                                                  |
| **Medium**   | Money handling is inconsistent outside commerce/order                                        | Salary uses `double`; price buckets use `float64`; Product duplicates currency                                                                         |
| **Medium**   | `ServiceManager` has too many bounded contexts                                               | Catalog, images, discounts, customer connections, and carts are all mixed together                                                                     |
| **Medium**   | Code generation is old and not reproducible                                                  | Generated files use old protoc/plugins and Makefile doesn't pin tools                                                                                  |
| **Medium**   | README/inventory are already stale                                                           | The documentation intended to prevent contract duplication is itself out of sync                                                                       |

## 1. The module-path problem should be fixed first

This is the most important problem I found.

Your `go.mod` says:

`go.mod:1`

```go
module github.com/kaansari/ceerat-contracts
```

But immediately afterward it depends on the **old version of itself**:

`go.mod:7`

```go
github.com/kaansari/ceerat-platform/packages/ceerat-contracts ...
```

And your mapper imports that old module:

`mapper/mapper.go:4-9`

```go
"github.com/kaansari/ceerat-platform/packages/ceerat-contracts/domain"
...
"github.com/kaansari/ceerat-platform/packages/ceerat-contracts/proto/order"
```

All ten `.proto` files also still declare the old `go_package`.

Even worse, generated local code does this:

`proto/order/order.pb.go:11-13`

```go
commerce "github.com/kaansari/ceerat-platform/packages/ceerat-contracts/proto/commerce"
customer "github.com/kaansari/ceerat-platform/packages/ceerat-contracts/proto/customer"
service "github.com/kaansari/ceerat-platform/packages/ceerat-contracts/proto/service"
```

So a consumer can import:

```text
github.com/kaansari/ceerat-contracts/proto/order
```

but that local order package contains fields whose Go types come from:

```text
github.com/kaansari/ceerat-platform/packages/ceerat-contracts/proto/service
```

instead of the new module.

That is a split-brain contract module.

The Git history confirms how it happened: when the module was changed from the monorepo path to `github.com/kaansari/ceerat-contracts`, the old module was added as a dependency instead of updating all internal imports.

I would make this **P0**: choose one canonical module path. Assuming the standalone repo is canonical, change every `go_package`, mapper import and test import to `github.com/kaansari/ceerat-contracts/...`, remove the old self-dependency, regenerate every protobuf file, then `go mod tidy`.

I would also add a CI check that fails if the old path ever appears again.

## 2. I found a potentially dangerous self-order contract

`proto/order/order.proto:140-147`:

```protobuf
message CreateMyOrderRequest {
  string schedule_date = 1;
  string start_date = 2;
  string due_date = 3;
  string notes = 4;
  repeated CreateOrderServiceInput services = 5;
  OrderStatus status = 6;
}
```

The customer role explicitly gets `CreateMyOrder`, and OAuth classifies it as checkout.

A customer should not be able to submit:

```text
ORDER_STATUS_CONFIRMED
ORDER_STATUS_IN_PROGRESS
ORDER_STATUS_COMPLETED
```

as part of creating their own order.

The server may currently ignore this field, but the **contract should not expose authority that the caller does not own**.

Remove `status = 6` and reserve both the name and field number:

```protobuf
reserved 6;
reserved "status";
```

The server should establish the initial status.

Interestingly, your self-order security test checks many self-order RPCs for authority-bearing fields, but `CreateMyOrder` is missing from that test. I would add it immediately.

## 3. Apply your excellent `MyCart` pattern everywhere

Your self-cart API is one of the strongest parts of this repo. For example:

```protobuf
message GetMyCartRequest {
  reserved 1;
  reserved "customer_id";
}
```

Ownership comes from authenticated context. Excellent.

But other contracts don't follow that rule.

For example, career job-cart operations exposed to customers accept:

`career.proto:618-645`

```protobuf
message GetJobCartRequest {
  string customer_id = 1;
}

message AddJobToCartRequest {
  string customer_id = 1;
  ...
}
```

AI thread requests repeatedly accept `user_id`, even though both customers and agents have thread permissions.

Customer/service connection requests similarly accept `customer_id`.

And `CreateCustomerRequest` contains both a full Customer and another `user_id`.

Even if every service currently checks ownership correctly, this creates unnecessary opportunities for an authorization mistake.

I would establish one rule:

**Self-service RPCs never receive the owner's user/customer ID. Identity always comes from OAuth/authenticated context.**

Then use names like:

```text
GetMyJobCart
AddMyJobToCart
GetMyThreads
AppendMyThreadMessage
ListMyConnections
```

Keep explicit `user_id/customer_id` only in genuinely administrative/agent APIs.

## 4. Your security policy is duplicated too many times

Every RPC effectively exists in several separate places:

```text
.proto service declaration
security.KnownGRPCMethods
DefaultRolePermissions
MethodScopePolicies
sometimes a specialized contract test
docs/contract-inventory.json
```

You currently have **154 RPCs** in `KnownGRPCMethods`.

The dangerous part is that this test:

`oauth_scope_policy_test.go:9`

iterates over `KnownGRPCMethods` and checks that every **known** method has a policy.

But it does not globally enumerate every service descriptor and prove that every RPC from the `.proto` files appears in `KnownGRPCMethods`.

So this sequence is possible:

```text
Developer adds NewRPC to foo.proto
Developer forgets KnownGRPCMethods
Developer forgets MethodScopePolicies
Existing general policy test still passes
```

Some specialized tests catch this for preference/cart/order, but not all 154 methods.

I would make one structure the source of truth.

For example, `MethodPolicies` could contain scope + allowed roles, and `KnownGRPCMethods` could be derived from it. Separately, a descriptor-based test should enumerate **all generated protobuf services/RPCs** and compare them against policy.

Even better, after modernizing the gRPC generator, use generated `FullMethodName` constants instead of repeating raw strings like:

```go
"/order.OrderManager/UpdateMyOrder"
```

everywhere.

## 5. Don't use output/resource objects directly as write inputs

You do this repeatedly:

```protobuf
message CreateProductRequest {
  Product product = 1;
}

message UpdateProductRequest {
  Product product = 1;
}
```

But `Product` contains things such as:

```text
id
created_at
updated_at
effective_price_amount
discount fields
inventory
categories
images
```

Some are clearly server-owned or calculated.

The same pattern appears with Customer, Company, Job, pricing rules, etc.

That makes authority ambiguous and makes updates particularly problematic because proto3 scalar values cannot tell you whether the caller omitted a value or intentionally set it to its zero value.

I would use:

```text
CreateProductInput
UpdateProductInput
```

and either modern `optional` fields or `google.protobuf.FieldMask` for patch semantics.

Your `MyOrderUpdatePatch` already demonstrates the right idea.

## 6. The domain + mapper layer deserves reconsideration

You currently have approximately:

```text
411 lines domain/models.go
884 lines mapper/mapper.go
~2,500 lines source .proto
```

A lot of the domain structs are almost exact copies of protobuf resources.

That means a Product change can require:

```text
service.proto
domain.Product
ProductFromProto
ProductToProto
mapper tests
contract inventory
```

Yet newer domains such as preference/calendar/career don't consistently have corresponding domain DTOs.

So the architecture is halfway between:

**A. protobuf is the shared service DTO**, and

**B. every service has transport-independent domain models.**

I would choose one.

For a standalone `ceerat-contracts` repository, I lean toward keeping it focused on **transport/API contracts**, while actual domain entities live within their owning services. Otherwise the contracts repository starts becoming a shared-domain monolith.

There's already evidence of stale domain state. `domain.User` still contains:

```go
Password string
Token    string
```

while `auth.proto` deliberately reserves the old fields 5 and 6.

The mapper doesn't map Password or Token either.

I would remove those two fields from the shared domain model. Keeping secrets in a broadly shared `User` DTO is also a security smell.

## 7. Money has a few inconsistencies

You made a very good move introducing:

```protobuf
commerce.Money {
    int64 minor_units
    string currency
}
```

But some older code bypasses it.

`career.Job` still has:

```protobuf
double salary_min = 9;
double salary_max = 10;
```

with no currency or salary period.

I would eventually replace that with something like a salary range containing `Money`, plus period such as hourly/yearly.

Also Product has:

```protobuf
string currency = 11;
commerce.Money price_amount = 21;
```

So there are now potentially two currencies for one Product.

I'd remove the standalone `Product.currency` unless it has a clearly different meaning.

And `domain.ProductPriceBucket` goes back to:

```go
Min float64
Max float64
```

despite the rest of the system moving away from floating-point money. That should operate on integer minor units/Money instead.

## 8. Error handling should be standardized

There are seven separate `Error` messages.

Most use:

```protobuf
int32 code
string description
```

AI uses:

```protobuf
string code
string description
```

Preference uses:

```protobuf
string field
string message
string code
```

For normal RPC-level failures, gRPC status codes should generally be authoritative, with structured `google.rpc.Status` details when needed.

For batch/partial operations, an application-level result/error structure makes sense.

I would not keep adding another package-specific `Error` message every time you create a package.

## 9. Time handling has drifted

Calendar and preference correctly use:

```protobuf
google.protobuf.Timestamp
```

But the majority of contracts still use arbitrary strings:

```text
created_at
updated_at
starts_at
ends_at
ordered_at
quote_expires_at
preview_expires_at
```

I'd standardize timestamps on `google.protobuf.Timestamp`.

Actual date-only concepts such as `schedule_date` can remain ISO dates or use an explicit date type.

## 10. `ServiceManager` is too broad

It currently has **33 RPCs** covering:

```text
services
products
categories
images
discounts
customer/service connections
customer cart
```

The security scopes already expose the conceptual split: some operations use `ceerat.products.*`, while CustomerService operations use `ceerat.connections.*`.

That is a strong sign that these are separate bounded contexts.

Longer term I would move toward something like `CatalogService`, `ConnectionService`, and `CartService`. Don't break existing RPCs just to rename them; migrate this with versioning.

`career.proto` has the opposite situation: four reasonably separated services but all packed into one 828-line file. Those could be separate `.proto` files while retaining the same career package.

## 11. There is contract duplication I would *not* remove

Messages such as:

```text
GetOrderResponse
UpdateOrderStatusResponse
CancelMyOrderResponse
```

may have identical `{ order, errors }` layouts.

I would **not** aggressively combine them just to be DRY.

Independent RPC response messages can evolve independently, which is valuable in protobuf APIs.

The exact duplicate:

```text
service.ProductSearchFacet
career.JobSearchFacet
```

and their identical facet-value messages are better candidates for a small shared `search` contract.

So I'd deduplicate **shared concepts**, not every structurally similar message.

## 12. Tooling/documentation also needs cleanup

Generated code says roughly:

```text
protoc 3.8.0
protoc-gen-go v1.28.1
protoc-gen-go-grpc v1.2.0
```

and `make proto` doesn't pin any of them.

That means two developers can run `make proto` and generate different output.

I would strongly consider Buf or another pinned generation setup, plus protobuf linting and breaking-change checks.

Your README and `contract-inventory.json` are already stale. For example, the inventory still says:

```text
github.com/kaansari/ceerat-platform/packages/ceerat-contracts
```

for the module, even though `go.mod` says otherwise. It also contains obsolete fields such as `Price` and `DiscountPercent`. README doesn't list the new preference or commerce packages/services either.

That inventory should ideally be **generated from the contracts**, not manually maintained.

### What I would change first

I would do this in three passes. **First**, repair the module identity completely: one Go module path, update all `go_package`s/imports/tests, remove the self-dependency, regenerate protobuf code, then add a CI check against the old path. **Second**, fix authority/security contracts: remove `CreateMyOrder.status`, convert customer-facing `customer_id/user_id` APIs to identity-derived self APIs, and generate/verify the global RPC security inventory. **Third**, clean architecture incrementally: separate write inputs from resource outputs, standardize timestamps/errors/money, decide whether the shared domain+mapper layer should continue to exist, and split the oversized service boundaries.

There are also several things I would **keep**: your retired-field `reserved` usage is good, `commerce.Money` is a good direction, the `MyCart` identity-derived pattern is strong, the order idempotency/version/fingerprint design is good, and the preference contract's typed `oneof` is much cleaner than arbitrary JSON.

I attempted to run the full Go tests as part of the review, but this execution environment has Go 1.23.2 while your repo pins Go 1.26.2, and external module downloads are unavailable here. So the findings above are from direct static/source inspection rather than a successful runtime test pass.

The **module-path/self-dependency issue and `CreateMyOrder.status` are the first two things I would fix before adding any more contracts**.
