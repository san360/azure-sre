# Azure SRE Agent Demo Proposal v2: "The Connected SRE Brain"

> **Document type:** Demo Proposal & Execution Guide
> **Target audience:** Customer-facing presentations, partner demos, internal enablement
> **Application theme:** Contoso Meals — cloud-native food ordering platform
> **Estimated demo duration:** 60-85 minutes (adjustable per part)
> **Infrastructure:** Bicep with Azure Verified Modules (AVM)
> **Estimated daily cost:** ~$20-35 (tear down after demo)

---

## 1. What Changed from v1 and Why

| v1 Problem | v2 Solution |
|------------|-------------|
| "Break thing, watch agent fix it" is formulaic and predictable | Demo centers on **connected intelligence** — the agent reasoning across multiple services via MCP |
| Terraform-based infra | **Bicep with Azure Verified Modules (AVM)** — enterprise-aligned, policy-compatible |
| Intentional misconfigs (public endpoints, TLS 1.0) may be blocked by Azure Policy in enterprise tenants | Uses **Azure Chaos Studio** for controlled fault injection + application-level error injection instead |
| Single-trick demo (just incident response) | Three-part narrative showing **setup, intelligence, and closed-loop operations** |
| MCP was an afterthought | **MCP is the centerpiece** — demonstrates the agent as a hub connecting 42+ Azure services |
| No ITSM extensibility story | **Part 4 demonstrates Jira Service Management** via MCP — proving the agent extends to any ITSM platform, not just built-in ServiceNow/PagerDuty |

---

## 2. The Core Thesis

> **The Azure SRE Agent is not a chatbot. It's a connected intelligence layer.**

Most AI-ops demos show a bot answering questions about one service. That's a wrapper around `kubectl` or `az monitor`. The real value of Azure SRE Agent is different:

1. **MCP gives it 42+ Azure service tool groups in a single connection** — it can reason across AKS, Cosmos DB, Storage, Monitor, Key Vault, Policy, Resource Health, and more simultaneously.
2. **The Subagent Builder lets you encode your team's expertise** — turning tribal knowledge into persistent, reusable agents.
3. **Memory means it learns** — past incidents inform future investigations.
4. **The closed loop from detection to PR** — it doesn't just report; it creates GitHub issues, sends Teams notifications, and hands off to developers.

The demo should make the audience feel: *"This is fundamentally different from what we have today."*

---

## 3. Application Theme: "Contoso Meals"

Every good demo needs a story the audience can hold onto. Ours is **Contoso Meals** — a cloud-native food ordering platform.

### Why This Theme Works

- **Immediately relatable** — everyone has ordered food online; no domain knowledge required.
- **Naturally multi-service** — the architecture maps cleanly to real business domains.
- **Failure scenarios feel real** — "payments are failing" or "the menu isn't loading" are problems your audience has personally experienced as customers.
- **Enterprise-relevant** — the pattern (API → processing → data store → external integration) mirrors what every enterprise builds, regardless of industry.

### Business Domains → Azure Services

| Business Domain | Service | Azure Resource | Data Store | Why This Service |
|----------------|---------|---------------|------------|-----------------|
| **Order Processing** | Receives and manages customer orders | AKS: `order-api` | PostgreSQL (relational — orders, customers, addresses) | Complex stateful workload with multiple dependencies; benefits from Kubernetes orchestration |
| **Payment Processing** | Handles payment transactions | AKS: `payment-service` | PostgreSQL (transactions table) | High reliability requirement; fault-injectable for demo; co-located with order-api for low latency |
| **Menu & Restaurant Catalog** | Serves restaurant menus and product catalog | Container App: `menu-api` | Cosmos DB (document store — flexible schema for varied restaurant menus) | Simpler read-heavy workload; good fit for serverless Container Apps; Cosmos DB handles schema variety |
| **Secrets & Config** | API keys, connection strings, feature flags | — | Key Vault | Every enterprise needs centralized secret management |

### The Narrative Grid

This mapping creates natural investigation paths that feel organic, not staged:

```
Customer places order
    │
    ├──► menu-api (Container App) ──► Cosmos DB
    │    "What's on the menu?"        (restaurant data)
    │
    ├──► order-api (AKS) ──► PostgreSQL
    │    "Place my order"     (order records)
    │
    └──► payment-service (AKS) ──► PostgreSQL
         "Charge my card"          (payment transactions)
```

When the payment-service has issues, it's not abstract — it's *"customers can browse menus but orders are failing at checkout."* When Cosmos DB throttles, *"the menu page is slow but existing orders are processing fine."* These are real business impact statements the SRE Agent can articulate.

---

## 4. The Role of Azure Load Testing

### Why Load Testing Matters for This Demo

Without traffic, the demo has three problems:

| Problem | What Happens |
|---------|-------------|
| **Flat metrics** | Azure Monitor shows zero traffic. The SRE Agent investigates and finds... nothing interesting. No baseline to compare against. |
| **Phantom incidents** | Chaos Studio kills a pod, but with no traffic, no requests fail. The pod restarts, and there's nothing for the agent to find. |
| **No business context** | The agent can't say "error rate spiked from 0.1% to 45%" if there's no traffic producing the baseline 0.1%. |

Azure Load Testing solves all three:

### Three Uses in the Demo

#### Use 1: Baseline Traffic (Before the Demo)

Run a steady-state load test for 30-60 minutes before the demo to build meaningful metrics in Application Insights and Azure Monitor.

```
Test configuration:
  - 10-20 virtual users
  - Constant rate: ~5 requests/second
  - Targets: order-api, menu-api, payment-service
  - Duration: 30-60 min before demo
```

This gives the SRE Agent historical data to reason about: *"Average P95 latency was 180ms over the last hour. Current P95 is 3,200ms — that's an 18x increase."*

#### Use 2: Load + Chaos = Realistic Incident (Part 3 of Demo)

Run a load test simultaneously with the Chaos Studio experiment. This creates a real incident:

- Load Testing sends 20 requests/second to payment-service
- Chaos Studio kills payment-service pods every 60 seconds
- Actual customer requests fail (not theoretical)
- Application Insights records real 5xx errors, latency spikes, and dependency failures
- The SRE Agent has rich, correlated data to investigate

**This is the difference between a demo and a simulation.** The failures are real. The metrics are real. The investigation is real.

#### Use 3: Post-Incident Performance Validation (Part 3 Closing)

After the agent fixes the issue, ask:

> *"Can you check the Application Insights data and confirm that error rates have returned to normal since the fix was applied?"*

The agent compares current metrics to the baseline established by the load test. It can say: *"Error rate has dropped from 42% back to 0.2%. P95 latency is 195ms, within normal range."*

### Azure Load Testing in the Architecture

Azure Load Testing is provisioned via AVM (`avm/res/load-test-service/load-test`) and configured with a simple URL-based test targeting the application endpoints. No JMeter scripting required for the demo.

```bicep
module loadTest 'br/public:avm/res/load-test-service/load-test:0.4.0' = {
  scope: rg
  name: 'load-test'
  params: {
    name: 'lt-${prefix}'
    location: location
    loadTestDescription: 'Contoso Meals baseline and chaos load test'
    managedIdentities: {
      systemAssigned: true
    }
  }
}
```

---

## 5. Demo Architecture

### Infrastructure (Bicep/AVM)

```
Resource Group: rg-contoso-meals (Sweden Central)
│
├── Azure SRE Agent: contoso-meals-sre
│   │  (Bicep: Microsoft.App/agents@2025-05-01-preview)
│   ├── Application Insights (connected via Bicep)
│   ├── Log Analytics Workspace (auto-provisioned)
│   ├── User-Assigned Managed Identity: id-contoso-meals-sre-agent
│   │   └── Tiered RBAC: Reader + Contributor + Log Analytics Reader + Key Vault roles
│   ├── Smart Detection Alert: Failure Anomalies (auto-configured)
│   ├── SRE Agent Administrator role: auto-assigned to deployer
│   ├── Connector: Azure MCP Server (42+ service tool groups)
│   ├── Connector: Microsoft Teams
│   ├── Connector: Outlook
│   └── Connector: Custom MCP — mcp-atlassian (Jira SM, 34 tools)
│
├── AKS Cluster: aks-contoso-meals
│   │  (AVM: avm/res/container-service/managed-cluster)
│   ├── Namespace: production
│   │   ├── Deployment: order-api (.NET 9 — order management)
│   │   └── Deployment: payment-service (.NET 9 — payment processing, fault-injectable)
│   ├── Container Insights enabled → Log Analytics
│   └── Chaos Studio Target (pod chaos, network latency)
│
├── Container App: menu-api
│   │  (AVM: avm/res/app/container-app)
│   ├── .NET 9 — restaurant menu & catalog service
│   ├── Container App Environment with Log Analytics
│   └── Managed Identity → Cosmos DB access
│
├── Azure Database for PostgreSQL Flexible Server: psql-contoso-meals
│   │  (AVM: avm/res/db-for-postgre-sql/flexible-server)
│   ├── Database: ordersdb (orders, customers, payments)
│   ├── Database: jiradb (Jira Service Management)
│   └── Diagnostic settings → Log Analytics
│
├── Cosmos DB Account: cosmos-contoso-meals
│   │  (AVM: avm/res/document-db/database-account)
│   ├── Database: catalogdb
│   ├── Container: restaurants (partitioned by /city)
│   ├── Container: menus (partitioned by /restaurantId)
│   └── Diagnostic settings → Log Analytics
│
├── Key Vault: kv-contoso-meals
│   │  (AVM: avm/res/key-vault/vault)
│   └── Connection strings, payment gateway keys, feature flags
│
├── Azure Monitor
│   ├── Alert Rule: AKS pod restart count > 0
│   ├── Alert Rule: payment-service P95 latency > 2s
│   ├── Alert Rule: PostgreSQL active connections > 80%
│   ├── Alert Rule: Cosmos DB 429 (throttled requests) > 0
│   └── Action Group → SRE Agent
│
├── Azure Chaos Studio
│   ├── Target: AKS Cluster (Chaos Mesh provider)
│   ├── Experiment: Kill payment-service pods every 60s for 5 min
│   └── Experiment: Inject 500ms network latency on order-api
│
├── Storage Account: st<prefix> (sanitized)
│   │  (AVM: avm/res/storage/storage-account)
│   └── File Share: jira-home (Jira home directory persistence)
│
├── Container App: jira-sm
│   │  (AVM: avm/res/app/container-app)
│   ├── Jira Service Management 10.0 (atlassian/jira-servicemanagement:10.0)
│   ├── 2 vCPU, 4 GB RAM
│   ├── Port 8080
│   ├── PostgreSQL backend (jiradb on psql-contoso-meals)
│   └── Azure Files volume mount (/var/atlassian/application-data/jira)
│
├── Container App: mcp-atlassian
│   │  (AVM: avm/res/app/container-app)
│   ├── MCP-Atlassian Server (ghcr.io/sooperset/mcp-atlassian:latest)
│   ├── 0.5 vCPU, 512 MB RAM
│   ├── Port 9000 (streamable-http transport)
│   ├── 34 Jira MCP tools (create, update, transition, search, SLA)
│   └── Exposes /mcp endpoint for SRE Agent
│
└── Azure Load Testing: lt-contoso-meals
    │  (AVM: avm/res/load-test-service/load-test)
    ├── Test: Baseline traffic (10 VUs, steady state)
    └── Test: Peak load (50 VUs, ramp to simulate lunch rush)
```

### Application Flow Diagram

```
     Azure Load Testing
     (simulated customers)
            │
            ▼
    ┌───────────────┐    ┌───────────────────────────────┐
    │  menu-api     │    │       AKS Cluster              │
    │  (Container   │    │  ┌─────────────────────────┐   │
    │   App)        │    │  │  order-api               │   │
    │               │    │  │  "Place order, track it"  │   │
    │  "Browse      │    │  │         │                 │   │
    │   restaurants │    │  │  payment-service          │   │
    │   and menus"  │    │  │  "Process payment"        │   │
    │       │       │    │  │  ⚡ Chaos Studio target   │   │
    │       ▼       │    │  └───────────┬───────────────┘   │
    │   Cosmos DB   │    │              │                   │
    │  (catalogdb)  │    │              ▼                   │
    │               │    │       PostgreSQL                 │
    └───────────────┘    │       (ordersdb)                 │
                         └───────────────────────────────────┘
                                        │
                           ┌────────────┴────────────┐
                           │                         │
                       Key Vault              Azure Monitor
                    (secrets, keys)        (metrics, logs, alerts)
                                                     │
                                              Azure SRE Agent
                                           (connected via MCP)
```

### Why This Architecture Tells a Story

The audience sees a **business they understand** — ordering food — running on the **same Azure services they use**. When something breaks, the impact is concrete: *"Customers can see the menu but can't complete checkout because the payment service is failing."* The SRE Agent investigation feels real because the scenario is real.

### ITSM Integration Path (Part 4)

```
Azure Monitor Alert fires
         │
         ▼
  Azure SRE Agent ──────────────── mcp-atlassian ──────── Jira SM
  (investigates via MCP)          (Container App)          (Container App)
         │                         port 9000/mcp            port 8080
         │                              │
         ├── jira_create_issue ─────────┤
         ├── jira_add_comment ──────────┤
         ├── jira_transition_issue ─────┤
         ├── jira_update_issue ─────────┤
         └── jira_get_issue_sla ────────┘
                                         │
                                    PostgreSQL
                                    (jiradb on psql-contoso-meals)
```

> **Important architectural note:** Jira SM is NOT a built-in incident platform trigger (only ServiceNow and PagerDuty are). Azure Monitor Alerts trigger the SRE Agent natively. The agent then creates, updates, and resolves Jira tickets via MCP tools during its investigation — a pull-based ITSM integration pattern rather than a push-based trigger.

---

## 6. Demo Flow: Four Parts

---

### Part 1: "Building the Brain" — Setup & MCP Connection (12-15 min)

**Why this part matters:** Most demos skip setup. But the setup IS the story here — connecting the MCP server shows 42+ Azure services becoming available to the agent instantly. No custom code. No integration development. That's the aha moment.

#### Scene 1.0: Infrastructure Deployed via Bicep (2 min)

Show the deployment output from `az deployment sub create`. The SRE Agent was provisioned alongside all other infrastructure — not manually in the portal.

**Narrator:** *"Everything you see — AKS, PostgreSQL, Cosmos DB, Container Apps, Chaos Studio, and the SRE Agent itself — was deployed in a single Bicep template. No portal clicking. The agent is an infrastructure resource, defined and versioned like everything else."*

Show the deployment output:
```
SRE Agent (deployed via Bicep):
  Portal URL:      https://portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/...
  Access Level:    High (Reader + Contributor + Log Analytics Reader)
  Mode:            Review
```

**Key talking point:** The `Microsoft.App/agents@2025-05-01-preview` resource type means the SRE Agent is a first-class Azure resource — deployable via Bicep, ARM, Terraform, or any IaC tool. It supports tiered access levels (High/Low), configurable modes (Review/Autonomous/ReadOnly), and cross-subscription targeting for enterprise multi-RG environments.

#### Scene 1.1: Open the SRE Agent (1 min)

Click the Portal URL from the deployment output (or navigate to the SRE Agent in the portal):
1. Show the agent is already provisioned with Application Insights connected
2. Show the user-assigned managed identity (`id-contoso-meals-sre-agent`) is already attached
3. Show the SRE Agent Administrator role was auto-assigned to the deployer

**Narrator:** *"The agent was deployed with the infrastructure. It already has its managed identity, Application Insights telemetry, and Smart Detection alerts configured. No setup wizard. No manual configuration. Just IaC."*

#### Scene 1.2: Connect Azure MCP Server (5 min)

This is the **centerpiece moment** of the demo.

1. Navigate to **Settings → Connectors**
2. Click **Add Connector → Custom MCP Server**
3. Configure:

| Field | Value |
|-------|-------|
| Connection Type | stdio |
| Command | `npx` |
| Arguments | `-y, @azure/mcp, server, start` |
| Managed Identity | `id-contoso-meals-sre-agent` *(select from dropdown)* |
| Environment: AZURE_CLIENT_ID | *(Client ID of `id-contoso-meals-sre-agent` — see deployment output)* |
| Environment: AZURE_TOKEN_CREDENTIALS | `ManagedIdentityCredential` |

4. Save and verify connection shows **Connected** status.

> **Important:** You must select the **user-assigned** managed identity `id-contoso-meals-sre-agent` from the dropdown. System-assigned managed identities are not supported for SRE Agent connectors. The `AZURE_CLIENT_ID` must match the client ID of the identity selected in the dropdown. Run `az identity show --name id-contoso-meals-sre-agent --resource-group rg-contoso-meals --query clientId -o tsv` to retrieve it.

**Narrator:** *"With one connector, this agent now has access to 42+ Azure service tool groups — AKS cluster management, Cosmos DB queries, Storage operations, Policy checks, Resource Health, RBAC analysis, Key Vault secrets listing, and more. One connection. No custom code. No API wrappers."*

#### Scene 1.3: Connect Teams (2 min)

1. Settings → Connectors → Add → Microsoft Teams
2. Authenticate with OAuth
3. Select the target Teams channel

**Narrator:** *"Now the agent can post findings directly to your team channel."*

#### Scene 1.4: Upload a Runbook to Knowledge Base (2 min)

1. Settings → Knowledge Base → Upload
2. Upload a markdown file: `contoso-meals-runbook.md`

```markdown
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
```

**Narrator:** *"Your team's runbooks, escalation policies, and tribal knowledge — uploaded once, available to the agent forever. Semantic search means it retrieves the right section automatically during an investigation."*

#### Scene 1.5: Quick Smoke Test (2 min)

Type in the chat:

> *"What resources are you monitoring for Contoso Meals? Give me a summary of the overall health across our AKS cluster, Container App, PostgreSQL database, and Cosmos DB."*

**What happens:** The agent uses MCP tools to enumerate resources across all services, checks Azure Resource Health for each, and produces a consolidated health summary.

**Narrator:** *"One question. The order processing pipeline, payment service, menu catalog, and both databases — all checked in one answer. No dashboard switching."*

---

### Part 2: "The Connected Brain in Action" — Cross-Service Intelligence (15-20 min)

**Why this part matters:** This is NOT "break thing, watch fix." This demonstrates the agent's ability to **reason across service boundaries** — something humans do slowly and AI can do fast.

#### Scene 2.1: Cross-Service Investigation (8 min)

Type in the chat:

> *"We're about to enter our lunch rush. Can you do a pre-rush health check? Verify that order-api and payment-service pods are healthy in AKS, the menu-api Container App is ready to scale, PostgreSQL has enough connection headroom, Cosmos DB has sufficient RU/s for the catalog reads, and all secrets in Key Vault are accessible."*

**What the agent does (visible in chat):**

1. **AKS** — Uses `kubectl get pods -n production`, checks resource utilization on order-api and payment-service
2. **Container Apps** — Queries menu-api revision health, current replica count vs max, scaling rules
3. **PostgreSQL** — Checks active connections vs max_connections on ordersdb
4. **Cosmos DB** — Queries RU consumption on catalogdb, checks for recent 429 throttling
5. **Key Vault** — Reviews access patterns, checks for denied operations or expiring secrets

The agent correlates and produces a unified pre-rush readiness report with severity-rated findings.

**Key message:** *"Before the lunch rush, an SRE would open five different portal blades, run multiple CLI commands, cross-reference metrics manually. The agent did this readiness check in one conversation turn, across all services."*

#### Scene 2.2: Proactive Risk Detection with Azure Policy (5 min)

Type in the chat:

> *"Are any of the Contoso Meals resources non-compliant with our Azure Policies? Check compliance state using the Policy tools."*

**What happens:** The agent uses the `policy` MCP namespace to query Azure Policy compliance state. It reports on any non-compliant resources, which policies they violate, and recommended remediation.

**Narrator:** *"Notice — the agent isn't scanning configurations on its own. It's querying Azure Policy, your organization's governance layer. It respects your enterprise guardrails, not its own rules."*

#### Scene 2.3: Cost & Performance Intelligence (4 min)

Type in the chat:

> *"Our Azure bill has been growing. Use Azure Advisor to check if any Contoso Meals resources are oversized or underutilized. Also, based on our Application Insights data from the load test, is our current PostgreSQL SKU appropriate for the query patterns?"*

**What happens:** The agent uses Advisor MCP tools for cost recommendations and correlates with Application Insights dependency data to give a data-driven sizing recommendation.

**Narrator:** *"Same agent, same conversation. Health, compliance, cost, performance — all through one interface. And the recommendations are grounded in your actual traffic patterns, not generic rules."*

---

### Part 3: "Lunch Rush Under Fire" — Load + Chaos + Closed Loop (15-20 min)

**Why this part matters:** Now we simulate Contoso Meals' busiest hour — lunch. Azure Load Testing generates realistic customer traffic while Chaos Studio introduces a real failure. The SRE Agent must investigate under pressure with live traffic flowing. This isn't a staged break-fix; it's a realistic operational scenario.

#### Scene 3.1: Start the Lunch Rush Load Test (2 min)

In the Azure Portal, navigate to Azure Load Testing → `lt-contoso-meals`:

1. Start the pre-configured **"Lunch Rush"** test:
   - 50 virtual users ramping up over 2 minutes
   - Targets: order-api (POST /orders), payment-service (POST /pay), menu-api (GET /menus)
   - Duration: 10 minutes

**Narrator:** *"It's noon. Contoso Meals is getting 50 concurrent customers placing orders — our simulated lunch rush. Metrics are flowing into Application Insights, the SRE Agent is watching, and everything looks healthy. Now let's introduce a real-world failure."*

#### Scene 3.2: Start the Chaos Experiment (1 min)

While load is running, navigate to Azure Chaos Studio → Experiments:

1. Start `exp-contoso-meals-pod-kill` — kills payment-service pods every 60 seconds for 5 minutes

**Narrator:** *"We're running an Azure Chaos Studio experiment during peak load — this is chaos engineering. We're testing: can our platform survive payment-service pod failures during the lunch rush? More importantly, can our SRE Agent figure out what's happening?"*

#### Scene 3.3: Agent Detects and Investigates (8 min)

**Wait for the Azure Monitor alert to fire (1-2 min)**, or ask directly:

> *"Customers are reporting that their food orders are failing at checkout. The menu seems to work fine. Can you investigate what's happening with order processing and payments?"*

**What the agent does:**

1. Checks AKS pods — sees payment-service pods restarting frequently, order-api healthy
2. Runs `kubectl describe pod` — sees pods terminated externally (not OOMKilled)
3. Checks Application Insights — correlates with load test data: menu-api requests succeeding (200s), order-api partially failing, payment-service showing intermittent 5xx errors
4. Checks Azure Activity Log — discovers the Chaos Studio experiment `exp-contoso-meals-pod-kill`
5. **Correlates:** *"The payment-service pods are being terminated by an active Chaos Studio experiment. During the lunch rush load test (50 concurrent users), this is causing ~40% of payment requests to fail. The menu-api (Container App) and Cosmos DB catalog are unaffected. PostgreSQL is healthy — the failures are at the pod level, not the database."*
6. Checks the Knowledge Base — finds the Contoso Meals runbook: *"Per your runbook, the Payments Team (#payments-oncall) owns this service. Business impact: customers can browse menus but cannot complete orders — this is revenue loss."*

**Key aha moments:**
- The agent identified it's a **Chaos Studio experiment, not a real outage**, by correlating Activity Log entries
- It quantified the business impact using the **load test data**: "40% of payments failing during peak"
- It correlated the **runbook** to identify the right team and escalation path
- It correctly identified that **menu-api and Cosmos DB are unaffected** — this scoping prevents panic

**Narrator:** *"A basic alert says 'pods restarting.' The SRE Agent says 'Chaos Studio is killing your payment pods during peak traffic, 40% of orders are failing, here's the team to call, and your menu service is unaffected.' That's the difference between alerting and intelligence."*

#### Scene 3.4: Closed-Loop Actions (5 min)

Ask the agent to close the loop:

> *"Send a summary of this investigation to the Teams channel. Include the business impact — what percentage of orders failed during the chaos experiment. Then create a GitHub issue recommending that we add a PodDisruptionBudget to the payment-service to survive pod failures during peak traffic."*

**What happens:**
1. Agent sends a formatted Teams message with:
   - Investigation summary
   - Business impact: ~40% payment failures during 50-user lunch rush
   - Root cause: No PodDisruptionBudget, so Chaos Mesh could kill all pods simultaneously
2. Agent creates a GitHub issue with:
   - Incident timeline
   - Load test baseline vs. failure metrics
   - Recommendation: Add `PodDisruptionBudget` allowing at most 1 pod unavailable
   - Recommended Kubernetes manifest change

Then ask for post-incident validation:

> *"The chaos experiment has ended. Can you verify that error rates have returned to normal based on the Application Insights data?"*

The agent checks current metrics against the load test baseline: *"Error rate has dropped from 40% back to 0.3%. P95 latency is 190ms, within the baseline range of 150-200ms. The payment-service has stabilized."*

**Narrator:** *"Detection, business impact quantification, team notification, developer handoff, and post-incident validation — all automated, all grounded in real metrics from the load test."*

#### Scene 3.5: Build a Resilience Subagent — Live (4 min)

Close the loop by building a custom subagent:

1. Navigate to **Subagent Builder** → Create → Subagent
2. Configure:

| Property | Value |
|----------|-------|
| Name | Contoso Meals Resilience Validator |
| Instructions | *"After any chaos experiment completes on the Contoso Meals platform, evaluate the results. Check if order-api and payment-service maintained availability during the experiment. Compare error rates and latency to the baseline load test. If availability dropped below 99%, create a GitHub issue recommending resilience improvements (PodDisruptionBudgets, circuit breakers, retry policies). Always note the business impact in terms of failed customer orders."* |
| Handoff Description | *"Hand off to this subagent when a chaos experiment is detected or completed"* |
| Built-in Tools | Azure CLI, Log Analytics |
| MCP Tools | Azure MCP (AKS tools, Monitor tools) |

3. Test in the Playground: *"The exp-contoso-meals-pod-kill chaos experiment just completed. Evaluate the impact on our food ordering platform."*

**Narrator:** *"Your chaos engineering practice is now automated. Every experiment gets an AI-powered evaluation that quantifies business impact — how many customer orders were affected. No one has to manually check dashboards after the experiment."*

---

### Part 4: "ITSM Extensibility" — Jira Service Management via MCP (20-25 min)

**Why this part matters:** Parts 1-3 show the SRE Agent with Azure-native services. But enterprise customers use diverse ITSM platforms. Part 4 proves the agent is not locked to ServiceNow or PagerDuty — it extends to **any ITSM platform** through MCP. Jira Service Management is the perfect example: widely used, not a built-in integration, and fully functional through the open-source mcp-atlassian MCP server. This is the extensibility story.

**Important architectural note:** Jira SM is NOT a built-in incident platform trigger (only ServiceNow and PagerDuty are). Azure Monitor Alerts trigger the SRE Agent natively. The agent then creates, updates, and resolves Jira tickets via MCP tools during its investigation — a pull-based ITSM integration pattern rather than a push-based trigger.

#### Scene 4.1: Overview & Jira Deployment Verification (2 min)

Show the audience the Jira and mcp-atlassian Container Apps that were deployed alongside the Contoso Meals infrastructure.

1. Navigate to **Azure Portal → Container Apps** in `rg-contoso-meals`
2. Show `jira-sm` Container App — click into it, show it is running with 2 vCPU / 4 GB RAM
3. Open the Jira SM URL (FQDN from Container App overview) — show the Jira dashboard with the pre-configured `CONTOSO` project
4. Navigate back to Container Apps and show `mcp-atlassian` — the MCP bridge that exposes 34 Jira tools

| Resource | Purpose | Key Detail |
|----------|---------|------------|
| `jira-sm` Container App | Jira Service Management instance | `atlassian/jira-servicemanagement:10.0`, port 8080 |
| `mcp-atlassian` Container App | MCP server bridging SRE Agent to Jira | `ghcr.io/sooperset/mcp-atlassian:latest`, port 9000, `/mcp` endpoint |
| `jiradb` on `psql-contoso-meals` | Jira's PostgreSQL database | Same PostgreSQL server as ordersdb |
| Azure Files share `jira-home` | Persistent storage for Jira home directory | Mounted at `/var/atlassian/application-data/jira` |

**Narrator:** *"We've deployed Jira Service Management as a Container App in the same environment as our Contoso Meals services. Alongside it, we have mcp-atlassian — an open-source MCP server that exposes 34 Jira tools over a standard MCP endpoint. This is the same pattern you'd use for any ITSM platform: deploy an MCP bridge, point the SRE Agent at it."*

#### Scene 4.2: Connect mcp-atlassian to SRE Agent (3 min)

Live in the Azure Portal:

1. Navigate to **SRE Agent → Settings → Connectors**
2. Click **Add Connector → Custom MCP Server**
3. Configure:

| Field | Value |
|-------|-------|
| Name | Jira Service Management |
| Connection Type | HTTP (streamable) |
| Endpoint URL | `https://<mcp-atlassian-fqdn>/mcp` |
| Authentication | Custom headers |
| Headers | `Authorization: Token <jira-api-token>` |

> **Important:** Use the `Token` prefix (not `Bearer`). The mcp-atlassian middleware interprets `Bearer` as OAuth (requiring a full OAuth config), while `Token` is treated as a Personal Access Token (PAT) which works with the server's existing basic auth credentials.

4. Save and verify connection — the agent discovers 34 Jira tools

**Narrator:** *"One connector. The SRE Agent now has 34 Jira tools — creating tickets, updating priorities, transitioning workflow states, adding investigation notes, querying SLAs, linking related incidents, and searching with JQL. No custom code. No webhook plumbing. Just an MCP endpoint."*

**What happens:** After saving, the agent's tool inventory expands. You can verify by asking:

> *"What Jira tools do you now have available? List them."*

The agent should enumerate tools including `jira_create_issue`, `jira_update_issue`, `jira_transition_issue`, `jira_add_comment`, `jira_search`, `jira_get_issue`, `jira_get_transitions`, `jira_get_issue_sla`, `jira_create_issue_link`, and `jira_create_remote_issue_link`.

**Aha moment:** The audience sees that connecting a third-party ITSM tool takes the same effort as connecting the Azure MCP server — a single connector configuration. MCP is the universal integration layer.

#### Scene 4.3: Incident Detection → Jira Ticket Creation (5 min)

This scene demonstrates the SRE Agent detecting a problem via Azure Monitor and automatically creating a Jira incident ticket with full context.

If the chaos experiment from Part 3 has ended, trigger a fresh incident by manually deleting a payment-service pod:

```bash
kubectl delete pod -n production -l app=payment-service
```

Or, if the Part 3 chaos experiment is still recent, reference that investigation. Ask the agent:

> *"A payment-service alert just fired. Investigate the issue and create a Jira incident ticket in the CONTOSO project. Set priority based on business impact. Include the affected services, error rates from Application Insights, and the root cause in the ticket description."*

**What the agent does:**

1. **Investigates** — Checks AKS pods, Application Insights errors, correlates with recent metrics (reusing the investigative pattern from Part 3)
2. Uses `jira_create_issue` to create a ticket:
   - **Project:** CONTOSO
   - **Issue Type:** Incident
   - **Summary:** "Payment-service pod failures causing order checkout errors"
   - **Priority:** High (P2) — based on business impact analysis
   - **Description:** Full investigation summary with error rates, affected pods, timeline, and root cause
   - **Labels:** `sre-agent`, `payment-service`, `production`
3. Uses `jira_create_remote_issue_link` to link the ticket to the Azure Monitor alert URL

**What happens:** The audience sees a fully-formed Jira ticket appear in the CONTOSO project — not a stub with a title, but a complete incident record with investigation findings, error rate data, and a link back to Azure Monitor.

**Narrator:** *"The agent didn't just open a ticket. It investigated first, then created an incident record with everything the on-call engineer needs — root cause, blast radius, error rates, and a direct link to the Azure Monitor alert. Compare that to a generic alert-to-ticket integration that creates 'Pod restarting — please investigate.'"*

**Aha moment:** The ticket contains *investigation results*, not just alert metadata. The SRE Agent adds value before the ticket even reaches a human.

#### Scene 4.4: Live Investigation with Jira Work Notes (8 min)

This is the centerpiece of Part 4 — showing the agent conducting a live investigation while posting real-time work notes to the Jira ticket.

Ask the agent:

> *"Continue investigating the payment-service incident. As you investigate, post your findings as comments on the Jira ticket you just created. Check the AKS pod status, Application Insights dependency failures, PostgreSQL connection health, and whether the issue is isolated to payment-service or affecting order-api too. Update the Jira ticket priority if the impact is broader than initially assessed."*

**What the agent does (visible in both chat and Jira):**

1. **AKS investigation** — Checks pod status, describes failing pods, checks events
   - Uses `jira_add_comment` → Posts: *"Investigation step 1: AKS pod status — payment-service pod restarted 3 times in last 5 minutes. order-api pods are healthy."*
2. **Application Insights correlation** — Queries dependency failures, error rates
   - Uses `jira_add_comment` → Posts: *"Investigation step 2: Application Insights shows 35% error rate on POST /pay endpoint. GET /menus (menu-api) unaffected at 0.1% error rate."*
3. **PostgreSQL health** — Checks connection count, active queries
   - Uses `jira_add_comment` → Posts: *"Investigation step 3: PostgreSQL ordersdb healthy — 12/100 connections active, no long-running queries. Issue is at pod level, not database."*
4. **Blast radius assessment** — Determines if order-api is affected
   - Uses `jira_add_comment` → Posts: *"Investigation step 4: Blast radius confirmed — payment-service only. order-api successfully processing order creation but failing at payment step. Menu browsing unaffected."*
5. **Priority update** — If impact warrants it
   - Uses `jira_update_issue` → Updates priority from P2 to P1 if error rate exceeds 30%
6. **Transition** — Moves ticket from "Open" to "In Progress"
   - Uses `jira_get_transitions` to find available transitions, then `jira_transition_issue`

**Key aha moments:**
- Open the Jira ticket in the browser alongside the SRE Agent chat — the audience sees comments appearing in real time as the agent investigates
- Each comment reads like an SRE's investigation notes, not raw CLI output
- The agent updated the priority based on data, not guesswork
- The ticket transitioned through the workflow automatically

**Narrator:** *"Watch the Jira ticket. Every investigation step appears as a work note — in real time. If this were a real on-call shift, the incident commander could follow the investigation in Jira without joining the SRE Agent session. The agent is documenting its work as it goes. And it just escalated the priority from P2 to P1 because the error rate exceeded 30% — that's your runbook logic applied automatically."*

#### Scene 4.5: Closed-Loop Resolution & SLA Tracking (5 min)

Close the incident lifecycle by resolving the issue and demonstrating SLA awareness.

First, ask the agent to verify recovery and close the ticket:

> *"The payment-service pods seem to be recovering on their own now that the chaos experiment ended. Verify the service is healthy, then resolve the Jira ticket with a summary of what happened, how long the incident lasted, and what the business impact was."*

**What the agent does:**

1. **Validates recovery** — Checks AKS pods (all running), Application Insights (error rate back to baseline)
2. Uses `jira_add_comment` → Posts resolution summary:
   - *"Resolution: Payment-service pods stabilized after chaos experiment ended. Error rate returned to 0.2% baseline. Incident duration: ~8 minutes. Business impact: approximately 35% of payment transactions failed during the incident window."*
3. Uses `jira_transition_issue` → Moves ticket from "In Progress" to "Resolved"
4. Uses `jira_update_issue` → Adds resolution field with root cause summary

Then ask about SLA tracking:

> *"Check the SLA metrics for the Jira ticket we just resolved. How long did the incident take from creation to resolution?"*

**What the agent does:**

- Uses `jira_get_issue_sla` to retrieve SLA data
- Reports: cycle time, lead time, whether the response SLA was met

**Narrator:** *"From alert to resolution — the Jira ticket has a complete audit trail. Every investigation step documented, priority escalated based on data, and the SLA clock tracked automatically. If your compliance team asks 'What happened and how fast did we respond?' — the answer is already in Jira."*

**Final aha moment:** Ask the agent one more question to demonstrate cross-incident intelligence:

> *"Search Jira for all incidents related to payment-service in the last 7 days. Are we seeing a pattern?"*

The agent uses `jira_search` with JQL: `project = CONTOSO AND labels = payment-service AND created >= -7d ORDER BY created DESC` and reports on any recurring patterns.

**Narrator:** *"The agent just did something most teams never have time for — pattern analysis across incidents. If payment-service keeps failing during the lunch rush, the agent can identify that trend and recommend a permanent fix before it becomes an SLA violation."*

---

### Part 4.5: "Infrastructure Under Fire — Hands-Off Autonomous Remediation" (10-15 min)

**Why this part matters:** Parts 3-4 showed the agent investigating application-level failures with human prompting. Part 4.5 goes further — the **entire infrastructure disappears**, and the agent handles detection, triage, remediation, and resolution **completely hands-off**. No human typing. No prompting. The SRE on-call engineer simply watches the Jira ticket fill with investigation notes and receives a final resolution summary.

This is the demo's capstone: proof that the SRE Agent is not just a chatbot that answers questions — it's an autonomous operator that can recover infrastructure.

#### Scene 4.5.1: Trigger Node Pool Failure (2 min)

Run the node pool failure script:

```bash
./scripts/start-node-failure.sh
```

This single command:
1. **Starts an Azure Load Testing `lunch-rush` run** — generates realistic customer traffic so Application Insights has meaningful error data
2. **Starts the Chaos Studio `exp-contoso-meals-nodepool-failure` experiment** — kills pods on workload nodes
3. **Scales the AKS `workload` user node pool from 1 → 0** — all VMs deallocated, all pods evicted

**Narrator:** *"We've tested application-level failures with pod chaos. Now let's go deeper — what happens when the infrastructure itself disappears? We're scaling the entire workload node pool to zero while customer traffic is flowing. Every order-api and payment-service pod is now unschedulable. And this time, I'm not going to type anything. We'll watch the SRE Agent handle this completely hands-off."*

**Script variants:**
| Command | What It Does |
|---------|-------------|
| `./scripts/start-node-failure.sh` | Full: load test + chaos + scale to 0 |
| `./scripts/start-node-failure.sh --no-load` | Chaos + scale only (skip load test) |
| `./scripts/start-node-failure.sh --chaos-only` | Only chaos experiment (no load, no scale) |
| `./scripts/start-node-failure.sh --scale-only` | Only scale to 0 (no load, no chaos) |
| `./scripts/start-node-failure.sh --test-id baseline` | Full with a different load test |
| `./scripts/start-node-failure.sh --restore` | Restore node pool to 1 node |

#### Scene 4.5.2: Hands-Off — Watch the Agent Work (8-12 min)

**Do nothing.** Open three views side-by-side:
- **SRE Agent chat** — watch the agent receive alerts and begin investigating
- **Jira CONTOSO board** — ticket appears and fills with real-time investigation comments
- **Terminal:** `kubectl get pods -n production -w` — pods go Pending → Running after remediation

**What happens autonomously:**

| Time | Agent Action |
|------|-------------|
| T+1-2 min | Azure Monitor alerts fire: Node NotReady, Node Pool Scaled to Zero, Pods Unschedulable |
| T+2 min | Agent creates P1 Jira ticket with blast radius and affected services |
| T+2-3 min | Investigation comment: *"AKS workload pool has 0/1 nodes ready"* |
| T+3-4 min | Investigation comment: *"order-api and payment-service pods in Pending state — FailedScheduling"* |
| T+4-5 min | Investigation comment: *"Application Insights shows error rate spiked from 0.2% to 100%"* |
| T+5 min | Root cause: *"workload node pool scaled to 0 — no compute available"* |
| T+5-6 min | **Remediation:** Agent scales node pool back to 1 node |
| T+8-10 min | **Verification:** Node Ready, pods Running, error rate returning to baseline |
| T+10-12 min | **Resolution:** Jira ticket closed with full incident timeline and business impact |

**Narrator:** *"Watch the Jira ticket. Every investigation step appears as a work note — node pool status, pod scheduling failures, error rate quantified from the load test. The agent determined the root cause, scaled the infrastructure back, verified recovery, and closed the ticket. From detection to resolution — fully autonomous, fully hands-off."*

**Key aha moments:**
- The agent **remediated infrastructure** (scaled a node pool), not just reported on it
- Business impact was quantified using the load test data: *"100% of orders failed for X minutes"*
- The Jira ticket has a complete audit trail — no human intervention required
- The on-call engineer received a clean incident report without lifting a finger

#### Scene 4.5.3: Manual Restore (fallback)

If the SRE Agent doesn't auto-remediate (e.g., agent mode is `Review` instead of `Autonomous`):

```bash
./scripts/start-node-failure.sh --restore
```

**Narrator:** *"In Review mode, the agent would propose the remediation and wait for approval. In Autonomous mode — which we just saw — it executed immediately. The mode is a Bicep parameter: `sreAgentMode: 'Autonomous'`."*

---

## 7. Infrastructure as Code: Bicep with Azure Verified Modules

### Project Structure

```
contoso-meals-sre/
├── infra/
│   ├── main.bicep                # Orchestrator — deploys all modules including SRE Agent
│   ├── main.parameters.json      # Environment-specific configuration
│   └── modules/
│       ├── sre-agent.bicep       # SRE Agent resource (Microsoft.App/agents@2025-05-01-preview)
│       ├── sre-agent-role.bicep  # Tiered role assignments (High/Low access)
│       ├── sre-agent-role-target.bicep  # Cross-RG role assignments
│       ├── monitoring.bicep      # Log Analytics, App Insights, Alerts
│       └── chaos.bicep           # Chaos Studio targets + experiments + role assignments
├── app/
│   ├── order-api/                # .NET 9 order management service
│   │   ├── src/
│   │   └── Dockerfile
│   ├── payment-service/          # .NET 9 payment processing (fault-injectable)
│   │   ├── src/
│   │   └── Dockerfile
│   └── menu-api/                 # .NET 9 restaurant menu catalog
│       ├── src/
│       └── Dockerfile
├── manifests/
│   ├── namespace.yaml            # production namespace
│   ├── order-api.yaml            # AKS deployment + service (LoadBalancer)
│   └── payment-service.yaml      # AKS deployment + service (LoadBalancer, fault-injectable)
├── load-tests/
│   ├── baseline.jmx              # 10 VU steady-state test (JMeter, parameterized endpoints)
│   └── lunch-rush.jmx            # 50 VU peak load test (JMeter, parameterized endpoints)
├── scripts/
│   ├── deploy.sh                 # Full deployment (infra + apps + .env + load tests + chaos)
│   ├── teardown.sh               # Clean teardown
│   ├── generate-load.sh          # Local curl-based baseline traffic (~5 req/s)
│   ├── seed-data.sh              # Seed customers, restaurants, orders via API
│   ├── post-provision.sh         # Runs after azd provision (secrets, env vars)
│   ├── post-deploy.sh            # Runs after azd deploy (configures AKS IPs on web-ui)
│   └── setup-jira.sh             # Jira SM initial setup (project, workflow, API token)
├── .env.example                  # Template for service endpoints (copy to .env)
├── .env                          # Auto-generated by deploy.sh (gitignored)
└── knowledge/
    ├── contoso-meals-runbook.md   # Upload to SRE Agent Knowledge Base
    └── jira-itsm-runbook.md      # Jira ITSM escalation procedures
```

### main.bicep (Orchestrator)

```bicep
targetScope = 'subscription'

@description('Deployment region')
param location string = 'swedencentral'

@description('Environment prefix')
param prefix string = 'contoso-meals'

@description('Enable Chaos Studio experiments')
param enableChaos bool = true

@description('Enable Azure Load Testing')
param enableLoadTesting bool = true

@description('Enable Jira Service Management deployment')
param enableJira bool = true

@description('Enable Azure SRE Agent provisioning via Bicep')
param enableSreAgent bool = true

@description('SRE Agent access level: High (Contributor) or Low (Reader)')
@allowed(['High', 'Low'])
param sreAgentAccessLevel string = 'High'

@description('SRE Agent mode: Review (requires approval), Autonomous, or ReadOnly')
@allowed(['Review', 'Autonomous', 'ReadOnly'])
param sreAgentMode string = 'Review'

@description('Additional resource group names the SRE Agent should have access to')
param targetResourceGroups array = []

@description('Subscription IDs for target resource groups (parallel array)')
param targetSubscriptions array = []

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${prefix}'
  location: location
}

// Log Analytics Workspace (AVM)
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  scope: rg
  name: 'log-analytics'
  params: {
    name: 'law-${prefix}'
    location: location
  }
}

// Key Vault (AVM)
module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  scope: rg
  name: 'key-vault'
  params: {
    name: 'kv-${prefix}'
    location: location
    enableRbacAuthorization: true
  }
}

// AKS Cluster — hosts order-api and payment-service (AVM)
module aks 'br/public:avm/res/container-service/managed-cluster:0.12.0' = {
  scope: rg
  name: 'aks-cluster'
  params: {
    name: 'aks-${prefix}'
    location: location
    primaryAgentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: 'Standard_B2s'
        mode: 'System'
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    omsAgentEnabled: true
    monitoringWorkspaceResourceId: logAnalytics.outputs.resourceId
  }
}

// Container App Environment — hosts menu-api (AVM)
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.8.1' = {
  scope: rg
  name: 'container-app-env'
  params: {
    name: 'cae-${prefix}'
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
  }
}

// menu-api Container App — restaurant catalog service (AVM)
module menuApi 'br/public:avm/res/app/container-app:0.12.0' = {
  scope: rg
  name: 'menu-api'
  params: {
    name: 'menu-api'
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'menu'
        image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
        resources: {
          cpu: '0.5'
          memory: '1Gi'
        }
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    ingressTargetPort: 8080
  }
}

// PostgreSQL — ordersdb for order-api and payment-service, jiradb for Jira SM (AVM)
module postgres 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.12.0' = {
  scope: rg
  name: 'postgres'
  params: {
    name: 'psql-${prefix}'
    location: location
    skuName: 'Standard_B1ms'
    tier: 'Burstable'
    administratorLogin: 'contosoadmin'
    administratorLoginPassword: keyVault.outputs.resourceId
    databases: [
      { name: 'ordersdb' }
      { name: 'jiradb' }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// Cosmos DB — catalogdb for menu-api (AVM)
module cosmosdb 'br/public:avm/res/document-db/database-account:0.11.0' = {
  scope: rg
  name: 'cosmosdb'
  params: {
    name: 'cosmos-${prefix}'
    location: location
    sqlDatabases: [
      {
        name: 'catalogdb'
        containers: [
          {
            name: 'restaurants'
            paths: ['/city']
          }
          {
            name: 'menus'
            paths: ['/restaurantId']
          }
        ]
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// Azure Load Testing (AVM)
module loadTest 'br/public:avm/res/load-test-service/load-test:0.4.0' = if (enableLoadTesting) {
  scope: rg
  name: 'load-test'
  params: {
    name: 'lt-${prefix}'
    location: location
    loadTestDescription: 'Contoso Meals baseline and lunch rush load tests'
    managedIdentities: {
      systemAssigned: true
    }
  }
}

// Storage Account for Jira home directory (AVM)
module storageAccount 'br/public:avm/res/storage/storage-account:0.14.0' = if (enableJira) {
  scope: rg
  name: 'storage-jira'
  params: {
    name: 'st${replace(prefix, '-', '')}'
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    fileServices: {
      shares: [
        {
          name: 'jira-home'
          shareQuota: 10
        }
      ]
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// Jira Service Management Container App (AVM)
module jiraSm 'br/public:avm/res/app/container-app:0.12.0' = if (enableJira) {
  scope: rg
  name: 'jira-sm'
  params: {
    name: 'jira-sm'
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'jira'
        image: 'atlassian/jira-servicemanagement:10.0'
        resources: {
          cpu: '2'
          memory: '4Gi'
        }
        env: [
          { name: 'ATL_JDBC_URL', value: 'jdbc:postgresql://psql-${prefix}.postgres.database.azure.com:5432/jiradb' }
          { name: 'ATL_JDBC_USER', value: 'contosoadmin' }
          { name: 'ATL_JDBC_PASSWORD', secretRef: 'jira-db-password' }
          { name: 'ATL_DB_DRIVER', value: 'org.postgresql.Driver' }
          { name: 'ATL_DB_TYPE', value: 'postgres72' }
          { name: 'JVM_MINIMUM_MEMORY', value: '1024m' }
          { name: 'JVM_MAXIMUM_MEMORY', value: '2048m' }
        ]
        volumeMounts: [
          {
            volumeName: 'jira-home'
            mountPath: '/var/atlassian/application-data/jira'
          }
        ]
      }
    ]
    volumes: [
      {
        name: 'jira-home'
        storageType: 'AzureFile'
        storageName: 'jira-home-storage'
      }
    ]
    ingressTargetPort: 8080
    managedIdentities: {
      systemAssigned: true
    }
  }
}

// mcp-atlassian MCP Server Container App (AVM)
module mcpAtlassian 'br/public:avm/res/app/container-app:0.12.0' = if (enableJira) {
  scope: rg
  name: 'mcp-atlassian'
  params: {
    name: 'mcp-atlassian'
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'mcp-atlassian'
        image: 'ghcr.io/sooperset/mcp-atlassian:latest'
        resources: {
          cpu: '0.5'
          memory: '0.5Gi'
        }
        args: [
          '--transport', 'streamable-http'
          '--stateless'
          '--port', '9000'
        ]
        env: [
          { name: 'JIRA_URL', value: 'https://jira-sm.${containerAppEnv.outputs.defaultDomain}' }
          { name: 'JIRA_USERNAME', value: 'admin' }
          { name: 'JIRA_API_TOKEN', secretRef: 'jira-api-token' }
        ]
      }
    ]
    ingressTargetPort: 9000
    managedIdentities: {
      systemAssigned: true
    }
  }
}

// Monitoring: Alert Rules
module monitoring './modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    aksResourceId: aks.outputs.resourceId
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    prefix: prefix
  }
}

// Chaos Studio (optional)
module chaos './modules/chaos.bicep' = if (enableChaos) {
  scope: rg
  name: 'chaos-studio'
  params: {
    aksResourceId: aks.outputs.resourceId
    prefix: prefix
  }
}

// Azure SRE Agent (optional) — deployed via Bicep instead of manual portal creation
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/
module sreAgent './modules/sre-agent.bicep' = if (enableSreAgent) {
  scope: rg
  name: 'sre-agent'
  params: {
    agentName: '${prefix}-sre'
    location: location
    userAssignedIdentityId: sreAgentIdentity.outputs.resourceId
    appInsightsResourceId: appInsights.outputs.resourceId
    appInsightsAppId: appInsights.outputs.applicationId
    appInsightsConnectionString: appInsights.outputs.connectionString
    accessLevel: sreAgentAccessLevel
    agentMode: sreAgentMode
  }
}

// Cross-RG role assignments (enterprise multi-RG monitoring)
module targetRoleAssignments 'modules/sre-agent-role-target.bicep' = [for (targetRG, index) in targetResourceGroups: if (enableSreAgent) {
  name: 'sre-agent-target-role-${index}'
  scope: resourceGroup(length(targetSubscriptions) > index ? targetSubscriptions[index] : subscription().subscriptionId, targetRG)
  params: {
    userAssignedIdentityPrincipalId: sreAgentIdentity.outputs.principalId
    accessLevel: sreAgentAccessLevel
  }
}]
```

### modules/monitoring.bicep (Alert Rules)

```bicep
param aksResourceId string
param logAnalyticsWorkspaceId string
param prefix string

// Action Group for SRE Agent
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}-sre'
  location: 'global'
  properties: {
    groupShortName: 'SREAgent'
    enabled: true
    // SRE Agent webhook will be configured post-deployment through the portal
  }
}

// AKS Pod Restart Alert
resource podRestartAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-pod-restart-${prefix}'
  location: 'global'
  properties: {
    severity: 1
    enabled: true
    scopes: [aksResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PodRestartCount'
          metricNamespace: 'Insights.Container/pods'
          metricName: 'restartingContainerCount'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}
```

### modules/chaos.bicep (Chaos Studio)

```bicep
param aksClusterName string
param prefix string
param tags object

// Reference existing AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// Chaos Studio Target for AKS
resource chaosTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-AzureKubernetesServiceChaosMesh'
  scope: aksCluster
  properties: {}
}

// Capability: Pod Chaos
resource podChaosCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: chaosTarget
  name: 'PodChaos-2.2'
}

// Experiment: Kill payment-service pods
resource experiment 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: 'exp-${prefix}-pod-kill'
  location: resourceGroup().location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'selector1'
        targets: [
          {
            type: 'ChaosTarget'
            id: chaosTarget.id
          }
        ]
      }
    ]
    steps: [
      {
        name: 'Kill payment-service pods'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:podChaos/2.2'
                selectorId: 'selector1'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"pod-kill","mode":"one","selector":{"namespaces":["production"],"labelSelectors":{"app":"payment-service"}},"scheduler":{"cron":"*/1 * * * *"}}'
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
}

// Role assignment: Chaos experiment identity → AKS Cluster Admin
// Required for Chaos Mesh pod-kill experiments on AKS
resource experimentAksClusterAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, experiment.id, 'aks-cluster-admin')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8') // Azure Kubernetes Service Cluster Admin Role
    principalId: experiment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
```

> **Important:** The experiment's system-assigned managed identity must have the **Azure Kubernetes Service Cluster Admin Role** on the AKS cluster. This role assignment is deployed automatically via Bicep. Without this, the experiment will fail with "insufficient permissions" errors. The Chaos Mesh provider requires read/write access to AKS RBAC resources, custom resource definitions, namespaces, and pods.

---

## 8. Deployment Commands

### Environment File (.env)

All scripts read service endpoints from a `.env` file at the project root (auto-generated by `deploy.sh`). This eliminates the need for `kubectl` or `az` CLI calls to discover endpoints at runtime.

```bash
# Copy template and fill in values manually:
cp .env.example .env

# Or let deploy.sh generate it automatically after deployment.
```

The `.env` file contains all service URLs, Azure resource identifiers, and SRE Agent details. It is gitignored. The `.env.example` template is committed for reference.

### Quick Deploy (Recommended)

```bash
# Full automated deployment — provisions infrastructure, deploys apps,
# generates .env, configures load tests, sets up Chaos Studio permissions
./scripts/deploy.sh
```

The deploy script performs 9 steps:
1. Deploy Azure infrastructure via Bicep (includes Chaos Studio with AKS role assignments)
2. Retrieve deployment outputs (FQDNs, SRE Agent details)
3. Get AKS credentials
4. Create Kubernetes namespace
5. Create Kubernetes secrets
6. Build and push container images (if ACR exists)
7. Deploy AKS workloads + wait for LoadBalancer IPs + configure web-ui
8. Generate `.env` file + configure Azure Load Testing tests (baseline + lunch-rush)
9. Verify deployment

### Step-by-Step Deployment

```bash
# Step 1: Deploy infrastructure (including SRE Agent and Chaos Studio via Bicep)
az deployment sub create \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
# Output includes: sreAgentPortalUrl, sreAgentIdentityClientId
# Chaos Studio role assignments are deployed automatically

# Step 2: Get AKS credentials (Entra ID RBAC)
az aks get-credentials \
  --resource-group rg-contoso-meals \
  --name aks-contoso-meals

# Step 3: Create namespace, secrets, and deploy apps
kubectl create namespace production
kubectl create secret generic contoso-meals-secrets -n production \
  --from-literal=orders-db-connection-string="Host=psql-contoso-meals-db.postgres.database.azure.com;..." \
  --from-literal=appinsights-connection-string="InstrumentationKey=..."
kubectl apply -f manifests/order-api.yaml
kubectl apply -f manifests/payment-service.yaml

# Step 4: Wait for AKS LoadBalancer external IPs (order-api + payment-service)
kubectl get svc -n production -w
# Wait until EXTERNAL-IP appears for both services

# Step 5: Configure web-ui Container App with AKS backend URLs
ORDER_API_IP=$(kubectl get svc order-api -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
PAYMENT_IP=$(kubectl get svc payment-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
MENU_API_FQDN=$(az containerapp show --name menu-api --resource-group rg-contoso-meals \
  --query properties.configuration.ingress.fqdn -o tsv)

az containerapp update --name web-ui --resource-group rg-contoso-meals \
  --set-env-vars "MENU_API_URL=https://${MENU_API_FQDN}" \
    "ORDER_API_URL=http://${ORDER_API_IP}" \
    "PAYMENT_API_URL=http://${PAYMENT_IP}"

# Step 6: Seed data (customers, restaurants, orders)
./scripts/seed-data.sh \
  --menu-api "https://${MENU_API_FQDN}" \
  --order-api "http://${ORDER_API_IP}" \
  --customers 20 --restaurants 15

# Step 7: Run baseline load test (30+ min before demo)
# Option A: Local curl-based load generation
./scripts/generate-load.sh 60
# Option B: Azure Load Testing (from portal or CLI)
az load test-run create --load-test-resource lt-contoso-meals \
  --resource-group rg-contoso-meals --test-id baseline \
  --test-run-id "baseline-$(date +%Y%m%d-%H%M)"

# Step 8: Open SRE Agent in portal (deployed automatically via Bicep)
# The deployment output 'sreAgentPortalUrl' provides a direct link
# Configure MCP, Teams, Knowledge Base (manual — see Part 1)

# Step 9: Wait for Jira SM to initialize (first boot takes 3-5 min)
JIRA_FQDN=$(az containerapp show \
  --name jira-sm \
  --resource-group rg-contoso-meals \
  --query properties.configuration.ingress.fqdn -o tsv)
echo "Jira SM URL: https://${JIRA_FQDN}"

# Step 10: Run Jira initial setup script
./scripts/setup-jira.sh

# Step 11: Verify mcp-atlassian is serving MCP endpoint
MCP_FQDN=$(az containerapp show \
  --name mcp-atlassian \
  --resource-group rg-contoso-meals \
  --query properties.configuration.ingress.fqdn -o tsv)
curl -s "https://${MCP_FQDN}/mcp" | jq .

# Step 12: Configure mcp-atlassian as Custom MCP Server in SRE Agent (manual — see Part 4)
```

### Running Chaos Studio Experiments

The chaos experiment `exp-contoso-meals-pod-kill` is deployed via Bicep with the required AKS Cluster Admin role assignment. Run it from:

```bash
# CLI
az chaos experiment start \
  --name exp-contoso-meals-pod-kill \
  --resource-group rg-contoso-meals

# Or from Azure Portal:
# Azure Portal > Chaos Studio > Experiments > exp-contoso-meals-pod-kill > Start
```

The experiment kills one payment-service pod every 60 seconds for 5 minutes. For best demo impact, run the experiment while the lunch-rush load test is active.

### Running Azure Load Testing

Load tests are configured by `deploy.sh` with the correct endpoint URLs. The JMX test plans use parameterized hosts injected as environment variables.

```bash
# Run baseline test (steady-state: 10 VUs, ~5 req/s, 30 min)
az load test-run create --load-test-resource lt-contoso-meals \
  --resource-group rg-contoso-meals --test-id baseline \
  --test-run-id "baseline-$(date +%Y%m%d-%H%M)"

# Run lunch-rush test (peak: 50 VUs, ~20 req/s, 10 min)
az load test-run create --load-test-resource lt-contoso-meals \
  --resource-group rg-contoso-meals --test-id lunch-rush \
  --test-run-id "lunch-rush-$(date +%Y%m%d-%H%M)"

# Or use the local curl-based load generator (no Azure Load Testing needed):
./scripts/generate-load.sh 30    # 30 min, ~5 req/s
./scripts/generate-load.sh 10 20 # 10 min, ~20 req/s
```

### Using Azure Developer CLI (azd)

```bash
# Full lifecycle with hooks
azd up    # provision + deploy + post-provision + post-deploy hooks

# Or step-by-step
azd provision    # Bicep deployment → runs post-provision.sh
azd deploy       # Deploy all services → runs post-deploy.sh (configures LoadBalancer IPs)
```

The `azd deploy` flow automatically runs `scripts/post-deploy.sh` which:
- Waits for AKS LoadBalancer external IPs
- Configures `ORDER_API_URL` and `PAYMENT_API_URL` on web-ui Container App

### Available Scripts

| Script | Purpose |
|--------|---------|
| `scripts/deploy.sh` | Full deployment (infra + apps + .env + load tests + chaos verification) |
| `scripts/post-provision.sh` | Runs after `azd provision` (secrets, env vars) |
| `scripts/post-deploy.sh` | Runs after `azd deploy` (configures AKS LoadBalancer IPs on web-ui) |
| `scripts/seed-data.sh` | Seeds customers, restaurants, and orders via API (reads .env) |
| `scripts/generate-load.sh` | Local curl-based load generation (~5 req/s, reads .env) |
| `scripts/setup-jira.sh` | Configures Jira project, workflow, and API token |
| `scripts/teardown.sh` | Clean teardown of all resources |

---

## 9. Why This Demo Is Different — Competitive Positioning

| Capability | Azure SRE Agent + MCP | Datadog AI Bot | PagerDuty AIOps | Dynatrace Davis |
|-----------|----------------------|----------------|-----------------|-----------------|
| Cross-service reasoning in one conversation | 42+ Azure services via MCP | Datadog metrics only | PagerDuty alerts only | Dynatrace data only |
| Natural-language remediations with approval | Yes (az CLI, kubectl) | No (read-only) | No | Limited |
| Custom subagents (no-code) | Yes (Subagent Builder) | No | No | No |
| Persistent memory across sessions | Yes (#remember, Knowledge Base) | No | No | No |
| Chaos engineering correlation | Yes (detects Chaos Studio experiments) | No | No | No |
| Enterprise IaC (Bicep/AVM) | Native Azure | N/A | N/A | N/A |
| GitHub Copilot handoff for PRs | Yes | No | No | No |
| ITSM extensibility via MCP (any platform) | Yes (Jira, ServiceNow, any MCP-compatible) | No | PagerDuty only | No |

---

## 10. Official SRE Agent Samples — Integration Plan

> **Source repository:** [microsoft/sre-agent](https://github.com/microsoft/sre-agent) (public, MIT-licensed)
> **Key paths:** `samples/bicep-deployment/`, `samples/automation/`, `samples/proactive-reliability/`

Microsoft has published official samples for the Azure SRE Agent that include Infrastructure-as-Code templates, end-to-end incident automation walkthroughs, proactive reliability patterns, and reusable subagent YAML definitions. This section analyzes each sample area and outlines how we integrate them into the Contoso Meals demo.

### 10.1 Bicep Deployment Templates — Automating SRE Agent Provisioning

#### What the Official Repo Provides

The `samples/bicep-deployment/` folder contains a **subscription-scoped Bicep template** that fully automates SRE Agent creation — something we currently do manually in Part 1 of the demo.

| File | Purpose |
|------|---------|
| `minimal-sre-agent.bicep` | Subscription-scoped entry point — creates the resource group reference, invokes modules |
| `sre-agent-resources.bicep` | Resource group-scoped module: Log Analytics Workspace, Application Insights, User-Assigned Managed Identity, Smart Detection alert rules, and the **`Microsoft.App/agents@2025-05-01-preview`** resource with `knowledgeGraphConfiguration`, `actionConfiguration`, and `logConfiguration` |
| `role-assignments-minimal.bicep` | Role assignments for the deployment RG (Reader, Contributor, Log Analytics Reader based on access level; Key Vault Certificate/Secrets User) |
| `role-assignments-target.bicep` | Role assignments for **target** resource groups — enables multi-RG and cross-subscription monitoring |
| `deploy.sh` | Interactive bash script with 3 modes: interactive prompts, config file, and CLI flags |
| `minimal-sre-agent.parameters.json` | Example parameters file |

#### Key Capabilities — Now Implemented

| Capability | Official Template | Our Implementation |
|-----------|-------------------|-------------------|
| **Automated SRE Agent provisioning** | `Microsoft.App/agents@2025-05-01-preview` resource in Bicep | `infra/modules/sre-agent.bicep` — deployed alongside all infrastructure |
| **Cross-subscription targeting** | `targetResourceGroups` + `targetSubscriptions` arrays, matched by index | Supported via `targetResourceGroups` and `targetSubscriptions` parameters in `main.bicep` |
| **Configurable access levels** | `High` (Reader + Contributor + Log Analytics Reader) vs `Low` (Log Analytics Reader only) | `sreAgentAccessLevel` parameter with tiered role assignments in `sre-agent-role.bicep` |
| **Existing managed identity reuse** | `existingManagedIdentityId` parameter — supports bring-your-own identity | Uses pre-existing AVM-provisioned identity (`id-contoso-meals-sre-agent`) |
| **SRE Agent Administrator role** | Auto-assigns `e79298df-d852-4c6d-84f9-5d13249d1e55` (SRE Agent Administrator) to deployer | Auto-assigned in `sre-agent.bicep` via `deployer().objectId` |
| **Smart Detection alerts** | Failure Anomalies Smart Detector alert rule with Action Group | Provisioned in `sre-agent.bicep` with Smart Detection Action Group |
| **Agent mode selection** | `Review`, `Autonomous`, or `ReadOnly` mode parameter | `sreAgentMode` parameter in `main.bicep` (default: Review) |
| **Key Vault roles** | Certificate User + Secrets User roles | Enabled in `sre-agent-role.bicep` with `enableKeyVault: true` |

#### What Was Done

The manual SRE Agent creation in Part 1 Scene 1.1 has been replaced with a single `az deployment sub create` that provisions the agent alongside all other infrastructure.

1. **Added `infra/modules/sre-agent.bicep`** — Adapted from `sre-agent-resources.bicep`, deploys `Microsoft.App/agents@2025-05-01-preview` with Smart Detection alerts and SRE Agent Administrator role
2. **Upgraded `infra/modules/sre-agent-role.bicep`** — Tiered role model (High/Low access) from `role-assignments-minimal.bicep`, including Key Vault Certificate User and Secrets User roles
3. **Added `infra/modules/sre-agent-role-target.bicep`** — Cross-RG role assignments from `role-assignments-target.bicep` for multi-RG enterprise scenarios
4. **Updated `infra/main.bicep`** — New parameters (`enableSreAgent`, `sreAgentAccessLevel`, `sreAgentMode`, `targetResourceGroups`, `targetSubscriptions`), SRE Agent module invocation, and portal URL output
5. **Updated `scripts/deploy.sh`** — Retrieves and displays `sreAgentPortalUrl`, conditionally updates next-steps messaging

**See actual implementation:** `infra/modules/sre-agent.bicep`, `infra/modules/sre-agent-role.bicep`, `infra/modules/sre-agent-role-target.bicep`

**Demo impact:** Part 1 Scene 1.0 now shows deployment output with the SRE Agent portal URL — "look, the SRE Agent was deployed alongside the entire infrastructure in a single Bicep deployment." This is more enterprise-relevant than manual portal creation.

---

### 10.2 Incident Automation — Octopets Memory Leak Pattern

#### What the Official Repo Provides

The `samples/automation/` folder contains a complete end-to-end incident automation walkthrough using a sample app called **Octopets** (a pet marketplace on Azure Container Apps).

| Sample | What It Demonstrates |
|--------|---------------------|
| **`01-incident-automation-sample.md`** | Memory leak injection → PagerDuty incident → SRE Agent diagnoses via metrics/logs → Outlook notifications → GitHub issue with proposed code fix |
| **`02-scheduled-health-check-sample.md`** | Daily scheduled task at 8 AM → `healthcheckagent` subagent autonomously checks CPU/memory/error rates → conditional email if anomalies found |
| **`pd-azure-resource-error-handler.yaml`** | Full subagent YAML: 6-phase autonomous workflow (intake → diagnostics → source analysis → GitHub issue → email notifications → PD resolution) |
| **`azurehealthcheck.yaml`** | Health check subagent YAML: auto-discover scope, collect 24h metrics, anomaly detection (3-sigma/MAD), conditional email |
| **`00-configure-sre-agent.md`** | Step-by-step: connect incident platform, Outlook, GitHub repo mapping, subagent creation, incident trigger setup |
| **`octopets-setup.md`** | Deploy Octopets via `azd up`, enable error generation with `Errors=true` env var |

#### Key Patterns We Should Adopt

**1. Subagent YAML Templates for Contoso Meals**

The Octopets `pd-azure-resource-error-handler.yaml` is a masterclass in autonomous subagent design. Its 6-phase process — intake, diagnostics, source/IaC analysis, GitHub issue, email notifications, incident resolution — should be adapted for Contoso Meals:

> **YAML definition:** [`subagents/contoso-meals-incident-handler.yaml`](subagents/contoso-meals-incident-handler.yaml)
>
> Full incident handler with 5-phase process (Intake → Investigation → Assessment → Jira → Remediation Decision), Jira MCP integration, and handoffs to AutoRemediator + ResilienceValidator.

**2. Scheduled Health Check for Contoso Meals**

Adapt `azurehealthcheck.yaml` for a daily Contoso Meals health check:

> **YAML definition:** [`subagents/contoso-meals-health-check.yaml`](subagents/contoso-meals-health-check.yaml)
>
> Daily anomaly detection across AKS, PostgreSQL, Cosmos DB, and Container Apps with conditional email notification.

**3. Demo Enhancement: Show the Scheduled Task Configuration**

Add a new scene to **Part 3** that demonstrates setting up a scheduled daily health check — directly mirroring the official `02-scheduled-health-check-sample.md`:

> **Part 3, Scene 3.6 (NEW): "Scheduled Health Checks"** (3 min)
>
> Navigate to SRE Agent → Scheduled Tasks → Create:
> - Task Name: `Daily Contoso Meals Health Check`
> - Response Subagent: `ContosoMealsHealthCheck`
> - Task Details: `check health of all Contoso Meals services`
> - Frequency: Daily at 8:00 AM
>
> **Narrator:** *"Every morning at 8 AM before your team starts, the agent proactively checks all services and emails your team only if something looks wrong. No dashboard checking. No morning stand-up to review metrics."*

---

### 10.3 Proactive Reliability — Autonomous Remediation Pattern (.NET Day Demo)

#### What the Official Repo Provides

The `samples/proactive-reliability/` folder contains the **.NET Day 2025** demo — a sophisticated pattern where the SRE Agent autonomously detects performance degradation after a deployment and rolls back by executing a slot swap **without human approval**.

| Component | Purpose |
|-----------|---------|
| **`AvgResponseBaseline.yaml`** | Scheduled subagent: queries App Insights for avg response time, stores `baseline.txt` in Knowledge Base |
| **`DeploymentHealthCheck.yaml`** | Incident-triggered subagent: compares current response time to baseline, auto-swaps slots if >20% degradation, creates GitHub issue, posts to Teams |
| **`DeploymentReporter.yaml`** | Scheduled subagent: reads Teams posts, builds deployment summary email with MTTD/MTTR metrics |
| **`DynatraceLogAnalysisSubagent.yaml`** | Extends to Dynatrace log analysis via MCP (multi-cloud observability) |
| **`DeploymentRemediationSubagent.yaml`** | Dynatrace-Azure deployment remediation via MCP |
| **`1-setup-demo.ps1`** | One-time setup: deploys infra, builds healthy + problematic code, deploys to production + staging slots |
| **`2-run-demo.ps1`** | Live demo: slot swap (bad → production), load generation, agent detects + remediates |
| **`infrastructure/main.bicep`** | App Service with staging slot, App Insights, Activity Log alerts |

#### The Three-Subagent Architecture

This is the most sophisticated pattern in the official samples — a **three-subagent pipeline** with different trigger types:

```
┌─────────────────────────────────────────────────────────────────────┐
│  PROACTIVE RELIABILITY PIPELINE (from microsoft/sre-agent samples) │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. AvgResponseTime (Scheduled - Daily)                            │
│     ├── Query App Insights: avg(duration) last 15 min              │
│     ├── Upload baseline.txt to Knowledge Base                       │
│     └── Stored: BaselineResponseTime + BaselineTimestamp            │
│                                                                     │
│  2. DeploymentHealthCheck (Incident Trigger - "slot swap" alert)   │
│     ├── Query App Insights: current avg response time               │
│     ├── Retrieve baseline.txt from Knowledge Base                   │
│     ├── Compare: if current > baseline × 1.2 → DEGRADED            │
│     ├── AUTO-EXECUTE: az webapp deployment slot swap                │
│     ├── Create GitHub issue with semantic code search               │
│     └── Post to Teams channel with deployment health report         │
│                                                                     │
│  3. DeploymentReporter (Scheduled - Daily)                          │
│     ├── Read Teams messages for deployment health posts              │
│     ├── Compile MTTD/MTTR metrics                                   │
│     └── Send summary email to ops team                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Demo timeline from their walkthrough:**

| Time | Event |
|------|-------|
| 0:00 | Run demo script — shows healthy production (~50ms) |
| 0:30 | Slot swap executes — bad code goes to production (~1500ms) |
| 1:30 | Load generation begins |
| ~5:00 | Activity Log alert fires (slot swap detected) |
| ~5:01 | SRE Agent incident trigger activates `DeploymentHealthCheck` |
| ~5:03 | Agent compares metrics to baseline → detects 20%+ degradation |
| ~5:04 | **Agent autonomously executes slot swap (rollback)** — no human approval |
| ~5:30 | Production restored to healthy state |
| ~6:00 | Agent posts to Teams, creates GitHub issue |

#### Integration Plan for Contoso Meals

**Option A: Adapt for App Service Slot Swap (New Scene)**

Add menu-api as an App Service (instead of Container App) with staging slot, then demonstrate autonomous rollback:

> **Part 5 (NEW): "Proactive Reliability — Fix Before They Feel It"** (10-15 min)
>
> **Scene 5.1: Baseline Learning** — Show the AvgResponseTime subagent capturing menu-api baseline response time and storing it in Knowledge Base.
>
> **Scene 5.2: Bad Deployment** — Swap staging slot (with artificial delay code) to production. Load Testing generates traffic. App Insights ingests degraded metrics.
>
> **Scene 5.3: Autonomous Remediation** — SRE Agent detects degradation, compares to baseline, and **autonomously executes slot swap rollback** without human approval. Posts to Teams, creates GitHub issue.
>
> **Narrator:** *"The agent learned what 'normal' looks like. When a bad deployment broke that pattern, it rolled back production in under a minute — before a single customer ticket was filed. Fix it before they feel it."*

**Option B: Adapt for AKS Rollback (Contoso Meals Native)**

Keep the AKS architecture but adapt the pattern for `kubectl rollout undo`:

```yaml
# Proposed scene: Agent detects payment-service degradation after a deployment,
# compares to stored baseline, and autonomously executes:
#   kubectl rollout undo deployment/payment-service -n production
# Then posts to Teams and creates GitHub issue.
```

**Option C: Reference as Advanced Demo Extension**

Keep the current four-part demo structure and reference the proactive reliability pattern as an "Advanced Demo Extension" for audiences interested in autonomous remediation and deployment safety.

#### Recommended Approach: Option C (Reference) + Subagent YAMLs from Option A

Keep the current demo focused on the four-part narrative, but:
1. Create `ContosoMealsBaselineCapture.yaml` and `ContosoMealsDeploymentHealthCheck.yaml` subagent files in the repo
2. Add a Section to Part 3 Scene 3.5 (Subagent Builder) that references the proactive reliability pattern
3. Include the `.NET Day 2025` YouTube link as an advanced resource

---

### 10.4 Dynatrace & Multi-Cloud Observability Extension

The `proactive-reliability/SubAgents/` folder includes two new subagents added 2 weeks ago:

| Subagent | What It Does |
|----------|-------------|
| **`DynatraceLogAnalysisSubagent.yaml`** | Log analysis via Dynatrace MCP — extends SRE Agent to query non-Azure observability platforms |
| **`DeploymentRemediationSubagent.yaml`** | Deployment remediation combining Dynatrace signals with Azure actions |

**Demo Relevance:** For customers running hybrid/multi-cloud, this proves Azure SRE Agent is not Azure-only — it can ingest signals from Dynatrace, Datadog, or any MCP-enabled observability platform and still execute Azure remediation actions. This strengthens the competitive positioning in Section 9.

**Proposed mention in demo:** Add to Part 2 Scene 2.3 discussion:
> *"And if you're running Dynatrace or Datadog alongside Azure Monitor, the same MCP pattern applies — the official SRE Agent samples include Dynatrace log analysis subagents that query via MCP and correlate with Azure actions."*

---

### 10.5 Summary — What to Build from Official Samples

| Item | Source | Target in Our Repo | Status |
|------|--------|-------------------|--------|
| SRE Agent Bicep module (`Microsoft.App/agents`) | `sre-agent-resources.bicep` | `infra/modules/sre-agent.bicep` | **Done** |
| Tiered role assignments (High/Low) | `role-assignments-minimal.bicep` | `infra/modules/sre-agent-role.bicep` | **Done** |
| Cross-subscription targeting parameters | `minimal-sre-agent.bicep` | `infra/main.bicep` + `infra/modules/sre-agent-role-target.bicep` | **Done** |
| SRE Agent Administrator role assignment | `sre-agent-resources.bicep` | `infra/modules/sre-agent.bicep` | **Done** |
| Smart Detection alert rules | `sre-agent-resources.bicep` | `infra/modules/sre-agent.bicep` | **Done** |
| Deploy script SRE Agent output | `deploy.sh` | `scripts/deploy.sh` | **Done** |
| Incident handler subagent YAML | `pd-azure-resource-error-handler.yaml` | `subagents/contoso-meals-incident-handler.yaml` | **Done** |
| Daily health check subagent YAML | `azurehealthcheck.yaml` | `subagents/contoso-meals-health-check.yaml` | **Done** |
| Auto-remediator subagent YAML | *(custom)* | `subagents/contoso-meals-auto-remediator.yaml` | **Done** |
| Resilience validator subagent YAML | *(custom)* | `subagents/contoso-meals-resilience-validator.yaml` | **Done** |
| Baseline capture subagent YAML | `AvgResponseBaseline.yaml` | `subagents/contoso-meals-baseline-capture.yaml` | **P2** — proactive reliability |
| Deployment health check subagent YAML | `DeploymentHealthCheck.yaml` | `subagents/contoso-meals-deployment-health.yaml` | **P2** — autonomous remediation |
| Deployment reporter subagent YAML | `DeploymentReporter.yaml` | `subagents/contoso-meals-deployment-reporter.yaml` | **P2** — daily summary |
| Interactive deploy script | `deploy.sh` | `scripts/deploy-sre-agent.sh` | **P2** — standalone SRE Agent deployment |

### 10.6 Updated Reference Resources

| Resource | URL |
|----------|-----|
| Official SRE Agent Samples (GitHub) | https://github.com/microsoft/sre-agent/tree/main/samples |
| Bicep Deployment Guide | https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/deployment-guide.md |
| Incident Automation Sample (Octopets) | https://github.com/microsoft/sre-agent/blob/main/samples/automation/samples/01-incident-automation-sample.md |
| Scheduled Health Check Sample | https://github.com/microsoft/sre-agent/blob/main/samples/automation/samples/02-scheduled-health-check-sample.md |
| Configure SRE Agent Guide | https://github.com/microsoft/sre-agent/blob/main/samples/automation/configuration/00-configure-sre-agent.md |
| PD Error Handler Subagent YAML | https://github.com/microsoft/sre-agent/blob/main/samples/automation/subagents/pd-azure-resource-error-handler.yaml |
| Health Check Subagent YAML | https://github.com/microsoft/sre-agent/blob/main/samples/automation/subagents/azurehealthcheck.yaml |
| Proactive Reliability Demo (.NET Day) | https://github.com/microsoft/sre-agent/tree/main/samples/proactive-reliability |
| .NET Day 2025 YouTube Video | https://www.youtube.com/watch?v=Kx_6SB-mhgg |
| Octopets Sample App | https://github.com/Azure-Samples/octopets |
| Dynatrace Subagents | https://github.com/microsoft/sre-agent/tree/main/samples/proactive-reliability/SubAgents |

---

## 11. Timing Variants

### Full Demo (85-100 min)
All five parts (1-4 + 4.5) + Q&A. Part 5 (Proactive Reliability) is optional — include for audiences interested in autonomous deployment rollback.

### Full Demo without Part 4.5 (70-85 min)
Parts 1-4 + Q&A. Best for dedicated customer workshops or partner enablement. Part 4 can be omitted for audiences already using ServiceNow (built-in integration).

### Conference Demo (30-40 min)
- Scene 1.0: IaC deployment (show Bicep output with SRE Agent portal URL) — 2 min
- Part 1: Scene 1.2 (MCP connection) + 1.5 (smoke test) — 7 min
- Part 2: Scene 2.0 (morning health report) + Scene 2.1 (cross-service investigation) — 10 min
- Part 3: Scene 3.2-3.3 (pre-triggered chaos + closed loop) — 10 min
- Part 4.5: Node pool failure hands-off (pre-triggered, show Jira trail) — 5 min

### Executive Demo (15-17 min)
- Part 1: Describe MCP connection (pre-configured) — 2 min
- Part 2: Live cross-service investigation — 5 min
- Part 3: Pre-triggered chaos investigation + Teams notification — 5 min
- Part 4.5: Show node pool failure Jira ticket trail (hands-off) — 5 min

### Lightning Demo (8 min)
Everything pre-configured. Open the agent chat and run Scene 2.1 (cross-service investigation) live. This single scene demonstrates the unique value.

### ITSM-Focused Demo (30 min)
For customers evaluating ITSM integration. Everything pre-configured.
- Part 1: Scene 1.2 (MCP connection, pre-configured) — 3 min
- Part 3: Scene 3.3 (agent investigates, pre-triggered chaos) — 7 min
- Part 4: All scenes (Jira SM end-to-end) — 20 min

---

## 12. Handling Failures & Fallbacks

| Situation | Recovery |
|-----------|----------|
| MCP connection fails | Pre-configure it before the demo. If it fails live, explain what it would provide and show the connector UI. |
| Chaos Studio experiment doesn't affect pods | Manually delete a pod: `kubectl delete pod -n production -l app=payment-service` |
| Agent is slow (1-3 min for investigation) | Explain what it's doing: *"It's running kubectl, querying Log Analytics, checking Activity Log, and correlating."* Compare to manual effort. |
| Agent gives generic/shallow response | Follow up with specific prompts: *"Check kubectl logs for payment-service pods. Are they restarting?"* |
| Alerts don't fire | Drive investigation conversationally: *"Can you investigate the payment-service?"* |
| Infrastructure deployment fails | Fall back to [tannenbaum-gmbh/sre-agent](https://github.com/tannenbaum-gmbh/sre-agent) (Bicep + AVM + Chaos Studio, ready to deploy) |
| Jira SM Container App slow to start | First boot takes 3-5 minutes. Pre-warm the instance 24 hours before. If it fails, show screenshots of the Jira ticket lifecycle. |
| mcp-atlassian connection fails | Verify the endpoint URL is correct (`/mcp` path). Check Container App logs. Fallback: show the mcp-atlassian GitHub repo and explain the architecture. |
| Jira ticket creation fails | Check JIRA_API_TOKEN env var in mcp-atlassian. Verify the CONTOSO project exists. Fallback: create the ticket manually in Jira and continue from Scene 4.4. |
| Agent doesn't use Jira tools | Ensure the Custom MCP Server connector is saved and active. Ask explicitly: *"Use your Jira tools to create an incident ticket."* |

---

## 13. Pre-Demo Checklist

### T-24 Hours
- [ ] Run `az deployment sub create` to deploy all infrastructure
- [ ] Deploy Kubernetes manifests to AKS
- [ ] Create URL-based load tests in Azure Load Testing (baseline + lunch rush)
- [ ] Start baseline load test — run for 30+ minutes to build metrics history
- [ ] Verify SRE Agent was deployed (check portal URL from deployment output)
- [ ] Configure MCP, Teams, Knowledge Base in SRE Agent portal
- [ ] Upload `contoso-meals-runbook.md` to Knowledge Base
- [ ] Test Chaos Studio experiment (run once, verify pods restart, verify alert fires)
- [ ] Store MCP connector settings (take screenshots for fallback)
- [ ] Verify Jira SM Container App is running and accessible
- [ ] Complete Jira setup wizard (if first boot) — set admin password, configure project
- [ ] Run `./scripts/setup-jira.sh` to create CONTOSO project with Incident issue type and workflow
- [ ] Generate Jira API token for admin user
- [ ] Verify mcp-atlassian Container App is running and `/mcp` endpoint responds
- [ ] Configure mcp-atlassian as Custom MCP Server in SRE Agent (see Scene 4.2)
- [ ] Test Jira integration: ask agent *"Create a test ticket in the CONTOSO project"* — delete the test ticket after
- [ ] Upload `jira-itsm-runbook.md` to Knowledge Base

### T-2 Hours
- [ ] Verify SRE Agent chat is responsive
- [ ] Verify MCP tools work: ask *"What resources are in rg-contoso-meals?"*
- [ ] Verify Teams connector works
- [ ] Verify Chaos Studio experiment is in Ready state
- [ ] Verify Azure Load Testing has the baseline and lunch rush tests configured
- [ ] Start a fresh baseline load test run (keep running until demo starts)
- [ ] Clear chat history for clean demo slate
- [ ] Prepare browser tabs:
  - Tab 1: SRE Agent chat
  - Tab 2: Azure Load Testing (lunch rush test ready to start)
  - Tab 3: Chaos Studio experiments
  - Tab 4: AKS overview (pods view)
  - Tab 5: Jira SM dashboard (CONTOSO project board)
  - Tab 6: mcp-atlassian Container App (logs view, for troubleshooting)
- [ ] Verify Jira SM is responsive — open the CONTOSO project board
- [ ] Verify mcp-atlassian connector is active in SRE Agent
- [ ] Clear any test tickets from CONTOSO project

### T-5 Minutes
- [ ] Baseline load test running (or recently completed with 30+ min of data)
- [ ] All services green
- [ ] Chat history cleared
- [ ] Chaos experiment ready to start
- [ ] Lunch rush load test ready to start
- [ ] Jira SM dashboard open in browser tab with empty CONTOSO board
- [ ] mcp-atlassian connector verified active

---

## 14. Teardown

```bash
# Delete everything
az group delete --name rg-contoso-meals --yes --no-wait

# Verify
az group show --name rg-contoso-meals 2>/dev/null && \
  echo "Still deleting..." || \
  echo "Deleted successfully"
```

Approximate daily cost while running: $20-35. Tear down immediately after the demo.

---

## 15. Reference Resources

| Resource | URL |
|----------|-----|
| Azure SRE Agent Docs | https://learn.microsoft.com/en-us/azure/sre-agent/overview |
| Azure MCP Server (New Repo) | https://github.com/microsoft/mcp |
| Azure MCP Server Docs | https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview |
| Azure MCP Server Tools (Full List) | https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/tools |
| Azure Load Testing Docs | https://learn.microsoft.com/en-us/azure/load-testing/overview-what-is-azure-load-testing |
| Azure Chaos Studio Docs | https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-overview |
| MCP Center (Remote Servers) | https://mcp.azure.com/?types.remote=true |
| SRE Agent Connectors Docs | https://learn.microsoft.com/en-us/azure/sre-agent/connectors |
| Connect SRE Agent to MCP Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/how-to-connect-azure-sre-agent-to-azure-mcp/4488905 |
| Subagent Builder Docs | https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview |
| Bicep AVM Registry | https://azure.github.io/Azure-Verified-Modules/indexes/bicep/ |
| Existing Bicep+AVM Demo (tannenbaum-gmbh) | https://github.com/tannenbaum-gmbh/sre-agent |
| SRE Agent Memory Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/never-explain-context-twice-introducing-azure-sre-agent-memory/4473059 |
| Context Engineering Lessons Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200 |
| Proactive Monitoring Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/proactive-monitoring-made-simple-with-azure-sre-agent/4471205 |
| ServiceNow Integration Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/connect-azure-sre-agent-to-servicenow-end-to-end-incident-response/4487824 |
| Observability & Multi-Cloud Blog | https://techcommunity.microsoft.com/blog/appsonazureblog/azure-sre-agent-expanding-observability-and-multi-cloud-resilience/4472719 |
| Microsoft SRE Agent GitHub (Issues) | https://github.com/microsoft/sre-agent |
| SRE Agent Bicep Deployment Samples | https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment |
| SRE Agent Automation Samples | https://github.com/microsoft/sre-agent/tree/main/samples/automation |
| Proactive Reliability Demo (.NET Day 2025) | https://github.com/microsoft/sre-agent/tree/main/samples/proactive-reliability |
| .NET Day 2025 YouTube: Fix It Before They Feel It | https://www.youtube.com/watch?v=Kx_6SB-mhgg |
| DEM550 Session (YouTube) | Search: "DEM550 Azure SRE Agent" |
| Agentic Ops Workshop | https://github.com/paulasilvatech/Agentic-Ops-Dev |
| mcp-atlassian GitHub (MCP Server for Jira) | https://github.com/sooperset/mcp-atlassian |
| Jira SM Docker Image (Docker Hub) | https://hub.docker.com/r/atlassian/jira-servicemanagement |
| Atlassian REST API v3 Docs | https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/ |
| Jira Service Management Docs | https://support.atlassian.com/jira-service-management-cloud/ |

---

*This proposal is designed to position Azure SRE Agent as a connected intelligence platform, not a point tool. Adjust acts and scenes based on your audience — security-focused customers should see Part 2 Scene 2.2 (Policy checks); cost-conscious customers should see Scene 2.3 (Advisor); platform teams should see Parts 1 and 3.4 (MCP setup + Subagent Builder); ITSM-focused customers should see Part 4 (Jira SM extensibility via MCP).*
