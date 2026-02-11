# Contoso Meals — Implementation Plan

> **Date:** 2026-02-11
> **Scope:** Phases 1, 2, and 4 from `feature-specification.md` (backend API enhancements)
> **Phase 3 (React UI) and Phase 5 (Advanced):** Deferred — implemented separately

---

## Summary of Changes

This plan implements **11 features** across the three backend services:

| ID | Feature | Service | Phase |
|----|---------|---------|-------|
| F-CORS-1 | CORS configuration | all | 1 |
| F-OPENAPI-1 | Swagger / OpenAPI docs | all | 1 |
| F-ORDER-1 | Order filtering (by customer, status) | order-api | 1 |
| F-ORDER-3 | Customer CRUD endpoints | order-api | 1 |
| F-MENU-1 | Restaurant search | menu-api | 2 |
| F-ORCH-1 | Order orchestration (order-api calls payment-service) | order-api | 2 |
| F-ORDER-2 | Enriched order details (cross-service) | order-api | 2 |
| F-MENU-2 | Update restaurant | menu-api | 4 |
| F-ORDER-4 | Cancel order | order-api | 4 |
| F-PAY-1 | Refund processing | payment-service | 4 |

---

## Phase 1 — Core API Hardening

### F-CORS-1: CORS Configuration (all services)

**Files changed:**
- `app/menu-api/Program.cs`
- `app/order-api/Program.cs`
- `app/payment-service/Program.cs`

**Changes:**
- Add `builder.Services.AddCors()` with configurable `ALLOWED_ORIGINS` env var
- Add `app.UseCors()` before endpoint mapping
- Default to allow all origins for demo simplicity

### F-OPENAPI-1: Swagger / OpenAPI (all services)

**Files changed:**
- `app/menu-api/MenuApi.csproj` — add `Microsoft.AspNetCore.OpenApi` and `Swashbuckle.AspNetCore`
- `app/menu-api/Program.cs` — add `AddEndpointsApiExplorer()`, `AddSwaggerGen()`, `UseSwagger()`, `UseSwaggerUI()`
- `app/order-api/OrderApi.csproj` — same packages
- `app/order-api/Program.cs` — same setup
- `app/payment-service/PaymentService.csproj` — same packages
- `app/payment-service/Program.cs` — same setup

**Changes:**
- Register Swagger services with service name and description
- Map `/swagger` UI and `/swagger/v1/swagger.json` spec
- Enable in all environments (demo app, not production-sensitive)

### F-ORDER-1: Order Filtering (order-api)

**Files changed:**
- `app/order-api/Program.cs`

**Changes:**
- Modify `GET /orders` endpoint to accept optional `customerId` and `status` query parameters
- Apply `IQueryable` filtering before `Take(50)`
- Add `status` index to `OrdersDbContext`

### F-ORDER-3: Customer CRUD (order-api)

**Files changed:**
- `app/order-api/Program.cs`

**New endpoints:**
- `POST /customers` — create customer (name, email required, returns 201)
- `GET /customers/{id}` — get customer by ID
- `GET /customers` — list all customers

---

## Phase 2 — Cross-Service Integration

### F-MENU-1: Restaurant Search (menu-api)

**Files changed:**
- `app/menu-api/Program.cs` — add `GET /restaurants/search` endpoint
- `app/menu-api/Services/CosmosDbService.cs` — add `SearchRestaurantsAsync()` method

**Changes:**
- New endpoint: `GET /restaurants/search?q={query}&city={city}`
- Uses Cosmos DB `CONTAINS()` for partial name/cuisine matching (case-insensitive)
- When `city` is provided, scope query to partition key for efficiency

### F-ORCH-1: Order Orchestration (order-api)

**Files changed:**
- `app/order-api/OrderApi.csproj` — no new packages needed (`IHttpClientFactory` is built-in)
- `app/order-api/Program.cs` — register HttpClient, modify `POST /orders`

**Changes:**
- Register named `HttpClient` for `payment-service` with base URL from `PaymentService__BaseUrl` env var
- Add `paymentMethod` to `CreateOrderRequest` (optional, defaults to `"credit_card"`)
- After creating order record, call `POST payment-service/pay` with order ID and amount
- If payment succeeds: update order status to `confirmed`
- If payment fails or service unreachable: update order status to `payment_failed`
- Return composite response with both order and payment result
- If `PaymentService__BaseUrl` is not set, skip orchestration (backwards-compatible)

### F-ORDER-2: Enriched Order Details (order-api)

**Files changed:**
- `app/order-api/Program.cs` — add `GET /orders/{id}/details` endpoint

**Changes:**
- New endpoint returns order with resolved restaurant name and payment status
- Calls `GET menu-api/restaurants/{restaurantId}` to get restaurant name (via `MenuApi__BaseUrl` env var)
- Calls `GET payment-service/payments/{orderId}` to get payment status
- Falls back gracefully if either service is unreachable (returns what it can)
- Includes customer name from local DB

---

## Phase 4 — Enhancements

### F-MENU-2: Update Restaurant (menu-api)

**Files changed:**
- `app/menu-api/Program.cs` — add `PUT /restaurants/{id}` endpoint
- `app/menu-api/Services/CosmosDbService.cs` — add `UpdateRestaurantAsync()` method

**Changes:**
- Accepts partial update (at minimum: `city` for partition key targeting)
- Uses `ReplaceItemAsync` with partition key
- Validates restaurant exists before update

### F-ORDER-4: Cancel Order (order-api)

**Files changed:**
- `app/order-api/Program.cs` — add `DELETE /orders/{id}` endpoint

**Changes:**
- Only allows cancellation for orders with status `pending` or `payment_failed`
- Sets status to `cancelled` (soft delete)
- Returns 409 Conflict if order cannot be cancelled

### F-PAY-1: Refund Processing (payment-service)

**Files changed:**
- `app/payment-service/Program.cs` — add `POST /pay/{paymentId}/refund` endpoint

**Changes:**
- Only `completed` payments can be refunded
- Creates a new payment record with status `refunded` and negative amount (audit trail)
- Returns 409 if payment status is not `completed`

---

## Environment Variables (New)

| Variable | Service | Default | Purpose |
|----------|---------|---------|---------|
| `ALLOWED_ORIGINS` | all | `*` | CORS allowed origins |
| `PaymentService__BaseUrl` | order-api | _(empty — skip orchestration)_ | payment-service URL for orchestration |
| `MenuApi__BaseUrl` | order-api | _(empty — skip enrichment)_ | menu-api URL for enriched details |

---

## Files Changed Summary

| File | Changes |
|------|---------|
| `app/menu-api/MenuApi.csproj` | Add Swashbuckle.AspNetCore package |
| `app/menu-api/Program.cs` | CORS, Swagger, search endpoint, update endpoint |
| `app/menu-api/Services/CosmosDbService.cs` | SearchRestaurantsAsync, UpdateRestaurantAsync |
| `app/order-api/OrderApi.csproj` | Add Swashbuckle.AspNetCore package |
| `app/order-api/Program.cs` | CORS, Swagger, filtering, customer CRUD, orchestration, enriched details, cancel |
| `app/order-api/Data/OrdersDbContext.cs` | Add status index |
| `app/payment-service/PaymentService.csproj` | Add Swashbuckle.AspNetCore package |
| `app/payment-service/Program.cs` | CORS, Swagger, refund endpoint |

---

## Testing Strategy

After implementation, verify each service compiles:
```bash
dotnet build app/menu-api/MenuApi.csproj
dotnet build app/order-api/OrderApi.csproj
dotnet build app/payment-service/PaymentService.csproj
```

Manual API testing sequence:
1. Start all services
2. `GET /swagger` — verify OpenAPI docs load on each service
3. `GET /restaurants/search?q=burger` — verify search returns Contoso Burger Palace
4. `POST /customers` — create a test customer
5. `POST /orders` with `paymentMethod` — verify orchestration creates order + processes payment
6. `GET /orders/{id}/details` — verify enriched response with restaurant name and payment status
7. `GET /orders?status=confirmed` — verify filtering
8. `DELETE /orders/{id}` on a pending order — verify cancellation
9. `POST /pay/{paymentId}/refund` — verify refund creates audit record
10. `PUT /restaurants/{id}` — verify restaurant update
