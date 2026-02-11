# Contoso Meals - Verification Checklist

> Maps every requirement from `demo-proposal.md` to its implementation and verification method.

---

## 1. Application Services

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| order-api (.NET 9) — order management | `app/order-api/` | `curl <order-api-url>/health` returns `{"status":"healthy"}` |
| payment-service (.NET 9) — fault-injectable | `app/payment-service/` | `curl <payment-url>/fault/status` returns `{"enabled":false,"rate":0}` |
| menu-api (.NET 9) — restaurant catalog | `app/menu-api/` | `curl <menu-api-url>/restaurants` returns seed restaurant data |
| order-api connects to PostgreSQL | `app/order-api/Program.cs` (EF Core) | `curl <order-api-url>/ready` returns `{"status":"ready"}` |
| payment-service connects to PostgreSQL | `app/payment-service/Program.cs` (EF Core) | `curl <payment-url>/ready` returns `{"status":"ready"}` |
| menu-api connects to Cosmos DB | `app/menu-api/Services/CosmosDbService.cs` | `curl <menu-api-url>/ready` returns `{"status":"Ready"}` |
| Fault injection toggleable at runtime | `app/payment-service/Program.cs` (/fault/*) | `POST /fault/enable {"rate":50}` then `GET /fault/status` |
| Dockerfiles for all services | `app/*/Dockerfile` | `docker build -t test app/order-api/` succeeds |

## 2. Infrastructure (Bicep/AVM)

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| AKS Cluster (aks-contoso-meals) | `infra/main.bicep` line 63 (AVM 0.12.0, Automatic SKU) | `az aks show -g rg-contoso-meals -n aks-contoso-meals` |
| Container App Environment | `infra/main.bicep` line 99 (AVM 0.8.1) | `az containerapp env show -g rg-contoso-meals -n cae-contoso-meals` |
| menu-api Container App | `infra/main.bicep` line 112 (AVM 0.12.0) | `az containerapp show -g rg-contoso-meals -n menu-api` |
| PostgreSQL Flexible Server | `infra/modules/postgres.bicep` | `az postgres flexible-server show -g rg-contoso-meals -n psql-contoso-meals-db` |
| ordersdb database | `infra/modules/postgres.bicep` line 44 | `az postgres flexible-server db show -g rg-contoso-meals --server-name psql-contoso-meals-db -d ordersdb` |
| jiradb database | `infra/modules/postgres.bicep` line 54 | `az postgres flexible-server db show -g rg-contoso-meals --server-name psql-contoso-meals-db -d jiradb` |
| Cosmos DB (serverless) | `infra/main.bicep` line 152 (AVM 0.11.0) | `az cosmosdb show -g rg-contoso-meals -n cosmos-contoso-meals` |
| catalogdb with restaurants + menus | `infra/main.bicep` lines 162-175 | `az cosmosdb sql database show -g rg-contoso-meals -a cosmos-contoso-meals -n catalogdb` |
| Key Vault | `infra/main.bicep` line 47 (AVM 0.11.0) | `az keyvault show -g rg-contoso-meals -n kvcontosomeals` |
| Log Analytics Workspace | `infra/main.bicep` line 36 (AVM 0.9.1) | `az monitor log-analytics workspace show -g rg-contoso-meals -n law-contoso-meals` |
| Storage Account (Jira home) | `infra/main.bicep` line 202 (AVM 0.14.0) | `az storage account show -g rg-contoso-meals -n stcontosomeals` |
| Postgres region fix (swedencentral) | `infra/main.bicep` line 143, `main.parameters.json` line 22 | Deployment succeeds without LocationIsOfferRestricted |

## 3. Jira Deployment & Configuration

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Jira SM Container App deployed | `infra/main.bicep` line 228 | `az containerapp show -g rg-contoso-meals -n jira-sm` returns running status |
| Jira connects to PostgreSQL (jiradb) | `infra/main.bicep` line 253 (JDBC URL with sslmode=require) | Open Jira URL in browser, login works |
| JDBC URL uses correct FQDN | `infra/main.bicep` line 253 (uses `postgres.outputs.fqdn`) | Check Jira container env: `ATL_JDBC_URL` matches `psql-contoso-meals-db.postgres.database.azure.com` |
| Jira admin account created | `scripts/setup-jira.sh` | Login at `https://<jira-fqdn>` with admin/admin |
| CONTOSO project created | `scripts/setup-jira.sh` step 3 | `curl <jira-url>/rest/api/2/project/CONTOSO` returns 200 |
| mcp-atlassian MCP server running | `infra/main.bicep` line 278 | `curl https://<mcp-fqdn>/mcp` returns MCP server info |
| Jira ticket creation works | SRE Agent + mcp-atlassian | Ask agent: "Create a test ticket in CONTOSO project" |

## 4. Monitoring & Alerts

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Pod restart alert (threshold > 0) | `infra/modules/monitoring.bicep` line 19 | `az monitor metrics alert show -g rg-contoso-meals -n alert-pod-restart-contoso-meals` |
| Payment P95 latency alert (> 2s) | `infra/modules/monitoring.bicep` line 51 | `az monitor scheduled-query show -g rg-contoso-meals -n alert-payment-latency-contoso-meals` |
| Action Group for SRE Agent | `infra/modules/monitoring.bicep` line 7 | `az monitor action-group show -g rg-contoso-meals -n ag-contoso-meals-sre` |
| Container Insights on AKS | `infra/main.bicep` line 91 (omsAgentEnabled) | AKS → Insights blade shows container metrics |
| Diagnostic settings on PostgreSQL | `infra/modules/postgres.bicep` line 74 | Logs flowing to Log Analytics |
| Diagnostic settings on Cosmos DB | `infra/main.bicep` line 177 | Logs flowing to Log Analytics |
| Observability workbooks | `infra/workbooks/contoso-meals-dashboard.json` | Deploy and open in Azure Portal |

## 5. Chaos Engineering

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Chaos Studio target on AKS | `infra/modules/chaos.bicep` line 11 | `az rest --method get --url "<aks-resource-id>/providers/Microsoft.Chaos/targets"` |
| Pod kill experiment defined | `infra/modules/chaos.bicep` line 24 | `az rest --method get --url "/subscriptions/.../providers/Microsoft.Chaos/experiments"` |
| Experiment targets payment-service | `infra/modules/chaos.bicep` line 59 (jsonSpec) | Check JSON spec: namespace=production, app=payment-service |
| No PDB on payment-service (by design) | `manifests/payment-service.yaml` (comment at bottom) | `kubectl get pdb -n production` shows only order-api-pdb |
| PDB on order-api | `manifests/order-api.yaml` | `kubectl get pdb order-api-pdb -n production` |

## 6. Load Testing

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Azure Load Testing provisioned | `infra/main.bicep` line 187 (AVM 0.4.0) | `az load show -g rg-contoso-meals -n lt-contoso-meals` |
| Baseline test plan (10 VUs) | `load-tests/baseline.jmx` | Import into Azure Load Testing portal |
| Lunch rush test plan (50 VUs) | `load-tests/lunch-rush.jmx` | Import into Azure Load Testing portal |
| curl-based load generator | `scripts/generate-load.sh` | `./scripts/generate-load.sh 5` runs for 5 minutes |

## 7. Kubernetes Manifests

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| production namespace | `manifests/namespace.yaml` | `kubectl get ns production` |
| order-api deployment (2 replicas) | `manifests/order-api.yaml` | `kubectl get deployment order-api -n production` |
| payment-service deployment (2 replicas) | `manifests/payment-service.yaml` | `kubectl get deployment payment-service -n production` |
| Health/readiness probes | Both deployment manifests | `kubectl describe deployment -n production` shows probe config |
| Resource limits (CPU/memory) | Both deployment manifests | `kubectl describe pod -n production` shows resource limits |
| Secrets template | `manifests/secrets.yaml.template` | Template exists with placeholders |

## 8. Knowledge Base / Runbooks

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Contoso Meals runbook | `knowledge/contoso-meals-runbook.md` | File contains service ownership, SLAs, escalation paths |
| Jira ITSM runbook | `knowledge/jira-itsm-runbook.md` | File contains priority matrix, workflow, SLA tracking |

## 9. Scripts

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Automated deployment | `scripts/deploy.sh` | `bash scripts/deploy.sh` completes successfully |
| Clean teardown | `scripts/teardown.sh` | `bash scripts/teardown.sh --yes` deletes resource group |
| Baseline traffic generation | `scripts/generate-load.sh` | `bash scripts/generate-load.sh 5` generates 5 min of traffic |
| Jira initial setup | `scripts/setup-jira.sh` | `bash scripts/setup-jira.sh` creates CONTOSO project |

## 10. Documentation

| Requirement | Implemented At | How to Verify |
|-------------|---------------|---------------|
| Feature specification | `docs/feature-specification.md` | File covers all 3 services, endpoints, data models |
| Architecture + deployment guide | `docs/architecture-deployment.md` | File covers architecture, deployment, troubleshooting |
| Demo walkthrough steps | `docs/demo-walkthrough.md` | File covers all 4 parts with exact prompts |
| Verification checklist | `docs/verification-checklist.md` | This file |
| Demo proposal (source of truth) | `demo-proposal.md` | 14-section comprehensive proposal |

---

## Final Project Structure

```
azure-sre/
├── demo-proposal.md                    # Source of truth
├── azure-sre-agent-guide.md            # Reference guide
├── azure.yaml                          # Azure CLI metadata
├── infra/
│   ├── main.bicep                      # Orchestrator (all modules)
│   ├── main.parameters.json            # Environment config
│   ├── modules/
│   │   ├── postgres.bicep              # PostgreSQL Flexible Server
│   │   ├── monitoring.bicep            # Alert rules + action group
│   │   ├── chaos.bicep                 # Chaos Studio experiments
│   │   └── workbooks.bicep             # Observability dashboards
│   └── workbooks/
│       └── contoso-meals-dashboard.json # Workbook template
├── app/
│   ├── order-api/                      # .NET 9 order management
│   │   ├── OrderApi.csproj
│   │   ├── Program.cs
│   │   ├── Models/Order.cs
│   │   ├── Models/Customer.cs
│   │   ├── Data/OrdersDbContext.cs
│   │   └── Dockerfile
│   ├── payment-service/                # .NET 9 payment processing
│   │   ├── PaymentService.csproj
│   │   ├── Program.cs
│   │   ├── Models/Payment.cs
│   │   ├── Data/PaymentsDbContext.cs
│   │   └── Dockerfile
│   └── menu-api/                       # .NET 9 restaurant catalog
│       ├── MenuApi.csproj
│       ├── Program.cs
│       ├── Models/Restaurant.cs
│       ├── Models/Menu.cs
│       ├── Services/CosmosDbService.cs
│       └── Dockerfile
├── manifests/
│   ├── namespace.yaml                  # production namespace
│   ├── order-api.yaml                  # Deployment + Service + PDB
│   ├── payment-service.yaml            # Deployment + Service (no PDB)
│   └── secrets.yaml.template           # Secrets template
├── load-tests/
│   ├── baseline.jmx                    # 10 VU steady-state test
│   └── lunch-rush.jmx                  # 50 VU peak load test
├── scripts/
│   ├── deploy.sh                       # Full deployment automation
│   ├── teardown.sh                     # Resource cleanup
│   ├── generate-load.sh                # Baseline traffic generator
│   └── setup-jira.sh                   # Jira initial configuration
├── knowledge/
│   ├── contoso-meals-runbook.md        # SRE Agent knowledge base
│   └── jira-itsm-runbook.md            # Jira ITSM procedures
└── docs/
    ├── feature-specification.md        # Service specifications
    ├── architecture-deployment.md      # Architecture + deployment guide
    ├── demo-walkthrough.md             # Step-by-step demo instructions
    └── verification-checklist.md       # This file
```

---

## Acceptance Criteria Summary

- [ ] `az deployment sub create` with `infra/main.bicep` succeeds
- [ ] All pods running: `kubectl get pods -n production` shows 4 pods (2 order-api, 2 payment-service)
- [ ] menu-api healthy: `curl https://<menu-api-fqdn>/restaurants` returns restaurant data
- [ ] PostgreSQL reachable: Both order-api and payment-service `/ready` return 200
- [ ] Cosmos DB populated: Seed data present in catalogdb
- [ ] Jira SM accessible: Browser loads Jira dashboard, CONTOSO project exists
- [ ] mcp-atlassian serving: `/mcp` endpoint responds
- [ ] Monitoring alerts configured: Pod restart + latency alerts visible in Portal
- [ ] Chaos experiment ready: `exp-contoso-meals-pod-kill` in Ready state
- [ ] Load tests available: baseline.jmx and lunch-rush.jmx importable
- [ ] SRE Agent responds to cross-service health queries
- [ ] Full demo scenario (Parts 1-4) runs end-to-end
