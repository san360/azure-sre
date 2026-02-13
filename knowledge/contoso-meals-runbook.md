# Contoso Meals — Escalation Runbook

## Payment Service (AKS: payment-service)
- Owner: Payments Team (#payments-oncall in Teams)
- Jira Assignee: **Alana Grant** (`agrant-sd-demo`)
- SLA: Blocker/Highest incidents must be acknowledged within 15 min
- Business impact: Customers cannot complete orders — revenue loss
- Known issues: Memory pressure during lunch rush (11am-1pm) — check resource limits first
- If pods are OOMKilled, safe to increase limits to 512Mi without approval
- If error rate > 10%, immediately page the Payments Team lead

## Order API (AKS: order-api)
- Owner: Platform Team (#platform-oncall in Teams)
- Jira Assignee: **Jennifer Evans** (`jevans-sd-demo`)
- SLA: Blocker/Highest within 15 min, High within 30 min
- Business impact: No new orders accepted — full outage for customers
- Depends on: PostgreSQL (ordersdb), payment-service, Key Vault
- If database connections exhausted, check for long-running queries first

## Menu API (Container App: menu-api)
- Owner: Catalog Team (#catalog-oncall in Teams)
- Jira Assignee: **Mitch Davis** (`mdavis-sd-demo`)
- SLA: High within 30 min (degraded experience, not full outage)
- Business impact: Customers can't browse menus, but existing orders still process
- Depends on: Cosmos DB (catalogdb)
- If Cosmos DB shows 429 errors, increase RU/s temporarily (safe up to 1000 RU/s)

## Database (PostgreSQL: psql-contoso-meals)
- Owner: Platform Data Team (#db-oncall in Teams)
- Jira Assignee: **Ryan Lee** (`rlee-sd-demo`)
- If connections > 80%, check for long-running queries in pg_stat_activity
- Safe to terminate idle connections older than 30 minutes

## AKS Node Pool Failure (workload node pool)
- Owner: Platform Team (#platform-oncall in Teams)
- Jira Assignee: **Vincent Wong** (`vwong-sd-demo`)
- SLA: Blocker/Highest incidents must be acknowledged within 15 min
- Business impact: Complete application outage — all order-api and payment-service pods unschedulable
- The AKS cluster has two node pools:
  - `system` pool (2 nodes) — reserved for system workloads (CoreDNS, kube-proxy, etc.)
  - `workload` pool (1 node, manual scale) — hosts all application workloads
- If workload node pool count drops to 0:
  1. Check AKS node pool status: `az aks nodepool show -g rg-contoso-meals --cluster-name aks-contoso-meals -n workload`
  2. Check for FailedScheduling events: `kubectl get events -n production --field-selector reason=FailedScheduling`
  3. Check pods in Pending state: `kubectl get pods -n production` — all should be Pending
  4. **Remediation:** Scale the workload node pool back to 1: `az aks nodepool scale -g rg-contoso-meals --cluster-name aks-contoso-meals -n workload --node-count 1`
  5. Wait 2-3 minutes for the node to become Ready
  6. Verify pods return to Running state: `kubectl get pods -n production`
  7. Verify services are responding: check Application Insights for error rate returning to baseline
- If node shows NotReady status but pool count > 0:
  1. Check node conditions: `kubectl describe node <node-name>`
  2. Check for resource pressure (MemoryPressure, DiskPressure)
  3. If node is unrecoverable, cordon and drain, then delete the node — AKS will reprovision
- The workload pool does NOT have autoscaling enabled (manual scale only)
- Safe to scale workload pool to 1-3 nodes without approval
- Do NOT modify the system pool without Platform Team lead approval
