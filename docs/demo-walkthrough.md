# Contoso Meals - Demo Walkthrough Steps

> Condensed step-by-step instructions for running the full 4-part demo.
> For detailed narration and context, refer to `demo-proposal.md`.

---

## Pre-Demo Setup (T-24h to T-5min)

### T-24h: Deploy Infrastructure
```bash
cd /path/to/azure-sre
./scripts/deploy.sh
```

### T-24h: Configure SRE Agent
1. Azure Portal → Search "Azure SRE Agent" → Create
2. RG: `rg-contoso-meals`, Region: Sweden Central, Name: `contoso-meals-sre`
3. Select managed resource group: `rg-contoso-meals`
4. Settings → Connectors → Add Custom MCP Server:
   - Type: stdio, Command: `npx`, Args: `-y, @azure/mcp, server, start`
   - Managed Identity: select `id-contoso-meals-sre-agent` from dropdown
   - Env: `AZURE_CLIENT_ID=<client-id-from-deployment-output>`, `AZURE_TOKEN_CREDENTIALS=ManagedIdentityCredential`
   - **Note:** Must use the **user-assigned** MI — system-assigned is not supported for connectors
5. Settings → Connectors → Add Microsoft Teams → OAuth → Select channel
6. Settings → Knowledge Base → Upload `knowledge/contoso-meals-runbook.md`

### T-24h: Configure Jira
```bash
./scripts/setup-jira.sh
```
Then configure mcp-atlassian connector in SRE Agent:
- Type: HTTP, URL: `https://<mcp-atlassian-fqdn>/mcp`, Auth: Custom headers
- Header: `Authorization: Token <jira-api-token>` (use `Token` prefix, not `Bearer`)

### T-2h: Verify Everything
```bash
# Verify services
kubectl get pods -n production
az containerapp list --resource-group rg-contoso-meals -o table

# Start baseline load test
./scripts/generate-load.sh 60
```

### T-5min: Browser Tabs
- Tab 1: SRE Agent chat (cleared)
- Tab 2: Azure Load Testing (lunch rush test ready)
- Tab 3: Chaos Studio experiments
- Tab 4: AKS pods view
- Tab 5: Jira CONTOSO project board
- Tab 6: mcp-atlassian logs (fallback)

---

## Part 1: "Building the Brain" (12-15 min)

### Scene 1.1: Create SRE Agent (3 min) — Pre-configured
Show the agent in Portal. Explain the resource group scope.

### Scene 1.2: Connect Azure MCP Server (5 min)
Show the MCP connector in Settings → Connectors.

**Talk track:** "One connector gives the agent 42+ Azure service tool groups."

### Scene 1.3: Connect Teams (2 min)
Show Teams connector.

### Scene 1.4: Upload Runbook (2 min)
Show Knowledge Base with uploaded runbook.

### Scene 1.5: Smoke Test (2 min)
Type in agent chat:
```
What resources are you monitoring for Contoso Meals? Give me a summary of
the overall health across our AKS cluster, Container App, PostgreSQL database,
and Cosmos DB.
```
Wait for response showing cross-service health summary.

---

## Part 2: "Connected Brain in Action" (15-20 min)

### Scene 2.1: Cross-Service Investigation (8 min)
Type:
```
We're about to enter our lunch rush. Can you do a pre-rush health check?
Verify that order-api and payment-service pods are healthy in AKS, the
menu-api Container App is ready to scale, PostgreSQL has enough connection
headroom, Cosmos DB has sufficient RU/s for the catalog reads, and all
secrets in Key Vault are accessible.
```

### Scene 2.2: Azure Policy Compliance (5 min)
Type:
```
Are any of the Contoso Meals resources non-compliant with our Azure Policies?
Check compliance state using the Policy tools.
```

### Scene 2.3: Cost & Performance (4 min)
Type:
```
Our Azure bill has been growing. Use Azure Advisor to check if any Contoso
Meals resources are oversized or underutilized. Also, based on our Application
Insights data from the load test, is our current PostgreSQL SKU appropriate
for the query patterns?
```

---

## Part 3: "Lunch Rush Under Fire" (15-20 min)

### Scene 3.1: Start Load + Chaos (2 min)

Option A — **Single command** (recommended):
```bash
./scripts/start-lunch-rush.sh
```
This starts the Azure Load Testing `lunch-rush` run, waits for traffic to ramp up,
then automatically triggers the Chaos Studio `exp-contoso-meals-payment-incident`
experiment (network latency + pod-kill on payment-service).

Option B — **Manual** (Portal):
- Azure Portal → Load Testing → `lt-contoso-meals` → Start "Lunch Rush" test (50 VUs, 10 min)
- While load is running: Chaos Studio → Start `exp-contoso-meals-payment-incident`

### Scene 3.2: Agent Investigates (8 min)
Wait for alert (1-2 min) or type:
```
Customers are reporting that their food orders are failing at checkout.
The menu seems to work fine. Can you investigate what's happening with
order processing and payments?
```

### Scene 3.3: Closed-Loop Actions (5 min)
Type:
```
Send a summary of this investigation to the Teams channel. Include the
business impact — what percentage of orders failed during the chaos
experiment. Then create a GitHub issue recommending that we add a
PodDisruptionBudget to the payment-service to survive pod failures
during peak traffic.
```

Then verify recovery:
```
The chaos experiment has ended. Can you verify that error rates have
returned to normal based on the Application Insights data?
```

### Scene 3.4: Build Resilience Subagent (4 min)
In SRE Agent → Subagent Builder → Create:
- Name: "Contoso Meals Resilience Validator"
- Instructions: See demo-proposal.md Scene 3.5

---

## Part 4: "ITSM Extensibility" (20-25 min)

### Scene 4.1: Show Jira Deployment (2 min)
- Portal → Container Apps → Show `jira-sm` and `mcp-atlassian`
- Open Jira URL → Show CONTOSO project board

### Scene 4.2: Connect mcp-atlassian (3 min)
Show the connector in SRE Agent settings. Verify:
```
What Jira tools do you now have available? List them.
```

### Scene 4.3: Create Jira Ticket (5 min)
Type:
```
A payment-service alert just fired. Investigate the issue and create a
Jira incident ticket in the CONTOSO project. Set priority based on
business impact. Include the affected services, error rates from
Application Insights, and the root cause in the ticket description.
```

### Scene 4.4: Live Investigation + Work Notes (8 min)
Type:
```
Continue investigating the payment-service incident. As you investigate,
post your findings as comments on the Jira ticket you just created.
Check the AKS pod status, Application Insights dependency failures,
PostgreSQL connection health, and whether the issue is isolated to
payment-service or affecting order-api too. Update the Jira ticket
priority if the impact is broader than initially assessed.
```
Show Jira ticket side-by-side — comments appear in real time.

### Scene 4.5: Resolution + SLA (5 min)
Type:
```
The payment-service pods seem to be recovering. Verify the service is
healthy, then resolve the Jira ticket with a summary of what happened,
how long the incident lasted, and what the business impact was.
```

Then:
```
Check the SLA metrics for the Jira ticket we just resolved. How long
did the incident take from creation to resolution?
```

Final:
```
Search Jira for all incidents related to payment-service in the last
7 days. Are we seeing a pattern?
```

---

## Part 4.5: "Infrastructure Under Fire — Hands-Off" (10-15 min)

> **Purpose:** Demonstrate the SRE Agent autonomously detecting, triaging, remediating,
> and closing a critical infrastructure-level failure — entirely hands-off.
> Unlike Part 3 (application-level pod chaos), this targets the compute substrate itself.

### Scene 4.5.1: Trigger Node Pool Failure (2 min)

```bash
# Full scenario: starts load test + chaos experiment + scales workload node pool to 0
./scripts/start-node-failure.sh
```

The script:
1. Starts an Azure Load Testing `lunch-rush` run (generates live customer traffic)
2. Starts the Chaos Studio `exp-contoso-meals-nodepool-failure` experiment (pod-kill on workload nodes)
3. Scales the AKS `workload` user node pool from 1 → 0 nodes

All application pods (order-api, payment-service) become unschedulable.

**Variants:**
```bash
./scripts/start-node-failure.sh --no-load        # skip load test
./scripts/start-node-failure.sh --chaos-only      # only chaos (no load, no scale)
./scripts/start-node-failure.sh --scale-only      # only scale to 0 (no load, no chaos)
./scripts/start-node-failure.sh --test-id baseline # use a different load test
```

### Scene 4.5.2: Hands-Off — Watch the SRE Agent (8-12 min)

**Do nothing.** The SRE Agent handles the entire incident lifecycle autonomously:

1. **Detection (T+1-2 min):** Azure Monitor alerts fire:
   - `AKS Workload Node Pool - Node NotReady`
   - `AKS Workload Node Pool Scaled to Zero Nodes`
   - `AKS Pods Unschedulable - No Available Nodes`

2. **Triage (T+2 min):** Agent creates a P1 Jira ticket in the CONTOSO project with
   blast radius assessment and affected services.

3. **Investigation (T+2-5 min):** Agent posts Jira comments as it investigates:
   - AKS node pool status → 0/1 nodes ready
   - Pod status → order-api and payment-service in Pending state
   - Application Insights → error rate spike correlating with load test data
   - Root cause → workload node pool scaled to 0

4. **Remediation (T+5-8 min):** Agent scales the workload node pool back to 1 node.

5. **Verification (T+8-12 min):** Agent confirms node is Ready, pods are Running,
   error rates return to baseline.

6. **Resolution:** Agent resolves the Jira ticket with full incident timeline,
   business impact, and remediation summary.

**Show side-by-side:**
- `kubectl get pods -n production -w` — watch pods go Pending → Running
- Jira CONTOSO board — real-time investigation comments and resolution

### Scene 4.5.3: Recap (1 min)

**Narrator:** *"From detection to resolution — fully autonomous, fully hands-off.
The on-call engineer received a clean incident report with root cause, business
impact quantified from the load test, and remediation details — without lifting a finger."*

### Manual Restore (if agent doesn't auto-remediate)

```bash
./scripts/start-node-failure.sh --restore
```

---

## Post-Demo Teardown

```bash
./scripts/teardown.sh --yes
```
