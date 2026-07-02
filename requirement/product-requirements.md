# Product Catalog, Cart, Checkout, and Payment Setup Requirements

## Goal

Create a customer-facing Products area in Ceerat where authenticated customers can search/browse products, add products to a cart, checkout the cart into an order, and reach a payment setup step that can later integrate with one or more payment gateways.

This is a requirement document first. It is also a Codex execution prompt at the bottom for the implementation pass.

## Builder-Agent Ownership Decision

Use `ceerat-platform-builder-agent` before coding and treat its output as factual context, not final design.

Builder evidence found existing product/cart/order ownership:

- Product catalog and customer cart already belong to `service.ServiceManager`.
- Checkout/order creation already belongs to `order.OrderManager`.
- The backend implementation owner is `services-repo/services/ceerat-user-service`.
- Contract owners are:
  - `contracts-repo/packages/ceerat-contracts/proto/service/service.proto`
  - `contracts-repo/packages/ceerat-contracts/proto/order/order.proto`
- Existing app owner for the browser UX is `apps-repo/apps/ceerat-customer-ui`.

Do not create a new backend service process or unrelated proto package unless live code inspection proves the existing `service` and `order` domains cannot safely support the requirements. Prefer extending the existing service/order domains.

## Current Context

Workspace layout:

- Infra and requirement docs:
  - `infra/`
  - `infra/requirement/product-requirements.md`
- Contracts:
  - `../contracts-repo/packages/ceerat-contracts`
- Backend service:
  - `../services-repo/services/ceerat-user-service`
- Customer portal:
  - `../apps-repo/apps/ceerat-customer-ui`
- App surface inventory:
  - `../apps-repo/docs/app-surface-inventory.json`
- Service inventory:
  - `../services-repo/docs/grpc-service-inventory.json`
- Contract inventory:
  - `../contracts-repo/docs/contract-inventory.json`

Existing contract concepts from builder inventory:

- `service.Product`
- `service.Cart`
- `service.CartItem`
- `service.ServiceManager/CreateProduct`
- `service.ServiceManager/GetProduct`
- `service.ServiceManager/ListProducts`
- `service.ServiceManager/UpdateProduct`
- `service.ServiceManager/DeleteProduct`
- `service.ServiceManager/GetCart`
- `service.ServiceManager/AddCartItem`
- `service.ServiceManager/UpdateCartItem`
- `service.ServiceManager/RemoveCartItem`
- `service.ServiceManager/ClearCart`
- `order.OrderManager/CreateMyOrder`
- `order.OrderManager/GetMyOrder`
- `order.OrderManager/ListMyOrders`

Existing RBAC inventory already includes customer access for product list/detail and cart operations, and customer order access for self-service order flows. Confirm this in live code before relying on it.

## Product Requirements

### Customer Product Catalog

Customers must be able to browse and search active products in `ceerat-customer-ui`.

Required pages:

- `GET /customer/products`
  - Product list/search page.  Use typsense for search just as the career page uses it, upgrade typsense to include product domain.
  - Uses existing customer portal navigation patterns.
  - Should be reachable from the customer home/workspace area.
- `GET /customer/products/{id}`
  - Product detail page.
  - Shows product metadata and add-to-cart controls.  make sure to include product variants like model, size, color and price.
- `GET /customer/products/cart`
  - Customer cart review page.
- `GET /customer/products/checkout`
  - Checkout review and order creation page.
- `GET /customer/products/checkout/payment`
  - Payment setup/placeholder page after order creation.
  - Shows the order total, order id/number, and payment status placeholder.

Search/list filters:

- Keyword query over product name, SKU, and description.
- Active-only products by default for customers.
- Products may belong to multiple categories.
- Product contracts use normalized category assignments only; do not add a legacy scalar category field or fallback query.
- Categories support parent/child relationships and must reject cycles.
- Selecting a parent category includes products assigned to its descendants.
- Typesense and database fallback search must expose equivalent facets for:
  - category
  - model
  - size
  - color
  - price
  - availability
- Price filters use fixed non-overlapping buckets: `0-50`, `50-100`, `100-200`, `200-500`, `500-1,000`, `1,000-2,000`, and `Over 2,000`.
- Render filter options and result-count chips using the customer career search pattern.
- During development, Typesense product-index rebuilds delete and recreate the collection from the current schema.
- Sort options:
  - relevance/default
  - name
  - price low to high
  - price high to low
  - newest

List result display:

- Product name
- SKU
- Short description
- Price
- Active/in-stock availability if supported
- Add-to-cart button
- Detail link

Customer-facing UI text must avoid internal terms like "gRPC", "ServiceManager", "proto", "cart item entity", or "payment intent table".

### Product Cart

Customers must be able to manage a cart containing products.

Cart behavior:

- Customer identity must be derived from authenticated JWT/session context.
- Browser must not submit trusted `customer_id` or `user_id`.
- Customers can add a product to their own cart.
- Customers can update quantity.
- Customers can remove an item.
- Customers can clear the cart.
- Cart totals must be calculated server-side.
- Cart lines must snapshot product price at add/update time if the existing model supports it. If it does not, add this as part of the service implementation.

Cart UI:

- List product lines with quantity controls.
- Show subtotal and total.
- Show empty cart state.
- Provide "Continue shopping" and "Checkout" actions.
- Keep layout usable on mobile widths.

### Checkout and Order Creation

Checkout must convert the customer's cart into an order through backend service APIs.

Backend requirement:

- Add or reuse a self-service checkout RPC.
- Preferred direction:
  - Add `CheckoutCart` or `CreateOrderFromCart` to the correct existing domain after code inspection.
  - If cart ownership and pricing live in `service.ServiceManager`, the cart checkout operation can live there and call/coordinate order creation internally only if consistent with existing architecture.
  - If order creation owns checkout finalization, add a customer-safe `CreateMyOrderFromCart` method to `order.OrderManager`.
- Do not make the browser construct final order totals.
- Do not trust cart item prices submitted by the browser.
- Backend must read the authenticated customer's current cart, validate products, calculate totals, create an order, and clear or mark the cart as checked out atomically.
- Checkout must be idempotency-aware. At minimum, accept a client-generated idempotency key or prevent duplicate checkout from the same cart version.
- Empty carts must be rejected.
- Inactive/deleted products must be rejected or reported clearly during checkout.

Order behavior:

- Created order status should be one of:
  - `pending_payment` if adding a new status is acceptable and reflected everywhere
  - otherwise the closest existing status, with a clear payment status field added separately
- Order detail pages must be able to show product line items, not only service line items.
- Existing service-line order flows must continue working.

### Payment Setup

Payment gateway integration is not required in the first implementation, but the domain must be ready for it.

Add a payment setup abstraction that can later connect to Stripe, Adyen, PayPal, or another provider without changing the checkout UI contract.

Backend payment setup requirements:

- Add payment model/contract fields only as needed for a placeholder flow.
- Do not store card numbers, CVV, bank account numbers, or other raw payment instruments.
- Do not collect payment credentials in the first pass.
- Payment gateway configuration must come from environment/config, never from browser input.
- Add a provider-neutral payment setup API shape such as:
  - `CreatePaymentSession`
  - `GetPaymentSession`
  - `ConfirmPaymentSession`
- First implementation can return a placeholder/manual provider response:
  - payment session id
  - order id
  - amount
  - currency
  - status such as `payment_setup_required`, `pending`, `not_configured`
  - provider name such as `manual` or `none`
- The response must not include secrets unless they are intentionally client-safe gateway tokens in a later gateway integration.

Customer UI payment setup:

- Show a payment setup page after checkout.
- Clearly state payment gateway integration is pending/configuration-based.
- Show order number, amount, and current payment status.
- Provide a path back to order detail.
- Do not render fake card forms unless a real gateway client integration is implemented.

### Admin/Agent Product Management

The immediate customer requirement is browsing/search/cart/checkout. Product management may already exist in contracts but may not have a complete UI.

Implementation should ensure seeded or test products exist so the customer product flow is demonstrable.

Admin/agent product creation can be:

- implemented through existing `service.ServiceManager/CreateProduct` and admin/agent tools if already present, or
- deferred if there is a seed/test fixture path and customer catalog works.
- create 10 random see products for testing and intial setup.
- Allow batch product upload.  Create a batch product upload api.


Do not block customer catalog implementation on a polished admin product-management UI unless live code inspection shows no other product data creation path.

### Catalog Media, Discounts, and Closeout

- Products and services support up to 10 JPEG, PNG, WebP, or GIF images of at most 5 MB each.
- Image binaries are stored separately from catalog metadata; normal list/search calls must not load image bytes.
- The first uploaded image is the primary thumbnail. Agents can choose another primary image or delete images.
- Customer product cards show the primary image and product detail shows all images.
- Discount scopes are `store`, `service`, `product`, `variant`, and `cart_item`.
- Discount rules may be ad hoc or scheduled with optional RFC3339 start/end timestamps.
- Discounts do not stack. Precedence is cart item, variant, product/service, then store; the strongest active rule wins within a scope.
- Cart and checkout pricing must re-evaluate active rules server-side.
- Discounts above 70 percent display a red Clearance tag.
- Products can be marked Closeout permanently or by an active closeout discount rule.
- Agent catalog operations must support image upload/primary/delete and discount create/delete without exposing image bytes or trusted pricing calculations to the browser.

### Order Tax, Shipping, and Discounts

- Order pricing rules use the existing `order.OrderManager` boundary.
- Rule kinds are `tax`, `shipping`, and `discount`; calculations may be fixed or percentage based.
- Rules support active state, priority, optional RFC3339 start/end dates, minimum subtotal, and country/state targeting.
- Discount rules may be automatic or require a case-insensitive code.
- Checkout always offers `Free` ($0), `Standard` ($5), `Three day` ($10), and `Next day` ($20) shipping. A matching configured rule with the same name overrides that built-in option.
- Shipping rules support a free-shipping threshold and customer selection among eligible methods.
- Tax defaults to 9 percent when no matching configured tax rule exists. Configured state rules take precedence over broader country rules.
- Customers store separate profile, shipping, and billing addresses. Complete shipping and billing addresses are required before quoting or checkout; there is no profile-address fallback.
- Cart quotes and checkout tax use the resolved shipping address, never the billing address or a browser-supplied tax region.
- Checkout snapshots resolved shipping and billing addresses on the order so later profile edits do not alter historical fulfillment or tax records.
- This is a new-system contract: missing address snapshots and stale shipping method identifiers are rejected rather than remapped for backward compatibility.
- Tax rules may include shipping in the taxable amount.
- The server calculates `subtotal - order discount + shipping + tax`, rounds money to cents, and snapshots all labels, rates, selections, and amounts on the order.
- Customer checkout must quote and finalize through the same backend calculator. Browser-supplied totals, customer ids, and addresses are never trusted.
- Customers can quote only their own cart. Agents/admins can manage pricing rules and reprice user-scoped orders.
- The customer checkout UI shows shipping selection, discount-code feedback, and a complete price breakdown.
- The agent Orders UI provides pricing-rule management and an order repricing control.

## Architecture Requirements

### Contracts

Use existing contract packages when possible:

- Extend `proto/service/service.proto` for product search/list/cart/payment-session setup if ownership fits.
- Extend `proto/order/order.proto` for checkout-to-order/order-product-line support if ownership fits.
- Update generated Go protobuf files.
- Update shared domain models and mappers.
- Update:
  - `contracts-repo/packages/ceerat-contracts/security/grpc_methods.go`
  - default role permissions for protected methods
  - public allowlist only if a method is intentionally public, which is not expected here
  - `contracts-repo/docs/contract-inventory.json`

Do not create public product/cart/checkout/payment RPCs. The customer portal is authenticated.

### Backend Service

Implement in `services-repo/services/ceerat-user-service`.

Expected service areas:

- Product/catalog/cart:
  - `services-repo/services/ceerat-user-service/services`
- Orders:
  - `services-repo/services/ceerat-user-service/orders`
- Shared persistence models:
  - `services-repo/services/ceerat-user-service/internal/models`
- Service registration/migrations:
  - `services-repo/services/ceerat-user-service/main.go`

Backend must:

- Use repository methods for DB work.
- Use transactions for checkout/order creation/cart clearing.
- Enforce auth and customer ownership at handler/repository boundaries.
- Keep Postgres as source of truth.
- Avoid direct database access from apps.
- Avoid direct browser-to-gRPC calls.
- Use structured errors compatible with existing app clients.
- Preserve existing service catalog and order workflows.

### Customer UI

Implement in `apps-repo/apps/ceerat-customer-ui`.

The customer UI must:

- Add a Products area with career/orders-style subnavigation.
- Use same-origin HTTP routes only.
- Have app server API wrappers that forward the customer's JWT/session to backend gRPC.
- Avoid direct database, direct gRPC from browser, or direct payment gateway calls until a real gateway integration is added.
- Keep mobile layouts usable.
- Keep routes authenticated.
- Update `apps-repo/docs/app-surface-inventory.json`.

Suggested browser routes:

- `GET /customer/products`
- `GET /customer/products/{id}`
- `GET /customer/products/cart`
- `GET /customer/products/checkout`
- `GET /customer/products/checkout/payment`

Suggested API routes:

- `GET /api/customer/products`
- `GET /api/customer/products/{id}`
- `GET /api/customer/products/cart`
- `POST /api/customer/products/cart/items`
- `PATCH /api/customer/products/cart/items/{id}`
- `DELETE /api/customer/products/cart/items/{id}`
- `DELETE /api/customer/products/cart`
- `POST /api/customer/products/checkout`
- `POST /api/customer/products/orders/{id}/payment-session`
- `GET /api/customer/products/payment-sessions/{id}`

Adapt route names to existing customer UI conventions if the codebase already has closer patterns.

## Security Requirements

- All product/cart/checkout/payment setup endpoints are authenticated unless explicitly documented otherwise.
- Customers can only access their own cart, checkout session, payment session, and order.
- Do not trust `customer_id`, `user_id`, totals, unit prices, product active status, or payment provider settings from browser input.
- Do not make cart/checkout/payment RPCs public.
- Do not expose payment gateway secrets to browser or logs.
- Do not store raw payment credentials.
- Do not log JWTs, auth headers, payment secrets, or full provider responses containing secrets.
- Use backend RBAC and ownership checks. UI visibility is not authorization.
- Admin/agent product management must remain RBAC-protected.

## Data Model Requirements

Confirm existing models first. Add only missing fields/tables.

Likely existing or needed:

- `products`
  - id
  - name
  - description
  - sku
  - price
  - active
  - created_at
  - updated_at
- `carts`
  - id
  - customer_id
  - subtotal
  - total
  - created_at
  - updated_at
- `cart_items`
  - id
  - cart_id
  - item_type
  - product_id
  - service_id
  - quantity
  - unit_price
  - total_price
  - notes
  - created_at
  - updated_at
- order product support, if missing:
  - either add product fields/lines to existing order line model, or
  - create an `order_items`/`order_products` model consistent with current order service style
- payment sessions, if adding placeholder payment setup:
  - id
  - order_id
  - customer_id
  - provider
  - provider_session_id nullable
  - amount
  - currency
  - status
  - client_reference_id/idempotency_key nullable
  - created_at
  - updated_at

Use migrations/AutoMigrate patterns already used by `ceerat-user-service`.

## Testing Requirements

Contracts:

- Proto generation succeeds.
- Contract package builds and tests pass.
- Known gRPC methods and default role permissions include new protected RPCs.
- Public allowlist is unchanged unless explicitly justified.

Backend:

- Product list filters active products for customer callers.
- Product search handles keyword/SKU/description.
- Get product hides inactive products from customers unless authorized.
- Get cart derives customer from auth context.
- Add/update/remove/clear cart enforce ownership.
- Cart totals are calculated server-side.
- Checkout rejects empty carts.
- Checkout rejects inactive products.
- Checkout creates an order from cart in a transaction.
- Checkout cannot create duplicate orders for repeated idempotency key/cart version.
- Checkout clears or marks cart checked out after success.
- Created order is visible through `GetMyOrder`/`ListMyOrders`.
- Payment session setup requires customer-owned order.
- Payment session setup does not expose secrets.

Customer UI:

- Product pages require session.
- Product list renders without exposing implementation details.
- Product search calls same-origin API.
- Product detail renders add-to-cart.
- Cart page renders empty and non-empty states.
- Quantity updates call same-origin API.
- Checkout creates order and navigates to payment setup.
- Payment setup page renders provider/status placeholder.
- Mobile layout does not overflow for product list/cart/checkout pages.

Integration:

- A customer can complete:
  1. search/list products
  2. view product detail
  3. add product to cart
  4. update quantity
  5. checkout cart to order
  6. see payment setup placeholder
  7. open created order detail

## Verification Commands

Run builder discovery and checks:

```bash
cd /Users/kaansari/go/src/github.com/kaansari/ceerat-platform-builder-agent
ceerat-builder codex-context --output json
ceerat-builder docs all --output json
ceerat-builder inventory services --output json
ceerat-builder inventory contracts --output json
ceerat-builder inventory apps --output json
ceerat-builder decide-owner "product catalog search cart checkout order payment setup customer portal services-repo contracts-repo" --output json
ceerat-builder evidence request "customer products catalog search product cart checkout order payment setup using existing service and order domains" --output json
ceerat-builder patterns service --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder patterns repository --output json
ceerat-builder patterns testing --output json
ceerat-builder app-context ceerat-customer-ui --output json
ceerat-builder app-surface ceerat-customer-ui --output json
ceerat-builder app-match "customer product catalog search cart checkout order payment setup customer portal services-repo contracts-repo" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products" --surface "customer product catalog search" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products/cart" --surface "customer product cart" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products/checkout" --surface "customer product checkout and payment setup" --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
ceerat-builder check apps --output json
ceerat-builder plan --output json "implement customer product catalog search cart checkout order and payment setup using existing ServiceManager and OrderManager domains"
```

Run code verification after implementation:

```bash
cd /Users/kaansari/go/src/github.com/kaansari/contracts-repo/packages/ceerat-contracts
make proto
go test ./...
go build ./...
```

```bash
cd /Users/kaansari/go/src/github.com/kaansari/services-repo/services/ceerat-user-service
go test ./...
go build ./...
```

```bash
cd /Users/kaansari/go/src/github.com/kaansari/apps-repo/apps/ceerat-customer-ui
go test ./...
go build ./...
```

Run final builder verification:

```bash
cd /Users/kaansari/go/src/github.com/kaansari/ceerat-platform-builder-agent
ceerat-builder verify contract-and-service service.ServiceManager --output json
ceerat-builder verify contract-and-service order.OrderManager --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
ceerat-builder check apps --output json
```

## Acceptance Criteria

- Customer portal has a Products area with search/list, detail, cart, checkout, and payment setup screens.
- Customer can add products to cart and update/remove/clear cart.
- Customer can checkout cart into an order.
- Checkout uses backend-calculated totals and server-side product validation.
- Created order is customer-owned and visible through the customer's orders area.
- Payment setup page exists and is provider-neutral.
- No raw payment instruments or gateway secrets are collected or stored.
- Existing service catalog/order service-line flows keep working.
- Contracts, services, apps, security method lists, RBAC permissions, and inventories are updated.
- Required tests/builds and builder checks pass.

## Out of Scope

- Real payment gateway integration.
- Card entry forms.
- Storing payment instruments.
- Public unauthenticated product catalog.
- Direct browser-to-gRPC or browser-to-database calls.
- New standalone product microservice unless builder/code evidence requires it.
- AI chat product shopping tools, unless explicitly requested later.

## Codex Prompt For Execution

```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to implement customer-facing product catalog, product cart, checkout-to-order, and payment setup in Ceerat.

Business context:
- Product catalog, Product, Cart, and CartItem already exist in the service contract inventory under service.ServiceManager.
- Orders and customer self-service order flows already exist under order.OrderManager.
- The backend owner should be services-repo/services/ceerat-user-service unless live code inspection proves otherwise.
- The customer browser owner is apps-repo/apps/ceerat-customer-ui.
- Payment gateway integration will be attached later. Build a provider-neutral payment setup placeholder, not a real card/payment gateway flow.

Before coding, run these from /Users/kaansari/go/src/github.com/kaansari/ceerat-platform-builder-agent:

- ceerat-builder codex-context --output json
- ceerat-builder docs all --output json
- ceerat-builder inventory services --output json
- ceerat-builder inventory contracts --output json
- ceerat-builder inventory apps --output json
- ceerat-builder decide-owner "product catalog search cart checkout order payment setup customer portal services-repo contracts-repo" --output json
- ceerat-builder evidence request "customer products catalog search product cart checkout order payment setup using existing service and order domains" --output json
- ceerat-builder patterns service --output json
- ceerat-builder patterns grpc-security --output json
- ceerat-builder patterns repository --output json
- ceerat-builder patterns testing --output json
- ceerat-builder app-context ceerat-customer-ui --output json
- ceerat-builder app-surface ceerat-customer-ui --output json
- ceerat-builder app-match "customer product catalog search cart checkout order payment setup customer portal services-repo contracts-repo" --output json
- ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products" --surface "customer product catalog search" --output json
- ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products/cart" --surface "customer product cart" --output json
- ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/products/checkout" --surface "customer product checkout and payment setup" --output json
- ceerat-builder rbac check --output json
- ceerat-builder check drift --output json
- ceerat-builder check apps --output json
- ceerat-builder plan --output json "implement customer product catalog search cart checkout order and payment setup using existing ServiceManager and OrderManager domains"

Use builder output as factual context, not final design. The final design must still be based on actual code currently present in the workspace.

Ownership decision:
- Reuse service.ServiceManager for product catalog and cart operations.
- Reuse order.OrderManager for order retrieval and checkout/order creation if that matches current code.
- Add only missing RPCs/messages/models needed for product checkout and payment setup.
- Do not create a new product microservice unless the existing service/order domains cannot support this safely.

Required code inspection before edits:
- ../contracts-repo/packages/ceerat-contracts/proto/service/service.proto
- ../contracts-repo/packages/ceerat-contracts/proto/order/order.proto
- ../contracts-repo/packages/ceerat-contracts/domain/models.go
- ../contracts-repo/packages/ceerat-contracts/mapper/mapper.go
- ../contracts-repo/packages/ceerat-contracts/security/grpc_methods.go
- ../contracts-repo/packages/ceerat-contracts/security/allowlist.go
- ../services-repo/services/ceerat-user-service/main.go
- ../services-repo/services/ceerat-user-service/services/handler.go
- ../services-repo/services/ceerat-user-service/services/repository.go
- ../services-repo/services/ceerat-user-service/orders/handler.go
- ../services-repo/services/ceerat-user-service/orders/repository.go
- ../services-repo/services/ceerat-user-service/internal/models/models.go
- ../apps-repo/apps/ceerat-customer-ui/internal/server/server.go
- ../apps-repo/apps/ceerat-customer-ui/internal/apiclient/client.go
- ../apps-repo/apps/ceerat-customer-ui/web/templates/home.html
- ../apps-repo/apps/ceerat-customer-ui/web/templates/orders.html
- ../apps-repo/apps/ceerat-customer-ui/web/templates/career_nav.html
- ../apps-repo/apps/ceerat-customer-ui/web/static/app.js
- ../apps-repo/apps/ceerat-customer-ui/web/static/app.css

Implementation requirements:
1. Tell me the final ownership decision and exact files to edit before editing.
2. Implement/complete product list/search/get APIs in ServiceManager if missing.
3. Implement/complete authenticated customer cart APIs in ServiceManager if missing.
4. Implement checkout from cart into a customer-owned order with server-side totals, product validation, transactionality, and duplicate-submit protection.
5. Add provider-neutral payment setup/session contract and backend implementation if no suitable placeholder exists.
6. Add or update order models/contracts so product-derived orders render correctly without breaking service-line orders.
7. Update KnownGRPCMethods and DefaultRolePermissions for new protected RPCs.
8. Regenerate protobuf code when proto changes.
9. Add customer UI pages and same-origin API wrappers:
   - /customer/products
   - /customer/products/{id}
   - /customer/products/cart
   - /customer/products/checkout
   - /customer/products/checkout/payment
10. Add product navigation using the existing career/orders subnav style.
11. Ensure mobile layouts do not overflow.
12. Update inventories:
   - contracts-repo/docs/contract-inventory.json
   - services-repo/docs/grpc-service-inventory.json
   - apps-repo/docs/app-surface-inventory.json
13. Update docs only where the new product/cart/checkout/payment surfaces are relevant.

Security constraints:
- Do not trust customer_id, user_id, totals, unit prices, product active status, or payment provider fields from browser input.
- Derive customer ownership from JWT/auth context.
- Do not make product/cart/checkout/payment setup RPCs public.
- Do not expose payment gateway secrets.
- Do not store raw payment instruments.
- Do not log JWTs, auth headers, payment secrets, or sensitive provider responses.
- Apps must call backend service APIs; no direct browser-to-gRPC or browser-to-database calls.

Tests required:
- Product search/list for customers returns active products only.
- Product get hides inactive products from customer callers.
- Cart get/add/update/remove/clear uses authenticated customer ownership.
- Cart totals are server-calculated.
- Checkout rejects empty cart and inactive products.
- Checkout creates an order transactionally and prevents duplicate checkout.
- Checkout result order is visible through customer order APIs.
- Payment setup requires a customer-owned order and returns no secrets.
- Customer product pages require auth.
- Customer UI renders product list/detail/cart/checkout/payment setup.
- Mobile product/cart/checkout layouts do not overflow.

Verification required:
- contracts-repo/packages/ceerat-contracts: make proto, go test ./..., go build ./...
- services-repo/services/ceerat-user-service: go test ./..., go build ./...
- apps-repo/apps/ceerat-customer-ui: go test ./..., go build ./...
- ceerat-builder verify contract-and-service service.ServiceManager --output json
- ceerat-builder verify contract-and-service order.OrderManager --output json
- ceerat-builder rbac check --output json
- ceerat-builder check drift --output json
- ceerat-builder check apps --output json

Acceptance:
- A customer can search products, add a product to cart, review cart, checkout to an order, see payment setup, and open the order detail.
- Payment setup is ready for gateway integration but does not collect/store payment credentials.
- Existing service/order flows continue to work.
```
