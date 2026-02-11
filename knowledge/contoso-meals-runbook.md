# Contoso Meals — Escalation Runbook

## Payment Service (AKS: payment-service)
- Owner: Payments Team (#payments-oncall in Teams)
- SLA: P1 incidents must be acknowledged within 15 min
- Business impact: Customers cannot complete orders — revenue loss
- Known issues: Memory pressure during lunch rush (11am-1pm) — check resource limits first
- If pods are OOMKilled, safe to increase limits to 512Mi without approval
- If error rate > 10%, immediately page the Payments Team lead

## Order API (AKS: order-api)
- Owner: Platform Team (#platform-oncall in Teams)
- SLA: P1 within 15 min, P2 within 30 min
- Business impact: No new orders accepted — full outage for customers
- Depends on: PostgreSQL (ordersdb), payment-service, Key Vault
- If database connections exhausted, check for long-running queries first

## Menu API (Container App: menu-api)
- Owner: Catalog Team (#catalog-oncall in Teams)
- SLA: P2 within 30 min (degraded experience, not full outage)
- Business impact: Customers can't browse menus, but existing orders still process
- Depends on: Cosmos DB (catalogdb)
- If Cosmos DB shows 429 errors, increase RU/s temporarily (safe up to 1000 RU/s)

## Database (PostgreSQL: psql-contoso-meals)
- Owner: Platform Data Team (#db-oncall in Teams)
- If connections > 80%, check for long-running queries in pg_stat_activity
- Safe to terminate idle connections older than 30 minutes
