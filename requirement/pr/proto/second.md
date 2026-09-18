Yes. The contracts repo is **significantly better now**, and the most serious problems from my first review are fixed. I would not call it completely finished yet, though. A few important authority/design issues remain.

### What you fixed successfully

I verified these directly in the new upload:

| Previous issue                                              | Status                                                |
| ----------------------------------------------------------- | ----------------------------------------------------- |
| Old `ceerat-platform/packages/ceerat-contracts` module path | ✅ Fixed everywhere I checked                          |
| `go_package` pointing to old module                         | ✅ Fixed                                               |
| Self-dependency in `go.mod`                                 | ✅ Fixed                                               |
| Customer-controlled `CreateMyOrder.status`                  | ✅ Fixed and field/name reserved                       |
| AI requests accepting `user_id`                             | ✅ Fixed                                               |
| Job-cart requests accepting `customer_id`                   | ✅ Fixed                                               |
| Self-cart identity selectors                                | ✅ Fixed                                               |
| Gateway `orders_quote_cart` scope mismatch                  | ✅ Canonical policy now uses `ceerat.orders.checkout`  |
| Gateway policy metadata duplicated outside contracts        | ✅ Much better: `GatewayToolPolicies` is now canonical |
| Actual proto RPCs vs `KnownGRPCMethods`                     | ✅ Exactly **154 vs 154**, no missing or extra methods |
| Self-order contract tests                                   | ✅ Much stronger                                       |
| Money for orders/cart/products                              | ✅ Much improved                                       |
| Order lifecycle strings                                     | ✅ Improved with enums                                 |
| Profile optimistic version support                          | ✅ Added `expected_version`                            |

So the core direction is now good.

## 1. `CreateCustomerRequest` still exposes ownership indirectly

This is the most important remaining contract issue.

You changed:

```protobuf
message CreateCustomerRequest {
  reserved 2;
  reserved "user_id";
  Customer customer = 1;
}
```

which looks safe.

But `Customer` itself contains:

```protobuf
message Customer {
    ...
    string user_id = 7;
    auth.User user = 8;
    ...
}
```

So the caller can still send:

```json
{
  "customer": {
    "user_id": "some-other-user"
  }
}
```

Your test:

```go
assertNoFields(
    (&customerpb.CreateCustomerRequest{}).
        ProtoReflect().Descriptor(),
    "user_id",
)
```

only looks at the **top level**. It doesn't inspect nested `Customer`.

More importantly, your default RBAC still gives a `customer`:

```text
/customer.CustomerService/CreateCustomer
```

So this is not merely an admin DTO.

Your README currently says:

> `CreateCustomerRequest` uses the embedded customer owner only for administrative creation flows.

But the security matrix allows customers to call it. Those two statements conflict.

### Better design

I would separate them.

For self-service:

```protobuf
message CreateMyCustomerProfileRequest {
  string first_name = 1;
  string last_name = 2;
  string email = 3;
  string phone = 4;
  Address address = 5;
  Address shipping_address = 6;
  Address billing_address = 7;
}
```

No `user_id`.

For administrative creation:

```protobuf
message CreateCustomerRequest {
    string user_id = 1;
    CustomerCreateInput customer = 2;
}
```

Then only admin/agent gets that RPC.

This follows the pattern you've now established successfully with:

```text
GetMyCart
GetMyOrder
ListMyOrders
GetMyPreference
```

---

# 2. The old `Auth` API is now the biggest authority smell

`auth.proto` still says:

```protobuf
service Auth {
    rpc Get(User) returns (Response) {}
    rpc GetAll(Request) returns (Response) {}
    rpc UpdateProfile(User) returns (Response) {}
}
```

And `User` contains:

```protobuf
message User {
    string id = 1;
    string name = 2;
    string company = 3;
    string email = 4;
    ...
    string role = 7;
    string status = 8;
}
```

So:

```text
UpdateProfile(User)
```

allows the request to contain:

```text
id
role
status
```

Yet the customer default permissions include:

```text
/auth.Auth/Get
/auth.Auth/GetAll
/auth.Auth/UpdateProfile
```

OAuth scopes mitigate some of this—`GetAll`, for example, requires `ceerat.admin.users.read`—but I wouldn't rely on scopes to compensate for an overly broad request contract.

### I'd retire these legacy shapes

Self-service should look more like:

```protobuf
rpc GetCurrentUser(GetCurrentUserRequest)
    returns (CurrentUserResponse);

rpc UpdateMyUserProfile(UpdateMyUserProfileRequest)
    returns (CurrentUserResponse);
```

where:

```protobuf
message GetCurrentUserRequest {}

message UpdateMyUserProfileRequest {
    string name = 1;
    string company = 2;
    int64 expected_version = 3;
    google.protobuf.FieldMask update_mask = 4;
}
```

No:

```text
id
role
status
```

Those belong in `AdminService`.

The customer role also should not contain `GetAll` at all, even if the OAuth scope currently blocks it. Defense-in-depth says both layers should agree.

---

# 3. You partially fixed patch/update semantics, but there is ambiguity

You added a good improvement:

```protobuf
message ProductPatch {
  string id = 1;
  Product product = 2;
  repeated string update_fields = 3;
  int64 expected_version = 4;
}
```

But `UpdateProductRequest` now contains **both**:

```protobuf
message UpdateProductRequest {
  Product product = 1;
  ProductPatch patch = 2;
}
```

Similarly:

```protobuf
message UpdateCustomerRequest {
  Customer customer = 1;
  CustomerProfilePatch patch = 2;
}
```

What happens if both are populated?

```json
{
  "product": {
    "name": "A"
  },
  "patch": {
    "product": {
      "name": "B"
    }
  }
}
```

The contract does not define which wins.

I assume this is a backward-compatibility migration. If so, that's reasonable, but make it explicit.

I would mark the legacy field deprecated:

```protobuf
Product product = 1 [deprecated = true];
ProductPatch patch = 2;
```

and document:

> Exactly one of `product` or `patch` may be populated. New clients MUST use `patch`.

Then eventually reserve field 1 when old clients are gone.

---

# 4. Prefer `FieldMask` over your own `repeated string update_fields`

You currently use:

```protobuf
repeated string update_fields = 3;
```

and:

```protobuf
repeated string update_fields = 9;
```

This works, but protobuf already has a standard mechanism:

```protobuf
google.protobuf.FieldMask update_mask = 3;
```

Advantages include standard semantics, standard tooling, nested paths such as:

```text
shipping_address.city
billing_address.postal_code
```

and less custom validation logic.

Also, your Product comment currently says:

> ProductPatch applies only fields named by `update_mask`.

but the actual field is called:

```text
update_fields
```

So there's already a small documentation/contract mismatch.

---

# 5. Full resource objects are still being used as create inputs

This original issue remains.

For example:

```protobuf
message CreateProductRequest {
  Product product = 1;
}
```

But `Product` contains:

```text
id
created_at
updated_at
effective_price_amount
discount_basis_points
discount_label
inventory
categories
images
version
```

A create caller should not normally control several of those.

Same general issue exists with:

```text
CreateCustomer
CreateService
CreateProductCategory
CreateCatalogDiscount
CreateCompany
CreateJob
```

### Better pattern

Have separate:

```text
Product
CreateProductInput
UpdateProductInput
```

For example:

```protobuf
message CreateProductInput {
    string name = 1;
    string description = 2;
    string sku = 3;
    commerce.Money price = 4;
    string model = 5;
}
```

The server controls:

```text
id
effective price
created_at
updated_at
discount calculations
version
```

This is especially important because these contracts are intended for LLM/MCP clients. The narrower the write DTO, the safer the tool.

---

# 6. `domain.User` still contains Password and Token

Your protobuf correctly removed them:

```protobuf
reserved 5, 6;
```

But the shared domain model still has:

```go
type User struct {
    ID       string
    Name     string
    Company  string
    Email    string
    Password string
    Token    string
    Role     string
    Status   string
}
```

And the mapper deliberately doesn't map Password or Token.

That tells me they're stale.

I would remove:

```go
Password
Token
```

from `domain.User`.

Particularly now that you're using OAuth, a shared business DTO containing password/token fields is a needless security liability.

---

# 7. Time representation is still inconsistent

Calendar is doing this correctly:

```protobuf
google.protobuf.Timestamp created_at = 18;
google.protobuf.Timestamp updated_at = 19;
```

But most other packages still use:

```protobuf
string created_at
string updated_at
string starts_at
string ends_at
string ordered_at
string quote_expires_at
string preview_expires_at
```

I would standardize actual instants to:

```protobuf
google.protobuf.Timestamp
```

Keep date-only business values as dates, e.g.:

```text
schedule_date
start_date
closing_date
```

if they genuinely represent a calendar date and not an instant.

This isn't an emergency migration, but it's worth doing before the APIs become harder to change.

---

# 8. Career salary is still `double`

You successfully eliminated floating-point money in commerce/order/cart.

But `career.proto` still contains:

```protobuf
double salary_min = 9;
double salary_max = 10;
```

and ATSJob has the same thing.

This loses:

```text
currency
pay period
exact representation
```

I'd eventually use something like:

```protobuf
message CompensationRange {
    commerce.Money minimum = 1;
    commerce.Money maximum = 2;
    CompensationPeriod period = 3;
}
```

with:

```text
HOURLY
MONTHLY
ANNUAL
```

This becomes important if your jobs platform handles different countries.

---

# 9. `Product.currency` is now redundant

You have:

```protobuf
string currency = 11;
```

while you also have:

```protobuf
commerce.Money price_amount = 21;
commerce.Money effective_price_amount = 22;
```

and Money itself contains:

```protobuf
string currency = 2;
```

Now the following invalid state is representable:

```text
Product.currency = USD

Product.price_amount.currency = EUR
```

Unless `Product.currency` has a separate documented meaning, I would deprecate it and use `Money.currency` as the only source of truth.

---

# 10. The domain price bucket puts money back into `float64`

The shared domain layer contains:

```go
type ProductPriceBucket struct {
    Min float64
    Max float64
}
```

and:

```go
func ProductPriceBucketFor(price float64)
```

This somewhat defeats your new exact-money design.

Make those minor units:

```go
MinMinorUnits int64
MaxMinorUnits int64
```

or explicitly document that they're normalized whole-unit search boundaries rather than financial values.

---

# 11. Error contracts remain duplicated and inconsistent

You still have seven package-level `Error` messages.

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

This isn't necessarily wrong, but it makes every client implement different error handling.

For RPC failure, I'd primarily use:

```text
grpc status codes
google.rpc.Status
structured details
```

Keep embedded errors mainly where you genuinely support partial/batch success.

That would eliminate a considerable amount of duplicated contract code.

---

# 12. Your canonical RPC inventory is correct today, but CI can still miss a future RPC

I programmatically compared all services in every `.proto`.

Current result:

```text
Actual protobuf RPCs: 154
KnownGRPCMethods:      154

Missing: 0
Extra:   0
```

That's excellent.

But your general test currently essentially does:

```text
KnownGRPCMethods
       ↓
MethodScopePolicies
```

It doesn't globally enumerate **all protobuf service descriptors** and compare those against `KnownGRPCMethods`.

Specialized order/cart/preference tests do descriptor inspection, but not globally.

I would add one global descriptor test:

```text
All protobuf services
        ↓
all methods
        ↓
exactly equals KnownGRPCMethods
```

Then a developer can never do:

```protobuf
rpc BrandNewMethod(...)
```

and forget the security inventory.

Your new `GatewayToolPolicies` is a very good improvement in this area.

---

# 13. Generated protobuf tooling is still old and unpinned

Generated headers still show:

```text
protoc         v3.8.0
protoc-gen-go  v1.28.1
protoc-gen-go-grpc v1.2.0
```

And `Makefile` simply runs:

```make
protoc ...
```

whatever happens to be installed on the developer's machine.

I would strongly recommend pinning this.

Buf would be a good fit:

```text
buf.yaml
buf.gen.yaml
buf.lock
```

Then CI can also give you:

```text
lint
breaking-change detection
deterministic generation
```

Breaking-change checking is particularly valuable now that these contracts are consumed by both the service and gateway.

---

# 14. Shared domain + mapper duplication remains

The architectural question from the first review hasn't changed much.

You still maintain:

```text
protobuf definitions
        ↓
domain structs
        ↓
~large mapper layer
```

For many objects the structures are almost identical.

For example:

```text
Product proto
Product domain
ProductFromProto
ProductToProto
```

Then the service repo has another persistence representation.

So conceptually you still get:

```text
protobuf
   ↓
shared domain
   ↓
service persistence model
```

My preference remains:

```text
contracts repo
    proto
    generated clients
    shared primitives
    security policy metadata

service repo
    business/domain models
    persistence models
```

That would make this contracts repo much more stable and focused.

If several services genuinely share the same domain package, keeping it is defensible—but then it should be treated as a separately governed public API, because changing those structs can break every service.

---

# 15. Minor documentation cleanup

Your README's `Contains` section currently doesn't list:

```text
proto/commerce/
proto/preference/
```

even though both exist.

The inventory still says:

```text
generated_on: 2026-09-08
```

so I'd regenerate it after the current changes if it is intended to be authoritative.

---

## Where I think you are now

I would characterize the contracts repo now as:

**Core security/order/cart contract architecture: good.**

The urgent defects from before have mostly been addressed.

The remaining changes I'd prioritize are:

1. Fix `CreateCustomer` nested `user_id` / separate self-service from admin creation.
2. Retire or redesign legacy `Auth.Get`, `GetAll`, and especially `UpdateProfile(User)`.
3. Make Product/Customer patch APIs unambiguous and deprecate full-resource updates.
4. Stop using full output resources as create inputs.
5. Remove `Password` and `Token` from `domain.User`.
6. Add the global protobuf-descriptor → security-inventory test.
7. Then clean up timestamps, salary Money, redundant currency, errors, and generation tooling.

I would **not block deployment merely because Error messages or timestamps aren't yet perfectly standardized**. But I **would fix the customer ownership issue and legacy `Auth.UpdateProfile(User)` contract before considering the security model fully cleaned up**.

I couldn't execute the repository's normal test suite because this environment has Go 1.23.2 while the repo requires Go 1.26.2, and the needed Go dependencies aren't cached/network-accessible. The structural comparison and source review above are direct static checks; notably, I did independently verify the **154/154 RPC/security inventory match**.
