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

```mermaid
graph TD
    ALERT["Azure Monitor Alert fires"] --> TRIGGER

    TRIGGER["Incident Response Plan (Trigger)<br/>Platform: Azure Monitor<br/>Filter: severity ≤ 2, production pods<br/>Mode: Autonomous<br/>Routes to: ContosoMealsIncidentHandler"]
    
    TRIGGER --> S1

    S1["Subagent 1: ContosoMealsIncidentHandler<br/>(Primary — Investigation + Jira + Notify)"]
    S1P1["Phase 1: Thread naming from alert title"]
    S1P2["Phase 2: Create Jira ticket (CONTOSO proj)"]
    S1P3["Phase 3: Investigate (AKS, App Insights,<br/>PostgreSQL, Cosmos DB, Chaos)"]
    S1P4["Phase 4: Post findings as Jira comments"]
    S1P5["Phase 5: Teams + Outlook notification"]
    S1P6["Phase 6: Handoff to Resilience Validator<br/>(if chaos experiment detected)"]
    
    S1 --> S1P1 --> S1P2 --> S1P3 --> S1P4 --> S1P5 --> S1P6

    S1P6 -->|"conditional handoff"| S2

    S2["Subagent 2: ContosoMealsResilienceValidator<br/>(Secondary — Post-Incident Analysis)<br/>- Compare error rates to baseline<br/>- Evaluate chaos experiment results<br/>- Create GitHub issue for resilience fixes<br/>- Update Jira ticket with recommendations"]
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

#### Subagent YAML

> **YAML definition:** [`subagents/contoso-meals-incident-handler.yaml`](../subagents/contoso-meals-incident-handler.yaml)
>
> Paste the contents of that file into the **YAML tab** in Subagent Builder.

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

> **YAML definition:** [`subagents/contoso-meals-resilience-validator.yaml`](../subagents/contoso-meals-resilience-validator.yaml)
>
> Paste the contents of that file into the **YAML tab** in Subagent Builder.

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

```mermaid
graph LR
    subgraph Incidents["SRE Agent — Incident Management"]
        I1["🔴 Active: [INCIDENT] Payment-service pod restart count > 0"]
        I2["🔴 Active: [INCIDENT] Payment-service P95 latency > 2s"]
        I3["🟢 Resolved: [INCIDENT] PostgreSQL active connections > 80%"]
    end
```

### Limitation

Thread naming based on alert title is native behavior for the incident trigger — the agent receives the alert metadata (including `alertRule.name`) and uses it as conversational context. The custom instruction `"name the investigation thread using the alert title"` reinforces this behavior and defines the formatting convention.

---

## 6. Alert → Jira Flow — Complete Data Path

```mermaid
sequenceDiagram
    participant AM as Azure Monitor<br/>Alert Rule
    participant SRE as Azure SRE Agent<br/>(Incident Response Plan)
    participant JIRA as Jira SM<br/>(CONTOSO project)

    AM->>SRE: 1. Alert fires
    Note over SRE: 2. Trigger activates<br/>ContosoMealsIncidentHandler
    Note over SRE: 3. Extract alert title<br/>Name thread: "[INCIDENT] ..."
    SRE->>JIRA: 4. jira_create_issue
    Note over JIRA: 5. CONTOSO-42 created<br/>"Payment-service pod restart..."
    Note over SRE: 6. Investigate<br/>(kubectl, App Insights,<br/>Activity Log, Chaos check)
    SRE->>JIRA: 7. jira_add_comment (after each step)
    Note over JIRA: 8. "Investigation Step 1: ..."
    SRE->>JIRA: 9. jira_update_issue (escalate priority)
    Note over JIRA: 10. Priority P2 → P1
    SRE->>JIRA: 11. jira_transition_issue
    Note over JIRA: 12. Status → "In Progress"
    Note over SRE: 13. Notify via Teams + Outlook<br/>"Look into CONTOSO-42"
    Note over SRE: 14. Handoff (if chaos):<br/>→ ContosoMealsResilienceValidator
    SRE->>JIRA: 15. jira_add_comment + transition
    Note over JIRA: 16. "Resilience analysis..."<br/>→ "Resolved"
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
