# Incident Response Plan: Automated Alert-to-Jira Pipeline — Research & Implementation Steps

> **Purpose:** Research document for implementing an automated incident response plan in Azure SRE Agent that picks up alerts, names threads based on alert title, creates Jira issues, proactively investigates, adds comments with findings, and notifies the user.
> **Date:** 2026-02-12

---

## 1. Executive Summary

The goal is to configure Azure SRE Agent with an **Incident Response Plan** backed by a **custom subagent** that:

1. **Automatically picks up** Azure Monitor alerts when they fire
2. **Names the investigation thread** based on the alert title (e.g., "Payment-service P95 latency > 2s")
3. **Creates a Jira incident ticket** in the CONTOSO project with severity based on business impact
4. **Proactively investigates** using AKS/Container Apps/App Insights/PostgreSQL diagnostics
5. **Adds comments to the Jira ticket** after each investigation step with findings
6. **Notifies the user** via Teams/Outlook to review the investigation

**Yes, a subagent is needed** — and the architecture should use **two subagents** with a handoff pattern. Here's why and how.

---

## 2. Why We Need a Subagent (Not Just an Incident Trigger)

### What an Incident Response Plan alone gives you

An **Incident Response Plan** (configured in Subagent Builder → Create → Incident Trigger) is a trigger mechanism that:
- Watches for incoming alerts from Azure Monitor, PagerDuty, or ServiceNow
- Filters by incident type, priority, impacted service
- Routes to a designated **response subagent**
- Operates in either **Review** (requires approval) or **Autonomous** mode

The incident trigger alone does NOT contain custom investigation logic, Jira integration instructions, or thread-naming behavior. It simply activates a subagent when conditions match.

### What a Subagent adds

The **subagent** is where all the intelligence lives:
- Custom instructions that define the multi-step investigation workflow
- Tool assignments (Azure MCP tools + Jira MCP tools)
- Knowledge base access (runbooks, escalation procedures)
- Handoff rules (when to escalate to another subagent or human)

### Official Pattern: Octopets `pd-azure-resource-error-handler.yaml`

Microsoft's official sample uses exactly this pattern:
1. **Incident Trigger** → watches PagerDuty for incoming incidents
2. **Subagent** (`PDazureresourceerrorhandler`) → contains the 6-phase autonomous workflow:
   - Intake → Diagnostics → Source analysis → GitHub issue → Email → Resolution

We adapt this for our Contoso Meals + Jira use case.

---

## 3. Proposed Architecture: Two-Subagent Design

### Why two subagents instead of one?

A single subagent doing everything (investigate + create Jira + update Jira + notify) works but creates a monolithic instruction set. Based on the Azure SRE Agent team's own [context engineering lessons](https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200), problems requiring more than four agent handoffs "almost always failed." Two is the sweet spot:

```
Azure Monitor Alert fires
         │
         ▼
  ┌─────────────────────────────────────────────┐
  │  Incident Response Plan (Trigger)           │
  │  - Platform: Azure Monitor                  │
  │  - Filter: severity ≤ 2, production pods    │
  │  - Mode: Autonomous                         │
  │  - Routes to: ContosoMealsIncidentHandler   │
  └──────────────────┬──────────────────────────┘
                     │
                     ▼
  ┌─────────────────────────────────────────────┐
  │  Subagent 1: ContosoMealsIncidentHandler    │
  │  (Primary — Investigation + Jira + Notify)  │
  │                                              │
  │  Phase 1: Thread naming from alert title     │
  │  Phase 2: Create Jira ticket (CONTOSO proj)  │
  │  Phase 3: Investigate (AKS, App Insights,    │
  │           PostgreSQL, Cosmos DB, Chaos)       │
  │  Phase 4: Post findings as Jira comments     │
  │  Phase 5: Teams + Outlook notification       │
  │  Phase 6: Handoff to Resilience Validator    │
  │           (if chaos experiment detected)      │
  └──────────────────┬──────────────────────────┘
                     │ (conditional handoff)
                     ▼
  ┌─────────────────────────────────────────────┐
  │  Subagent 2: ContosoMealsResilienceValidator │
  │  (Secondary — Post-Incident Analysis)        │
  │                                              │
  │  - Compare error rates to baseline           │
  │  - Evaluate chaos experiment results         │
  │  - Create GitHub issue for resilience fixes  │
  │  - Update Jira ticket with recommendations   │
  └─────────────────────────────────────────────┘
```

### When to use just ONE subagent

If you don't need the post-incident resilience analysis (e.g., simpler environments without Chaos Studio), a single subagent with all phases is sufficient and simpler to maintain.

---

## 4. Step-by-Step Implementation

### Step 1: Prerequisites — Verify Connectors

Before configuring the incident response plan, ensure the following connectors are active in **SRE Agent → Settings → Connectors**:

| Connector | Type | Purpose | Status |
|-----------|------|---------|--------|
| Azure MCP Server | Custom MCP (stdio) | 42+ Azure service tools (AKS, Monitor, App Insights) | Required |
| mcp-atlassian | Custom MCP (HTTP) | 34 Jira tools (create, update, transition, comment, SLA) | Required |
| Microsoft Teams | OAuth | Post investigation summaries to team channel | Required |
| Outlook | OAuth | Send notification emails | Optional |

**Verify configuration:**
```
Azure MCP: npx -y @azure/mcp server start (with AZURE_CLIENT_ID + ManagedIdentityCredential)
mcp-atlassian: https://<mcp-atlassian-fqdn>/mcp (with Authorization: Token <jira-api-token>)
```

### Step 2: Upload Knowledge Base Files

Navigate to **SRE Agent → Settings → Knowledge Base → Upload**:

1. `knowledge/contoso-meals-runbook.md` — Service ownership, SLAs, escalation paths
2. `knowledge/jira-itsm-runbook.md` — Jira ticket creation guidelines, priority mapping, workflow lifecycle

These are already in the repo and ready to upload.

### Step 3: Create Subagent 1 — ContosoMealsIncidentHandler

Navigate to **SRE Agent → Subagent Builder → Create → Subagent**

#### Configuration

| Property | Value |
|----------|-------|
| **Name** | `ContosoMealsIncidentHandler` |
| **Instructions** | *(see YAML below)* |
| **Handoff Description** | `Activate when a Contoso Meals production service has an active alert or incident. Performs end-to-end investigation, creates and updates Jira tickets with real-time findings, and notifies the team.` |
| **Built-in Tools** | Azure CLI, Log Analytics, Application Insights |
| **MCP Tools** | Azure MCP (all tool groups), mcp-atlassian (Jira tools) |
| **Handoff Agents** | `ContosoMealsResilienceValidator` (optional) |
| **Knowledge Base** | Enable — link to uploaded runbooks |

#### Subagent YAML (paste in YAML tab)

```yaml
api_version: azuresre.ai/v1
kind: AgentConfiguration
spec:
  name: ContosoMealsIncidentHandler
  system_prompt: >-
    Goal: Diagnose incidents for Contoso Meals and maintain a live Jira ticket with findings.

    === THREAD NAMING ===
    Name thread: "[INCIDENT] <alert-title>" or "[INCIDENT] <service-name> issue detected"

    === PHASE 1: INTAKE & JIRA CREATION ===
    1. Extract alert title, severity, affected resource, timestamp
    2. Identify affected service (payment-service, order-api, menu-api)
    3. Look up service in contoso-meals-runbook.md for business impact and SLA
    4. Create Jira ticket (jira_create_issue):
       - Project: CONTOSO, Type: Incident
       - Summary: alert title, Labels: sre-agent, <service>, production
       - Priority: P1=full outage/payments>30% fail, P2=partial/10-30%,
         P3=menu degradation, P4=non-customer-facing
    5. Transition to "In Progress" (jira_get_transitions + jira_transition_issue)

    === PHASE 2: INVESTIGATION ===
    Investigate systematically. Post Jira comment (jira_add_comment) after EACH step:

    2a - AKS Health: kubectl get pods -n production, check CrashLoopBackOff/restarts,
    describe unhealthy pods, get recent events. → Jira comment with findings.

    2b - App Insights: Query error rates (5xx), P95/P99 latency, dependency failures.
    Baseline: <1% errors, <200ms P95. → Jira comment with metrics.

    2c - Database: PostgreSQL→connections+queries. CosmosDB→RU/s+429s+hotspots.
    → Jira comment with DB health.

    2d - Activity Log & Chaos: Check recent changes, deployments, Chaos Studio experiments.
    If chaos detected, note as expected test. → Jira comment.

    2e - Blast Radius: Which services affected vs healthy? Business impact %?
    Reference runbook for impact descriptions. → Jira comment.

    === PHASE 3: PRIORITY REASSESSMENT ===
    If actual impact worse than initial: escalate via jira_update_issue.
    Error rate > 30% → P1. Post Jira comment explaining change with data.

    === PHASE 4: NOTIFICATION ===
    Send Teams message: summary, affected service, impact, root cause, Jira ID, action needed.
    Send Outlook email to ops-team@contoso.com: "[Contoso Meals Incident] <title> - <priority>"

    === PHASE 5: REMEDIATION DECISION ===
    Evaluate after investigation:
    A) Known pattern + clear root cause + pre-approved fix in runbook:
       → Hand off to ContosoMealsAutoRemediator with Jira ID and findings.
       → Jira comment: "Handing off for pre-approved remediation: [scenario]"
    B) Chaos experiment active:
       → Skip remediation. Hand off to ContosoMealsResilienceValidator.
       → Jira comment: "Chaos detected — skipping remediation, analyzing resilience."
    C) Unknown/complex pattern:
       → Do NOT remediate. Jira comment: "Unknown pattern — human review required."
       → Teams notification with P1 urgency.
    Known patterns: pod CrashLoopBackOff→restart, OOMKilled→memory increase,
    menu-api slow→scale replicas, Cosmos 429→increase RU/s,
    PostgreSQL >80% connections→kill idle, node pool at 0→scale to 1.

    === CONSTRAINTS ===
    - Post Jira comments with quantitative data (error rates, latency, pod counts)
    - Reference Knowledge Base runbooks for escalation paths and SLAs
    - If investigation stalls, post Jira progress update every 2 minutes

  tools:
    - RunAzCliReadCommands
    - ListAvailableMetrics
    - PlotTimeSeriesData
    - GetMetricsTimeSeriesAnalysis
    - QueryAppInsightsByResourceId
    - QueryLogAnalyticsByResourceId
    - GetResourceHealthInfo
    - PostTeamsMessage
    - SendOutlookEmail
    - SearchMemory
    # MCP tools from mcp-atlassian connector (auto-discovered):
    # jira_create_issue, jira_add_comment, jira_update_issue,
    # jira_transition_issue, jira_get_transitions, jira_search,
    # jira_get_issue, jira_get_issue_sla, jira_create_remote_issue_link
  handoff_description: >-
    Activate when a Contoso Meals production service has an alert. Investigates,
    creates/updates Jira tickets with findings, notifies team, and hands off to
    AutoRemediator for known patterns or ResilienceValidator for chaos analysis.
  handoff_agents:
    - ContosoMealsAutoRemediator
    - ContosoMealsResilienceValidator
  agent_type: Autonomous
```

### Step 4: Create Subagent 2 — ContosoMealsResilienceValidator (Optional)

Navigate to **SRE Agent → Subagent Builder → Create → Subagent**

| Property | Value |
|----------|-------|
| **Name** | `ContosoMealsResilienceValidator` |
| **Instructions** | *(see below)* |
| **Handoff Description** | `Hand off to this subagent when a chaos experiment is detected or completed, or when post-incident resilience analysis is needed.` |
| **Built-in Tools** | Azure CLI, Log Analytics |
| **MCP Tools** | Azure MCP (AKS, Monitor tools), mcp-atlassian (Jira tools) |
| **Knowledge Base** | Enable |

```yaml
api_version: azuresre.ai/v1
kind: AgentConfiguration
spec:
  name: ContosoMealsResilienceValidator
  system_prompt: >-
    Goal: After a chaos experiment or incident affecting Contoso Meals, evaluate resilience
    and recommend improvements.

    Process:
    1. Check if a Chaos Studio experiment was active during the incident window
    2. Compare error rates and latency during vs before the experiment
    3. Evaluate: did the affected service maintain availability above 99%?
    4. If availability dropped below 99%, create a GitHub issue recommending:
       - PodDisruptionBudgets for AKS services
       - Circuit breakers for inter-service communication
       - Retry policies for payment processing
       - Autoscaling adjustments
    5. Update the existing Jira ticket with:
       - Post-incident resilience analysis
       - Recommended improvements
       - Link to the GitHub issue
    6. Always quantify business impact: how many customer orders were affected?

  tools:
    - RunAzCliReadCommands
    - QueryAppInsightsByResourceId
    - QueryLogAnalyticsByResourceId
    - CreateGithubIssue
    - FindConnectedGitHubRepo
    - SearchMemory
  handoff_description: >-
    Use for post-incident resilience analysis, especially after chaos experiments.
    Evaluates service availability, recommends improvements, creates GitHub issues.
  agent_type: Autonomous
```

### Step 5: Create the Incident Response Plan (Trigger)

Navigate to **SRE Agent → Subagent Builder → Create → Incident Trigger**

| Field | Value |
|-------|-------|
| **Name** | `Contoso Meals Production Alert Handler` |
| **Platform** | Azure Monitor (connected by default) |
| **Filters** | |
| &nbsp;&nbsp;Severity | Sev 0, Sev 1, Sev 2 (Critical through Warning) |
| &nbsp;&nbsp;Impacted Service | All services in `rg-contoso-meals` |
| **Response Subagent** | `ContosoMealsIncidentHandler` |
| **Processing Mode** | `Autonomous` (or `Review` for demo — lets you watch before agent acts) |
| **Timeout** | 30 minutes |

**What this trigger does:**
- Watches for Azure Monitor alerts fired against resources in `rg-contoso-meals`
- Filters to Sev 0-2 (skips informational Sev 3-4 alerts)
- Activates `ContosoMealsIncidentHandler` subagent with the alert context
- The subagent receives the alert title, severity, affected resource, and timestamp

### Step 6: Test in Playground Before Going Live

1. Navigate to **Subagent Builder → ContosoMealsIncidentHandler → Playground**
2. Click **2 Window View** to see tools + responses side by side
3. Enter test prompt:

```
An Azure Monitor alert fired: "payment-service P95 latency > 2s" with severity Sev 1.
Affected resource: aks-contoso-meals in resource group rg-contoso-meals.
The alert title is "Payment-service pod restart count exceeded threshold".
Investigate and follow your incident response process.
```

4. Verify the agent:
   - Names the thread appropriately
   - Creates a Jira ticket in CONTOSO project
   - Posts investigation comments step by step
   - Sends a Teams notification
   - Attempts handoff to ResilienceValidator if chaos detected

---

## 5. Thread Naming — How It Works

### The mechanism

Azure SRE Agent **automatically** names investigation threads when activated by an incident trigger. The thread title comes from the alert/incident metadata. With the custom instructions above, we explicitly instruct the agent to:

1. Use the format `[INCIDENT] <alert-title>` for thread naming
2. Fall back to `[INCIDENT] <service-name> issue detected` if no title is available

### What the user sees

In the SRE Agent portal under **Incident Management → Incidents**:

```
┌──────────────────────────────────────────────────────────────────┐
│ Incidents                                                        │
├──────────┬───────────────────────────────────────────────────────┤
│ Status   │ Thread / Title                                        │
├──────────┼───────────────────────────────────────────────────────┤
│ Active   │ [INCIDENT] Payment-service pod restart count > 0      │
│ Active   │ [INCIDENT] Payment-service P95 latency > 2s           │
│ Resolved │ [INCIDENT] PostgreSQL active connections > 80%         │
└──────────┴───────────────────────────────────────────────────────┘
```

### Limitation

Thread naming based on alert title is native behavior for the incident trigger — the agent receives the alert metadata (including `alertRule.name`) and uses it as conversational context. The custom instruction `"name the investigation thread using the alert title"` reinforces this behavior and defines the formatting convention.

---

## 6. Alert → Jira Flow — Complete Data Path

```
Azure Monitor Alert Rule                 Azure SRE Agent                              Jira SM
(payment-service P95 > 2s)              (Incident Response Plan)                     (CONTOSO project)
         │                                        │                                        │
    1. Alert fires ──────────────────────────► 2. Trigger activates                        │
         │                                    ContosoMealsIncidentHandler                  │
         │                                        │                                        │
         │                                   3. Agent extracts alert title                 │
         │                                      Names thread: "[INCIDENT] ..."             │
         │                                        │                                        │
         │                                   4. Agent calls ─────────────────────────► 5. Jira ticket
         │                                      jira_create_issue                       CONTOSO-42
         │                                        │                                    "Payment-service
         │                                        │                                     pod restart..."
         │                                        │                                        │
         │                                   6. Agent investigates                         │
         │                                      (kubectl, App Insights,                    │
         │                                       Activity Log, Chaos check)                │
         │                                        │                                        │
         │                                   7. After each step: ────────────────────► 8. Comment added
         │                                      jira_add_comment                        "Investigation
         │                                        │                                     Step 1: ..."
         │                                        │                                        │
         │                                   9. Agent may escalate: ─────────────────► 10. Priority
         │                                      jira_update_issue                        P2 → P1
         │                                        │                                        │
         │                                  11. Agent transitions: ──────────────────► 12. Status
         │                                      jira_transition_issue                   "In Progress"
         │                                        │                                        │
         │                                  13. Agent notifies:                            │
         │                                      Teams + Outlook                            │
         │                                      "Look into CONTOSO-42"                     │
         │                                        │                                        │
         │                                  14. Handoff (if chaos detected):               │
         │                                      → ContosoMealsResilienceValidator          │
         │                                        │                                        │
         │                                  15. Validator updates: ──────────────────► 16. Final comment
         │                                      jira_add_comment                        "Resilience
         │                                      jira_transition_issue                    analysis..."
         │                                                                              → "Resolved"
```

---

## 7. Do We Need the Second Subagent?

### Recommendation: **Yes, for the demo — optional for simple production use**

| Scenario | Single Subagent | Two Subagents |
|----------|----------------|---------------|
| **Simple alert → investigate → Jira → notify** | Sufficient | Overkill |
| **Chaos experiment → investigate → Jira → resilience analysis → GitHub issue** | Instruction bloat, >6 phases | Clean separation of concerns |
| **Demo storytelling** | Less dramatic | Shows subagent handoff live — powerful visual |
| **Maintenance** | One YAML to maintain | Two focused YAMLs, easier to evolve independently |
| **Context window efficiency** | All tools loaded, even if unused | Each subagent only loads relevant tools |

**For the Contoso Meals demo:** Use two subagents. The handoff from IncidentHandler to ResilienceValidator is a demo-worthy moment that showcases the Subagent Builder's orchestration capability.

**For a real production deployment:** Start with one subagent. Split into two only if the investigation YAML exceeds ~200 lines or you need different tool sets for different phases.

---

## 8. Existing Alert Rules That Will Fire This

The following alerts are already deployed via `infra/modules/monitoring.bicep`:

| Alert Rule | Condition | Fires When |
|-----------|-----------|------------|
| `alert-pod-restart-contoso-meals` | `restartingContainerCount > 0` | Any pod restarts in AKS |
| Payment-service P95 latency alert | P95 > 2s | Payment latency spikes |
| PostgreSQL connections alert | Active connections > 80% | DB connection pressure |
| Cosmos DB 429 alert | Throttled requests > 0 | Cosmos DB throttling |

The **Chaos Studio experiment** (`exp-contoso-meals-payment-incident`) will trigger the pod restart alert, which activates the incident response plan, which triggers the `ContosoMealsIncidentHandler` subagent.

---

## 9. Configuration Checklist

- [ ] **Connectors verified:** Azure MCP, mcp-atlassian, Teams, Outlook all active
- [ ] **Knowledge Base uploaded:** `contoso-meals-runbook.md` + `jira-itsm-runbook.md`
- [ ] **Subagent 1 created:** `ContosoMealsIncidentHandler` with full YAML
- [ ] **Subagent 2 created:** `ContosoMealsResilienceValidator` (optional, for chaos demo)
- [ ] **Incident Trigger created:** `Contoso Meals Production Alert Handler`
  - Platform: Azure Monitor
  - Severity filter: Sev 0-2
  - Response subagent: `ContosoMealsIncidentHandler`
  - Mode: Autonomous (or Review for demo)
- [ ] **Playground tested:** Simulated alert prompt, verified Jira ticket creation + comments
- [ ] **GitHub connected:** Resource mapping for AKS cluster to the `azure-sre` repo
- [ ] **Jira project ready:** CONTOSO project with Incident issue type and workflow

---

## 10. Demo Script — How to Show This

### Setup (pre-demo)
1. Configure all of the above
2. Ensure baseline load test has been running (30+ min of metrics in App Insights)
3. Open browser tabs: SRE Agent chat, Jira CONTOSO board, Azure Monitor alerts

### Live demo flow

**Step 1:** Start the lunch rush load test:
```bash
./scripts/start-lunch-rush.sh --load-only
```

**Step 2:** Start the chaos experiment (payment-service pod kill):
```bash
./scripts/start-lunch-rush.sh --chaos-only
```

**Step 3:** Watch the magic happen:
- Azure Monitor fires pod restart alert (within 1-2 minutes)
- SRE Agent incident trigger activates `ContosoMealsIncidentHandler`
- Agent creates Jira ticket → watch CONTOSO board update live
- Agent posts investigation comments → watch Jira ticket comments appear in real-time
- Agent sends Teams notification → "Look into CONTOSO-42: payment-service pod failures"
- Agent hands off to `ContosoMealsResilienceValidator` → resilience analysis + GitHub issue

**Narrator:** *"The alert fired 90 seconds ago. Without a human touching anything, the SRE Agent has already: created a Jira incident ticket, investigated across AKS, App Insights, and Activity Log, posted 5 investigation comments with quantitative findings, escalated the priority to P1, and sent a Teams message to the on-call team. The on-call engineer opens Jira and finds a complete investigation trail — not 'pod restarting, please investigate.'"*

---

## 11. Key References

| Resource | URL |
|----------|-----|
| Subagent Builder Overview | https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview |
| Subagent Builder Scenarios | https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-scenarios |
| Official Incident Automation Sample | https://github.com/microsoft/sre-agent/blob/main/samples/automation/samples/01-incident-automation-sample.md |
| Configure SRE Agent Guide | https://github.com/microsoft/sre-agent/blob/main/samples/automation/configuration/00-configure-sre-agent.md |
| PD Error Handler Subagent YAML | https://github.com/microsoft/sre-agent/blob/main/samples/automation/subagents/pd-azure-resource-error-handler.yaml |
| Context Engineering Lessons | https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200 |
| SRE Agent Connectors Docs | https://learn.microsoft.com/en-us/azure/sre-agent/connectors |
| mcp-atlassian GitHub | https://github.com/sooperset/mcp-atlassian |
