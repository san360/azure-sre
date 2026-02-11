# Azure SRE Agent: Comprehensive Guide for Demo & Customer Presentations

> **Status:** Public Preview (no sign-up required)
> **Region availability:** East US 2 (expanding)
> **Documentation last validated:** February 2026

---

## Table of Contents

1. [What Is Azure SRE Agent?](#1-what-is-azure-sre-agent)
2. [Why Azure SRE Agent? The Rationale](#2-why-azure-sre-agent-the-rationale)
3. [Core Capabilities](#3-core-capabilities)
4. [Architecture & How It Works](#4-architecture--how-it-works)
5. [Supported Azure Services](#5-supported-azure-services)
6. [Integration Ecosystem](#6-integration-ecosystem)
7. [Subagent Builder](#7-subagent-builder)
8. [Memory & Context Engineering](#8-memory--context-engineering)
9. [Pricing Model](#9-pricing-model)
10. [Demo Scenarios You Can Build Quickly](#10-demo-scenarios-you-can-build-quickly)
11. [Getting Started (Quickstart)](#11-getting-started-quickstart)
12. [GitHub Samples & Community Repositories](#12-github-samples--community-repositories)
13. [Official Blog Posts & Announcements](#13-official-blog-posts--announcements)
14. [Videos & Learning Resources](#14-videos--learning-resources)
15. [Key Considerations for Your Demo](#15-key-considerations-for-your-demo)

---

## 1. What Is Azure SRE Agent?

Azure SRE Agent is an **AI-powered operations automation platform** that helps Site Reliability Engineers (SREs), DevOps teams, IT operations, and support teams automate incident detection, diagnosis, and resolution across Azure environments. It uses fine-tuned large language model reasoning to investigate production issues, perform root cause analysis, and execute remediations — all through a natural-language chat interface in the Azure Portal.

The service has already **saved over 20,000 engineering hours** across Microsoft's own product teams internally.

**Key value proposition:** Reduce Mean Time To Resolution (MTTR), eliminate operational toil, and shift from reactive firefighting to proactive reliability engineering — without writing custom automation code.

> **Source:** [Azure SRE Agent Overview - Microsoft Learn](https://learn.microsoft.com/en-us/azure/sre-agent/overview) | [Product Page](https://azure.microsoft.com/en-us/products/sre-agent)

---

## 2. Why Azure SRE Agent? The Rationale

### The Problem It Solves

Traditional cloud operations suffer from:

- **Alert fatigue:** Teams drown in notifications, many of which are false positives or lack actionable context.
- **Manual root cause analysis:** Engineers spend hours correlating metrics, logs, and traces across multiple tools to find the source of an incident.
- **Knowledge silos:** Tribal knowledge about systems, past incidents, and runbooks lives in people's heads and scattered documents.
- **Reactive posture:** Most teams only act after users report problems, losing valuable uptime.
- **Tool sprawl:** Operators juggle Azure Monitor, Log Analytics, Application Insights, PagerDuty, ServiceNow, GitHub, and more — manually context-switching between them.

### Why It Works: Design Principles

The Azure SRE Agent team published their [context engineering lessons](https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200), revealing key architectural decisions:

1. **Tool consolidation over specialization:** The team moved from 100+ tools and 50+ specialized agents down to **5 core tools and a handful of generalist agents**. Instead of wrapping individual Azure APIs, they exposed `az` CLI and `kubectl` as first-class tools, leveraging the model's built-in training knowledge of these CLIs.

2. **Generalist agents over deep specialists:** Problems requiring more than four agent handoffs "almost always failed" due to discovery issues, system prompt fragility, infinite loops, and tunnel vision. Fewer, broader agents proved more reliable.

3. **Code execution over raw data:** Rather than dumping large metric datasets into the model's context, the agent sends data to a code interpreter where the model writes pandas/numpy analysis scripts — eliminating metrics analysis failures entirely.

4. **External state management:** Explicit checklists and compressed history summaries keep investigations on track rather than relying on raw conversation logs.

5. **Progressive data disclosure:** Large tool outputs are treated as queryable data sources in sandboxed environments, not inline context. This keeps the model's context window focused.

These principles explain why the agent achieves reliable results in real-world production scenarios where simpler LLM wrappers fail.

> **Source:** [Context Engineering Lessons from Building Azure SRE Agent - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200)

---

## 3. Core Capabilities

### 3.1 Incident Response Automation

- Integrates with **Azure Monitor Alerts**, **PagerDuty**, and **ServiceNow** for automatic alert ingestion.
- Conducts root cause analysis in **minutes** instead of hours by correlating metrics, activity logs, dependency data, and application traces.
- Creates documented triage plans with investigation findings.
- Proposes and executes mitigations (scaling, restarts, rollbacks) **only with user approval**.
- Generates GitHub issues containing full investigation summaries for developer handoff.

### 3.2 Proactive Monitoring (Scheduled Tasks)

- Define monitoring tasks in **natural language** (e.g., "Check for exposed public endpoints daily").
- The agent converts prompts into structured execution plans using Azure CLI, Log Analytics, and Application Insights.
- Supports cron expressions or simple intervals (hourly, daily, weekly).
- Delivers findings via Microsoft Teams, email (Outlook), or incident management systems.

**Example scheduled tasks:**
| Task | Schedule |
|------|----------|
| Scan for publicly exposed storage accounts | Daily |
| Compare weekly cloud spend and alert on >20% growth | Weekly |
| Check TLS version compliance across App Services | Daily |
| Summarize production VM health status | Every 4 hours |
| Identify recurring incident patterns | Weekly |

### 3.3 Resource Monitoring & Analytics

- Continuously watches Azure infrastructure across multiple subscriptions.
- Answers natural-language queries: *"Why is my-app slow?"* or *"What changed in the last 24 hours?"*
- Generates visualizations of metrics (error rates, request patterns, latency).

### 3.4 Security Auditing

- Scans resources for compliance gaps (TLS versions, Managed Identity configuration, public endpoints).
- Recommends and optionally executes remediation with user authorization.

### 3.5 IaC Drift Detection & Code-Aware RCA

- Detects infrastructure-as-code drift.
- Traces issues directly to source context in **GitHub** and **Azure DevOps**.
- Can trigger GitHub Copilot to generate pull requests for code fixes.

### 3.6 Autonomous Resolution

- Follows team runbooks to resolve known incident categories independently.
- Operates on a **least-privilege model** — never executes write actions without explicit human approval.
- Organizations control autonomy levels from read-only insights to full automation.

> **Source:** [Introducing Azure SRE Agent - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/azurepaasblog/introducing-azure-sre-agent/4414569) | [Expanding the Public Preview - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/expanding-the-public-preview-of-the-azure-sre-agent/4458514)

---

## 4. Architecture & How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                       Azure SRE Agent                           │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │  Built-in    │  │   Custom     │  │   Subagent Builder    │  │
│  │  Azure       │  │   Runbooks   │  │   (No-Code)           │  │
│  │  Knowledge   │  │  (AZ CLI,    │  │                       │  │
│  │              │  │   REST API)  │  │  - Custom instructions│  │
│  └──────┬───────┘  └──────┬───────┘  │  - Tool assignments   │  │
│         │                 │          │  - Handoff rules       │  │
│         │                 │          │  - Knowledge base      │  │
│         └────────┬────────┘          └───────────┬───────────┘  │
│                  │                               │              │
│         ┌────────▼───────────────────────────────▼──────────┐   │
│         │              Core Reasoning Engine                │   │
│         │   (Fine-tuned LLM + Code Interpreter + Memory)   │   │
│         └────────┬───────────────────────────────┬──────────┘   │
│                  │                               │              │
│  ┌───────────────▼────────┐   ┌──────────────────▼───────────┐  │
│  │   Triggers             │   │    Integrations              │  │
│  │  - Azure Monitor Alerts│   │  - Azure Monitor / LA / AI   │  │
│  │  - PagerDuty           │   │  - GitHub / Azure DevOps     │  │
│  │  - ServiceNow          │   │  - Datadog / New Relic       │  │
│  │  - Scheduled Tasks     │   │  - Dynatrace / Grafana       │  │
│  │                        │   │  - MCP Servers (extensible)  │  │
│  └────────────────────────┘   │  - Outlook / Teams           │  │
│                               └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Automatic Resource Provisioning

When you create an Azure SRE Agent, these resources are automatically provisioned:
- **Azure Application Insights** instance
- **Log Analytics Workspace**
- **Managed Identity** (for RBAC-scoped access to your resources)

### Security Model

- Uses **Managed Identity** with role-based access control.
- Never executes write actions without explicit human approval.
- Organizations can assign **read-only** or **approver** roles.
- Permissions are scoped to specific resource groups (least-privilege).

> **Source:** [Azure SRE Agent Overview - Microsoft Learn](https://learn.microsoft.com/en-us/azure/sre-agent/overview)

---

## 5. Supported Azure Services

Azure SRE Agent has **enhanced diagnostics** for the following services, with built-in operational patterns:

| Category | Services |
|----------|----------|
| **Compute** | Azure Kubernetes Service (AKS), Azure Container Apps, Azure App Service, Azure Functions, Virtual Machines |
| **Databases** | Azure SQL Database, Cosmos DB, PostgreSQL, MySQL, Redis |
| **Storage** | Blob Storage, File Shares, Managed Disks, Storage Accounts |
| **Networking** | Virtual Networks, Load Balancers, Application Gateways, Network Security Groups |
| **Monitoring** | Azure Monitor, Log Analytics, Application Insights |
| **API Management** | Azure API Management |

**Important:** Any operation performable via **Azure CLI** can be automated through the SRE Agent using custom runbooks — so coverage extends beyond the services listed above.

> **Source:** [Azure SRE Agent Overview - Microsoft Learn](https://learn.microsoft.com/en-us/azure/sre-agent/overview) | [Expanding the Public Preview - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/expanding-the-public-preview-of-the-azure-sre-agent/4458514)

---

## 6. Integration Ecosystem

### Monitoring & Observability

| Integration | Type | Notes |
|------------|------|-------|
| **Azure Monitor** | Native | Metrics, logs, alerts, workbooks |
| **Application Insights** | Native | APM, traces, dependencies |
| **Log Analytics** | Native | KQL queries, workspace analysis |
| **Grafana** | Supported | Dashboard integration |
| **Datadog** | MCP Connector | Centralized logs and metrics |
| **New Relic** | MCP Connector | 35+ specialized tools for entity management, alerts, monitoring |
| **Dynatrace** | MCP Connector | Davis AI engine integration for hybrid cloud |

### Incident Management

| Integration | Configuration |
|------------|---------------|
| **Azure Monitor Alerts** | Default (built-in) |
| **PagerDuty** | API key in Settings > Incident platform |
| **ServiceNow** | Endpoint + credentials in Settings > Incident platform |

### Source Control & CI/CD

| Integration | Capabilities |
|------------|-------------|
| **GitHub** | Repositories, issues, code-aware RCA, Copilot handoff for PR generation |
| **Azure DevOps** | Repos, work items, pipelines |

### Communication & Actions

| Integration | Use Case |
|------------|----------|
| **Microsoft Teams** | Notifications, findings delivery |
| **Outlook Email** | Alert and report delivery |
| **MCP Servers** | Custom third-party SaaS integrations |

### Multi-Cloud

Azure SRE Agent positions itself as a **hub for cross-platform reliability**, enabling incident management across Azure, on-premises, and other cloud environments through MCP connectors and agent-to-agent collaboration frameworks.

> **Source:** [Azure SRE Agent: Expanding Observability and Multi-Cloud Resilience - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/azure-sre-agent-expanding-observability-and-multi-cloud-resilience/4472719) | [Reimagining AI Ops - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/reimagining-ai-ops-with-azure-sre-agent-new-automation-integration-and-extensibi/4462613)

---

## 7. Subagent Builder

The **no-code Subagent Builder** lets you create purpose-built agents for specific operational domains without writing code.

### What You Can Build

| Capability | Examples |
|-----------|---------|
| **Custom Subagents** | RCA specialists for specific services, compliance checkers, monitoring agents |
| **Data Integration** | Azure Monitor connectors, file uploads (runbooks), MCP connectors |
| **Automated Triggers** | Incident response plans, scheduled health reports, compliance scans |
| **Actions** | Send Teams notifications, Outlook emails, call custom MCP tools |

### Subagent Configuration Properties

| Property | Purpose |
|----------|---------|
| **Name** | Descriptive name for identification |
| **Instructions** | Custom behavioral instructions (natural language) |
| **Handoff Description** | When to transfer processing to this subagent |
| **Custom Tools** | Azure CLI commands, Kusto queries, REST API calls |
| **Built-in Tools** | System tools to provide access to |
| **Handoff Agents** | Which subagent takes over after this one completes |
| **Knowledge Base** | Uploaded markdown/text files as reference material (up to 16MB/file) |

### Testing

The **Playground** feature lets you test subagents interactively before deploying them to production workflows.

> **Source:** [Subagent Builder Overview - Microsoft Learn](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview)

---

## 8. Memory & Context Engineering

Azure SRE Agent includes a persistent memory system with three components:

### 8.1 User Memories

Quick chat commands for storing team knowledge:
- `#remember Team owns app-service-prod in East US` — saves a fact
- `#forget` — removes a saved fact
- `#retrieve` — searches saved items

These persist across all team conversations instantly.

### 8.2 Knowledge Base

Upload markdown (`.md`) and text (`.txt`) files directly (up to 16MB per file). The system uses intelligent indexing combining **keyword matching with semantic similarity**, automatically chunking documents for optimal retrieval.

### 8.3 Session Insights

Automated feedback on troubleshooting sessions:
- Timeline of investigation steps
- Performance analysis (quality score 1-5)
- Key learnings for future sessions
- Improvement suggestions

> **Source:** [Never Explain Context Twice: Introducing Azure SRE Agent Memory - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/never-explain-context-twice-introducing-azure-sre-agent-memory/4473059)

---

## 9. Pricing Model

Azure SRE Agent uses **Azure Agent Units (AAU)** for billing (effective September 1, 2025):

| Component | Cost | Description |
|-----------|------|-------------|
| **Always-On Flow** | 4 AAU/hour/agent | Fixed baseline — 24/7 monitoring and learning |
| **Active Flow** | 0.25 AAU/second/task | Variable — charged during active remediation tasks |

### Example Monthly Costs (at $0.10/AAU, 730 hours/month)

| Scenario | Monthly Cost (per agent) |
|----------|------------------------|
| Minimal incidents (4 tasks, 5 min each) | ~$322 |
| High operational load (2 incidents/day, 10 min each) | ~$1,222 |
| Burst events (50 incidents, 5 min each) | ~$667 |

> **Note:** Preview pricing — subject to change at GA.

> **Source:** [Announcing a Flexible, Predictable Billing Model for Azure SRE Agent - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/announcing-a-flexible-predictable-billing-model-for-azure-sre-agent/4427270)

---

## 10. Demo Scenarios You Can Build Quickly

### Demo 1: AKS Incident Response (30 min setup)

**Scenario:** Deploy a misbehaving application on AKS, trigger alerts, and let the SRE Agent investigate.

**Steps:**
1. Create an AKS cluster with a sample application (e.g., a .NET or Node.js app).
2. Create an Azure SRE Agent monitoring the AKS resource group.
3. Introduce a problem: misconfigured resource limits, crashlooping pods, or an OOM condition.
4. Trigger an Azure Monitor alert.
5. Observe the agent: it uses `kubectl` to inspect pods, check logs, analyze events, and propose a fix.

**What to show:** The agent's natural-language RCA, its use of kubectl commands, proposed remediation, and the approval workflow.

---

### Demo 2: Container Apps Proactive Security Audit (15 min setup)

**Scenario:** Schedule daily security scans across Azure Container Apps.

**Steps:**
1. Deploy one or more Container Apps with intentional misconfigurations (e.g., public ingress on a backend service, outdated TLS version).
2. Create a scheduled task: *"Scan all Container Apps for security misconfigurations, check TLS versions, and report findings via Teams."*
3. Wait for the scheduled run or trigger it manually.

**What to show:** Natural-language task definition, automated scanning, findings summary, Teams notification delivery.

---

### Demo 3: Full Incident Lifecycle with ServiceNow (20 min setup)

**Scenario:** End-to-end incident flow from ServiceNow alert to automated resolution.

**Steps:**
1. Deploy sample infrastructure (App Service + database).
2. Connect Azure SRE Agent to ServiceNow (Settings > Incident platform — takes ~5 minutes per the [ServiceNow blog](https://techcommunity.microsoft.com/blog/appsonazureblog/connect-azure-sre-agent-to-servicenow-end-to-end-incident-response/4487824)).
3. Create an incident in ServiceNow.
4. Watch the agent acknowledge, triage, investigate, and update work notes automatically.

**What to show:** ServiceNow integration, automated triage, investigation documentation, resolution workflow.

---

### Demo 4: Proactive Cost & Compliance Monitoring (10 min setup)

**Scenario:** Set up weekly cost analysis and compliance checks.

**Steps:**
1. Point the SRE Agent at a resource group with various resources.
2. Create scheduled tasks:
   - *"Compare this week's spend to last week and alert if any service grew more than 20%."*
   - *"Check all storage accounts for encryption compliance and report findings."*
3. Show the resulting reports and notifications.

**What to show:** No-code scheduled tasks, natural-language monitoring definitions, actionable reports.

---

### Demo 5: Multi-Source Observability with MCP (25 min setup)

**Scenario:** Connect the SRE Agent to Azure MCP for cross-subscription resource management.

**Steps:**
1. Deploy the Azure MCP connector (Settings > Connectors, type: stdio, command: `npx -y @azure/mcp server start`).
2. Configure Managed Identity with Reader access on target subscriptions.
3. Create a subagent that uses the MCP connector.
4. In the Playground, ask: *"List all resources across my subscriptions and identify any without tags."*

**What to show:** MCP integration, cross-subscription visibility, Managed Identity security model.

> **Source for MCP setup:** [How to Connect Azure SRE Agent to Azure MCP - Microsoft Tech Community](https://techcommunity.microsoft.com/blog/appsonazureblog/how-to-connect-azure-sre-agent-to-azure-mcp/4488905)

---

### Demo 6: Pre-Built Demo Kit (45 min guided demo)

Use the **community demo kit** ([jiratouchmhp/azure-sre-agent-demo](https://github.com/jiratouchmhp/azure-sre-agent-demo)) which includes:

- **Full application stack:** React frontend + .NET 8 API + PostgreSQL
- **Pre-planted issues:** Security gaps, cost inefficiencies, availability risks
- **Incident triggers:** API endpoints for simulating CPU spikes, memory leaks, DB slowdowns
- **Guided 45-minute demo flow:**
  - Phase 1 (5 min): Architecture overview and health check
  - Phase 2 (15 min): Proactive audit — watch the agent find security misconfigs, oversized resources, missing redundancy
  - Phase 3 (15 min): Reactive incident response — trigger incidents and watch real-time investigation

**Cost:** ~$460/month (includes intentionally oversized resources). Tear down after demo.

---

## 11. Getting Started (Quickstart)

### Prerequisites

- Azure subscription with `Microsoft.Authorization/roleAssignments/write` permissions (RBAC Administrator or User Access Administrator)
- Allowlist `*.azuresre.ai` in your firewall

### Create Your First Agent

1. Open the Azure Portal → search for **Azure SRE Agent** (or navigate to [aka.ms/sreagent/portal](https://aka.ms/sreagent/portal))
2. Select **Create**
3. Choose your **Subscription** and **Resource Group**
4. Enter an **Agent name** and select **East US 2** as the region
5. Under **Choose resource groups**, select the resource groups you want the agent to monitor
6. Click **Create**

The portal automatically provisions Application Insights, a Log Analytics workspace, and a Managed Identity.

### Start Chatting

Once created, open the agent and the chat window appears. Try:

- *"What resources are you monitoring?"*
- *"Show me a visualization of error rates for my web apps."*
- *"Why is `<resource-name>` slow?"*
- *"What alerts should I set up for `<resource-name>`?"*

### Connect Incident Platforms

| Platform | Path |
|----------|------|
| **PagerDuty** | Settings > Incident platform > PagerDuty > enter API key |
| **ServiceNow** | Settings > Incident platform > ServiceNow > enter endpoint, username, password |
| **Azure Monitor Alerts** | Connected by default |

> **Source:** [Use an Agent - Microsoft Learn](https://learn.microsoft.com/en-us/azure/sre-agent/usage)

---

## 12. GitHub Samples & Community Repositories

### Official Microsoft Repository

| Repository | Description |
|-----------|-------------|
| [**microsoft/sre-agent**](https://github.com/microsoft/sre-agent) | Official repo — issue tracking, feature requests, community discussions. 40 stars, MIT license. |

### Community Demo & Sample Repositories

| Repository | Description | Language |
|-----------|-------------|----------|
| [**jiratouchmhp/azure-sre-agent-demo**](https://github.com/jiratouchmhp/azure-sre-agent-demo) | Full demo environment with React + .NET 8 + PostgreSQL, pre-planted issues, and 45-minute guided demo flow | HCL |
| [**ussvgr/azure-sre-agent-demokit**](https://github.com/ussvgr/azure-sre-agent-demokit) | Terraform-based demo kit with App Service, monitoring, and alert rules | HCL/C# |
| [**tannenbaum-gmbh/sre-agent**](https://github.com/tannenbaum-gmbh/sre-agent) | Consolidated demo resources using Bicep | Bicep |
| [**kohei3110/azure-sre-agent-demo**](https://github.com/kohei3110/azure-sre-agent-demo) | Another community demo setup | HCL |
| [**GomanovNA/azure-sre-ai-agent**](https://github.com/GomanovNA/azure-sre-ai-agent) | GitHub Copilot-powered SRE agent implementation | — |
| [**paulasilvatech/Agentic-Ops-Dev**](https://github.com/paulasilvatech/Agentic-Ops-Dev) | 8-module workshop covering observability + Azure SRE Agent. Includes Terraform, sample apps, Grafana dashboards, and load generation scripts. Three levels: Essential (2h), Standard (4h), Advanced (8h+). | Shell |

> **Note:** The `Azure-Samples` organization does not currently have repositories specifically for SRE Agent. The community repositories above are the primary source of deployable demos.

---

## 13. Official Blog Posts & Announcements

Listed chronologically (newest first):

| Date | Title | Engagement |
|------|-------|------------|
| Jan 23, 2026 | [How to Connect Azure SRE Agent to Azure MCP](https://techcommunity.microsoft.com/blog/appsonazureblog/how-to-connect-azure-sre-agent-to-azure-mcp/4488905) | 571 views |
| Jan 20, 2026 | [Connect Azure SRE Agent to ServiceNow: End-to-End Incident Response](https://techcommunity.microsoft.com/blog/appsonazureblog/connect-azure-sre-agent-to-servicenow-end-to-end-incident-response/4487824) | 1.5K views |
| Dec 26, 2025 | [Context Engineering Lessons from Building Azure SRE Agent](https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200) | 6.1K views |
| Dec 08, 2025 | [Never Explain Context Twice: Introducing Azure SRE Agent Memory](https://techcommunity.microsoft.com/blog/appsonazureblog/never-explain-context-twice-introducing-azure-sre-agent-memory/4473059) | 740 views |
| Dec 04, 2025 | [Proactive Monitoring Made Simple with Azure SRE Agent](https://techcommunity.microsoft.com/blog/appsonazureblog/proactive-monitoring-made-simple-with-azure-sre-agent/4471205) | 989 views |
| Nov 24, 2025 | [Azure SRE Agent: Expanding Observability and Multi-Cloud Resilience](https://techcommunity.microsoft.com/blog/appsonazureblog/azure-sre-agent-expanding-observability-and-multi-cloud-resilience/4472719) | 998 views |
| Nov 18, 2025 | [Reimagining AI Ops with Azure SRE Agent: New Automation, Integration, and Extensibility](https://techcommunity.microsoft.com/blog/appsonazureblog/reimagining-ai-ops-with-azure-sre-agent-new-automation-integration-and-extensibi/4462613) | 3.8K views |
| Oct 01, 2025 | [Expanding the Public Preview of the Azure SRE Agent](https://techcommunity.microsoft.com/blog/appsonazureblog/expanding-the-public-preview-of-the-azure-sre-agent/4458514) | 5.9K views |
| Aug 01, 2025 | [Announcing a Flexible, Predictable Billing Model for Azure SRE Agent](https://techcommunity.microsoft.com/blog/appsonazureblog/announcing-a-flexible-predictable-billing-model-for-azure-sre-agent/4427270) | 3.8K views |
| May 19, 2025 | [Introducing Azure SRE Agent](https://techcommunity.microsoft.com/blog/azurepaasblog/introducing-azure-sre-agent/4414569) | 86K views |

---

## 14. Videos & Learning Resources

### YouTube / Microsoft Sessions

| Title | Source | Duration | Views |
|-------|--------|----------|-------|
| **Use Azure SRE Agent to Automate Tasks and Increase Site Reliability (DEM550)** | Microsoft Developer | 15:52 | 10.9K |
| **Azure SRE Agent: Less Toil, More Uptime, Maximum Innovation** | Microsoft Azure Developers | 15:39 | 2.5K |
| **Fix It Before They Feel It: Proactive .NET Reliability with Azure SRE Agent** | dotnet | 25:34 | 911 |
| **Overview of Azure SRE Agent Preview** | Microsoft / Craig Shoemaker | — | — |
| **SRE Agent First Run Experience** | Azure SRE Agent | 1:37 | 328 |

Additional videos cover topics like incident management with PagerDuty, IaC drift detection, and integration with Logic Apps.

### Official Documentation

| Resource | URL |
|----------|-----|
| Azure SRE Agent Overview | [learn.microsoft.com/en-us/azure/sre-agent/overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) |
| Using an Agent | [learn.microsoft.com/en-us/azure/sre-agent/usage](https://learn.microsoft.com/en-us/azure/sre-agent/usage) |
| Subagent Builder | [learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview) |
| Product Page | [azure.microsoft.com/en-us/products/sre-agent](https://azure.microsoft.com/en-us/products/sre-agent) |

---

## 15. Key Considerations for Your Demo

### Before the Demo

- [ ] **Region:** Deploy to **East US 2** (primary supported region).
- [ ] **Firewall:** Allowlist `*.azuresre.ai`.
- [ ] **Permissions:** Ensure RBAC Administrator or User Access Administrator permissions.
- [ ] **Cost awareness:** Budget for 4 AAU/hour baseline + active task costs. Tear down demo resources after presenting.
- [ ] **Preview limitations:** English-only chat interface. Feature availability may vary by tenant.

### Demo Best Practices

1. **Start with the "why":** Explain the operational toil problem (alert fatigue, manual RCA, knowledge silos) before showing the product.
2. **Show, don't tell:** Use the chat interface live. Ask the agent real questions about your deployed resources.
3. **Demonstrate the approval workflow:** Show that write actions require human approval — this addresses governance and security concerns immediately.
4. **Use proactive + reactive scenarios together:** Show scheduled monitoring (proactive) and incident response (reactive) to demonstrate the full value.
5. **Highlight the subagent builder:** The no-code builder resonates with operations teams who don't want to write automation code.
6. **End with the integration story:** Show how findings flow to GitHub issues, Teams notifications, or ServiceNow — this demonstrates enterprise readiness.

### What NOT to Do

- Don't demo in a subscription with sensitive production resources without proper scoping.
- Don't claim GA-level SLAs — this is still in public preview.
- Don't overstate multi-cloud capabilities — they work through MCP connectors and are expanding but not at parity with native Azure support.

### Talk Track: Key Messages

- *"Azure SRE Agent reduces MTTR from hours to minutes by automating the investigation process that SREs do manually today."*
- *"It brings built-in Azure expertise — it already knows how Azure services work, so it can use `az` CLI and `kubectl` intelligently without custom scripting."*
- *"The approval workflow ensures humans stay in control. The agent proposes, you approve."*
- *"It has already saved over 20,000 engineering hours inside Microsoft."*
- *"You can extend it with the no-code subagent builder and connect it to your existing tools through MCP."*

---

## Appendix: Quick Reference Links

| Resource | URL |
|----------|-----|
| Create an Agent (Portal) | `https://aka.ms/sreagent/portal` |
| Product Page | `https://azure.microsoft.com/en-us/products/sre-agent` |
| Official Docs | `https://learn.microsoft.com/en-us/azure/sre-agent/overview` |
| GitHub Issues & Feedback | `https://github.com/microsoft/sre-agent` |
| Community Demo Kit | `https://github.com/jiratouchmhp/azure-sre-agent-demo` |
| Agentic Ops Workshop | `https://github.com/paulasilvatech/Agentic-Ops-Dev` |
| Terraform Demo Kit | `https://github.com/ussvgr/azure-sre-agent-demokit` |

---

*This document was compiled from official Microsoft documentation, Microsoft Tech Community blog posts, and community GitHub repositories. All sources are linked inline. Content reflects the public preview state as of February 2026.*
