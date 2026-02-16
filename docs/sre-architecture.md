# Contoso Meals — SRE Architecture & Agent Topology

> Comprehensive view of the Azure infrastructure, application services, SRE Agent configuration, and autonomous incident management pipeline for the Contoso Meals platform.

---

## 1. Azure Infrastructure Overview

All resources are deployed into a single resource group (`rg-contoso-meals`) in **Sweden Central** via Bicep with Azure Verified Modules (AVM).

```mermaid
graph TD
    subgraph RG["rg-contoso-meals (Sweden Central)"]
        subgraph Compute["Compute"]
            AKS["AKS Cluster<br/>(aks-contoso-meals)<br/>System pool: 2× B2s<br/>Workload pool: 1× B2s"]
            CAE["Container App Environment<br/>(cae-contoso-meals)<br/>Consumption + Dedicated-D4"]
        end

        subgraph Apps["Application Services"]
            OA["order-api<br/>(AKS, port 8080)"]
            PS["payment-service<br/>(AKS, port 8080)"]
            MA["menu-api<br/>(Container App, port 8080)"]
            WUI["web-ui<br/>(Container App, port 8080)"]
        end

        subgraph ITSM["ITSM Layer"]
            JIRA["jira-sm<br/>(Container App, D4 profile)<br/>4 CPU / 8Gi RAM"]
            MCPA["mcp-atlassian<br/>(Container App, port 9000)"]
        end

        subgraph Data["Data Stores"]
            PG["PostgreSQL Flexible Server<br/>(psql-contoso-meals-db)<br/>Standard_B1ms"]
            CDB["Cosmos DB Serverless<br/>(cosmos-contoso-meals)"]
            KV["Key Vault<br/>(kv-contosomealssc)"]
            ST["Storage Account<br/>(stcontosomeals)<br/>Jira home (Azure Files)"]
        end

        subgraph Observability["Observability"]
            LAW["Log Analytics Workspace<br/>(law-contoso-meals)"]
            APPI["Application Insights<br/>(appi-contoso-meals)"]
            MON["Azure Monitor<br/>(alert rules + action groups)"]
            WB["Workbook Dashboard"]
        end

        subgraph Reliability["Reliability Testing"]
            CHAOS["Chaos Studio<br/>(pod-kill + node-pool experiments)"]
            ALT["Azure Load Testing<br/>(lt-contoso-meals)"]
        end

        subgraph Identity["Identity & Access"]
            MI["User-Assigned MI<br/>(id-contoso-meals-sre-agent)"]
            SREA["Azure SRE Agent<br/>(contoso-meals-sre)"]
        end
    end

    AKS --> OA & PS
    CAE --> MA & WUI & JIRA & MCPA
    OA --> PG
    PS --> PG
    MA --> CDB
    JIRA --> PG
    ST --> JIRA
    APPI --> LAW
    MON --> LAW
    WB --> LAW
    AKS --> LAW
    CAE --> LAW
    CHAOS --> AKS
    ALT --> OA & PS & MA
    MI --> SREA
    SREA --> APPI
    MON -->|"alert triggers"| SREA
```

---

## 2. Application Service Communication

```mermaid
graph LR
    CUSTOMER["Customer<br/>(Browser)"] --> WUI["web-ui<br/>(React + Nginx)"]

    WUI -->|"GET /restaurants<br/>GET /menus"| MA["menu-api<br/>(Container App)"]
    WUI -->|"POST /orders"| OA["order-api<br/>(AKS)"]
    WUI -->|"POST /pay"| PS["payment-service<br/>(AKS)"]

    MA --> CDB[("Cosmos DB<br/>catalogdb<br/>├ restaurants (/city)<br/>└ menus (/restaurantId)")]
    OA --> PG[("PostgreSQL<br/>ordersdb")]
    PS --> PG

    OA -.->|"validates payment<br/>(internal)"| PS

    PS -.->|"fault injection<br/>(FAULT_ENABLED=true)"| FAIL["Simulated 500s<br/>(50% failure rate)"]

    style FAIL fill:#c0392b,color:#fff,stroke-dasharray: 5
```

| Flow | Protocol | Path | Data Store |
|------|----------|------|------------|
| Browse restaurants | HTTPS | Customer → web-ui → menu-api → Cosmos DB | `catalogdb.restaurants` |
| View menu | HTTPS | Customer → web-ui → menu-api → Cosmos DB | `catalogdb.menus` |
| Place order | HTTPS | Customer → web-ui → order-api → PostgreSQL | `ordersdb` |
| Process payment | HTTPS | Customer → web-ui → payment-service → PostgreSQL | `ordersdb` |
| Fault injection | Internal | payment-service returns 500 when `FAULT_ENABLED=true` | — |

---

## 3. SRE Agent — Tool & Connector Topology

The Azure SRE Agent (`Microsoft.App/agents@2025-05-01-preview`) connects to Azure resources and ITSM systems via MCP servers, and uses built-in connectors for Teams, Outlook, and memory.

```mermaid
graph TD
    SREA["Azure SRE Agent<br/>(contoso-meals-sre)<br/>Mode: Review / Autonomous"]

    subgraph AzureMCP["Azure MCP Server"]
        direction TB
        CLI_R["RunAzCliReadCommands"]
        CLI_W["RunAzCliWriteCommands"]
        CLI_H["GetAzCliHelp"]
        MET["ListAvailableMetrics<br/>GetMetricsTimeSeriesAnalysis<br/>PlotTimeSeriesData<br/>GetMultipleTimeSeries<br/>GetTimeSeriesAnalysis"]
        TEL["QueryAppInsightsByResourceId<br/>QueryLogAnalyticsByResourceId"]
        HLT["GetResourceHealthInfo"]
    end

    subgraph JiraMCP["mcp-atlassian MCP Server<br/>(Container App, port 9000)"]
        direction TB
        J_CRUD["jira_create_issue<br/>jira_update_issue<br/>jira_delete_issue"]
        J_FLOW["jira_transition_issue<br/>jira_add_comment<br/>jira_add_worklog"]
        J_READ["jira_get_issue<br/>jira_search<br/>jira_get_all_projects"]
        J_AGILE["jira_get_agile_boards<br/>jira_get_sprint_issues<br/>jira_create_sprint"]
        J_LINK["jira_create_issue_link<br/>jira_link_to_epic<br/>jira_create_remote_issue_link"]
    end

    subgraph Builtin["Built-in Connectors"]
        TEAMS["PostTeamsMessage"]
        EMAIL["SendOutlookEmail"]
        MEM["SearchMemory<br/>(Knowledge Base)"]
        GH["CreateGithubIssue<br/>FindConnectedGitHubRepo"]
        SCHED["CreateScheduledMonitoringTask"]
    end

    SREA -->|"User-Assigned MI<br/>(id-contoso-meals-sre-agent)"| AzureMCP
    SREA -->|"API Token auth<br/>(streamable-http)"| JiraMCP
    SREA --> Builtin

    style SREA fill:#2c3e50,color:#fff
    style AzureMCP fill:#1a5276,color:#fff
    style JiraMCP fill:#7d3c98,color:#fff
    style Builtin fill:#1e8449,color:#fff
```

### MCP Connector Configuration

| Property | Azure MCP Server | mcp-atlassian |
|----------|-----------------|---------------|
| **Transport** | Streamable HTTP | Streamable HTTP |
| **Identity** | User-Assigned MI (`id-contoso-meals-sre-agent`) | API Token (Jira admin) |
| **Environment** | `AZURE_CLIENT_ID`, `AZURE_TOKEN_CREDENTIALS=ManagedIdentityCredential` | `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN` |
| **Arguments** | `-y, @azure/mcp, server, start` | `--transport streamable-http --stateless --port 9000` |
| **Tool Count** | 42+ | 34 |
| **Scope** | All resources in `rg-contoso-meals` + cross-RG targets | CONTOSO Jira project |

### Knowledge Base

The SRE Agent's memory is seeded with operational runbooks via `SearchMemory`:

| Runbook | File | Contents |
|---------|------|----------|
| Contoso Meals Runbook | `knowledge/contoso-meals-runbook.md` | Service ownership, SLA targets, escalation paths, deployment info |
| Jira ITSM Runbook | `knowledge/jira-itsm-runbook.md` | Project key (CONTOSO), issue types, priority mappings, label conventions, assignee table |

---

## 4. Subagent Hierarchy & Handoff Chain

Four specialized subagents handle distinct phases of the incident lifecycle. The IncidentHandler is the entry point; it delegates to downstream agents based on investigation findings.

```mermaid
graph TD
    ALERT["Azure Monitor Alert<br/>(ag-contoso-meals-sre)"] -->|triggers| SREA["Azure SRE Agent"]
    SREA -->|"incident detected"| IH

    subgraph IH_BOX["ContosoMealsIncidentHandler"]
        IH["Phase 1: Intake<br/>Acknowledge alert, identify service"]
        IH2["Phase 2: Investigate<br/>App Insights, AKS logs, activity logs"]
        IH3["Phase 3: Assess<br/>Severity (P1 if error > 30%)"]
        IH4["Phase 4: ITSM<br/>Create Jira ticket, assign owner, email"]
        IH5["Phase 5: Decision"]
        IH --> IH2 --> IH3 --> IH4 --> IH5
    end

    IH5 -->|"Known pattern<br/>+ pre-approved fix"| AR
    IH5 -->|"Chaos experiment<br/>detected"| RV
    IH5 -->|"Unknown / complex"| HUMAN["Human Escalation<br/>(Jira + Teams)"]

    subgraph AR_BOX["ContosoMealsAutoRemediator"]
        AR["Pre-check<br/>(no chaos, no rollout)"]
        AR2["Execute Fix<br/>(from 6 approved playbooks)"]
        AR3["Validate<br/>(error rate < 5%, resources healthy)"]
        AR --> AR2 --> AR3
    end

    AR3 -->|"success"| RV
    AR3 -->|"failed after 2 retries"| HUMAN

    subgraph RV_BOX["ContosoMealsResilienceValidator"]
        RV["Compare metrics<br/>(during vs baseline)"]
        RV2["Evaluate availability<br/>(target: 99%)"]
        RV3["Recommend improvements<br/>(PDBs, circuit breakers, retries)"]
        RV --> RV2 --> RV3
    end

    RV3 -->|"availability < 99%"| GHISSUE["GitHub Issue<br/>(improvement recommendations)"]
    RV3 -->|"update Jira"| CLOSE["Jira → Closed"]

    subgraph HC_BOX["ContosoMealsHealthCheck (standalone)"]
        HC["Scheduled: every 24h"]
        HC2["Anomaly detection<br/>(z-score ≥ 3, MAD ≥ 3)"]
        HC3["HTML report<br/>(inline, 6 resource checks)"]
        HC --> HC2 --> HC3
    end

    style IH_BOX fill:#4a90d9,color:#fff
    style AR_BOX fill:#e67e22,color:#fff
    style RV_BOX fill:#27ae60,color:#fff
    style HC_BOX fill:#8e44ad,color:#fff
    style HUMAN fill:#c0392b,color:#fff
```

### Subagent Tool Matrix

| Tool | IncidentHandler | AutoRemediator | ResilienceValidator | HealthCheck |
|------|:-:|:-:|:-:|:-:|
| `RunAzCliReadCommands` | ✅ | ✅ | ✅ | ✅ |
| `RunAzCliWriteCommands` | ✅ | ✅ | — | — |
| `QueryAppInsightsByResourceId` | ✅ | ✅ | ✅ | ✅ |
| `QueryLogAnalyticsByResourceId` | ✅ | ✅ | ✅ | ✅ |
| `ListAvailableMetrics` | ✅ | ✅ | — | — |
| `PlotTimeSeriesData` | ✅ | ✅ | — | — |
| `GetMetricsTimeSeriesAnalysis` | ✅ | ✅ | — | — |
| `GetMultipleTimeSeries` | — | — | — | ✅ |
| `GetTimeSeriesAnalysis` | — | — | — | ✅ |
| `GetResourceHealthInfo` | — | ✅ | — | — |
| `SearchMemory` | ✅ | ✅ | ✅ | — |
| `PostTeamsMessage` | ✅ | ✅ | — | — |
| `SendOutlookEmail` | ✅ | ✅ | — | ✅ |
| `CreateScheduledMonitoringTask` | — | ✅ | — | — |
| `CreateGithubIssue` | — | — | ✅ | — |
| `FindConnectedGitHubRepo` | — | — | ✅ | — |
| `GetAzCliHelp` | ✅ | ✅ | — | — |
| **Jira MCP tools** | 8 | 32 | 5 | — |

---

## 5. Auto-Remediation Playbooks

The AutoRemediator executes only pre-approved actions with strict safety ceilings.

```mermaid
graph TD
    TRIGGER["Handoff from IncidentHandler<br/>(with Jira key)"] --> PRECHECK

    PRECHECK{"Pre-checks pass?<br/>• No active chaos<br/>• No rollout in progress<br/>• Known failure pattern"}

    PRECHECK -->|"No"| ESCALATE["Escalate to Human"]

    PRECHECK -->|"Yes"| MATCH{"Match Playbook"}

    MATCH -->|"CrashLoopBackOff"| S1["S1: Restart Deployment<br/>kubectl rollout restart<br/>Validate: 60s, pods Running, error < 5%<br/>Max 2 attempts"]

    MATCH -->|"OOMKilled"| S2["S2: Increase Memory<br/>kubectl set resources --limits=memory=512Mi<br/>Validate: 120s, no OOMKilled<br/>Ceiling: 512Mi, 1 attempt"]

    MATCH -->|"menu-api slow"| S3["S3: Scale Container App<br/>az containerapp update --min-replicas 3 --max-replicas 10<br/>Validate: 90s, replicas up, P95 < 500ms<br/>Schedule scale-down after 30min"]

    MATCH -->|"Cosmos 429s"| S4["S4: Increase RU/s<br/>az cosmosdb sql database throughput update --throughput 1000<br/>Validate: 30s, 429 rate = 0<br/>MUST revert to 400 RU/s after 1h"]

    MATCH -->|"PG connection exhaustion"| S5["S5: Terminate Idle Connections<br/>Kill connections > 30min idle<br/>Read-only confirmation first"]

    MATCH -->|"Node pool at zero"| S6["S6: Scale Node Pool<br/>az aks nodepool scale --node-count 1<br/>Validate: 180s, node Ready, pods Running<br/>Max 1 attempt"]

    S1 & S2 & S3 & S4 & S5 & S6 --> VALIDATE{"Validation Passed?"}
    VALIDATE -->|"Yes"| JIRA_OK["Update Jira → Resolved<br/>Hand off to ResilienceValidator"]
    VALIDATE -->|"No"| ESCALATE

    style ESCALATE fill:#c0392b,color:#fff
    style JIRA_OK fill:#27ae60,color:#fff
```

### Safety Guardrails

| Rule | Ceiling |
|------|---------|
| AKS deployment restarts | `production` namespace only (`payment-service`, `order-api`) |
| Memory limit increase | Max 512Mi per container |
| menu-api replicas | Min 1, max 10 |
| Cosmos DB RU/s | Max 1000 RU/s, must revert after 1h |
| Node pool scaling | Min 0, max 3 nodes |
| **Forbidden** | Delete resources, modify network/NSG/RBAC, scale beyond ceilings, Key Vault changes, actions outside `rg-contoso-meals` |

---

## 6. End-to-End Incident Lifecycle

Complete sequence from alert to incident closure, showing all participants and data flow.

```mermaid
sequenceDiagram
    participant AM as Azure Monitor
    participant AG as Action Group
    participant SRE as SRE Agent
    participant IH as IncidentHandler
    participant AI as App Insights
    participant AKS as AKS Cluster
    participant JIRA as Jira SM
    participant AR as AutoRemediator
    participant RV as ResilienceValidator
    participant GH as GitHub

    Note over AM: Alert condition met<br/>(e.g., payment-service 5xx > 30%)
    AM->>AG: Fire alert (ag-contoso-meals-sre)
    AG->>SRE: Notify SRE Agent
    SRE->>IH: Delegate to IncidentHandler

    rect rgb(70, 130, 180)
        Note over IH: Phase 1 — Intake
        IH->>AM: Acknowledge alert (PATCH alertState)
        IH->>IH: SearchMemory → load runbooks
        IH->>IH: Identify affected service
    end

    rect rgb(70, 130, 180)
        Note over IH: Phase 2 — Investigation
        IH->>AI: Query error rate, P95, dependencies (30min)
        AI-->>IH: 45% 5xx on POST /pay, P95 = 2.3s
        IH->>AKS: QueryLogAnalytics → KubePodInventory
        AKS-->>IH: payment-service: 3/3 pods CrashLoopBackOff
        IH->>AM: Check activity logs (2h)
        AM-->>IH: No recent deployments
    end

    rect rgb(70, 130, 180)
        Note over IH: Phase 3-4 — Assess + ITSM
        IH->>IH: Severity = P1 (error > 30%, critical path)
        IH->>JIRA: Create issue (CONTOSO-42, P1, payment-service)
        IH->>JIRA: Assign to agrant-sd-demo
        IH->>JIRA: Transition → In Progress
        IH->>IH: SendOutlookEmail (incident summary)
    end

    rect rgb(230, 126, 34)
        Note over AR: Remediation
        IH->>AR: Handoff (known pattern: CrashLoopBackOff)
        AR->>AR: Pre-check: no chaos, no rollout
        AR->>AKS: kubectl rollout restart deployment/payment-service
        Note over AR: Wait 60s
        AR->>AI: Validate error rate
        AI-->>AR: Error rate = 2% ✅
        AR->>JIRA: Add remediation log comment
        AR->>JIRA: Transition → Resolved
    end

    rect rgb(39, 174, 96)
        Note over RV: Resilience Validation
        AR->>RV: Handoff
        RV->>AI: Compare during vs baseline metrics
        AI-->>RV: Availability dropped to 97.2%
        RV->>GH: Create issue (add PDB, circuit breaker)
        RV->>JIRA: Add resilience analysis comment
        RV->>JIRA: Transition → Closed
    end
```

---

## 7. Monitoring & Alerting Pipeline

```mermaid
graph LR
    subgraph Sources["Telemetry Sources"]
        AKS_T["AKS<br/>(container logs, pod events)"]
        CA_T["Container Apps<br/>(request logs, scaling)"]
        PG_T["PostgreSQL<br/>(diagnostics)"]
        CDB_T["Cosmos DB<br/>(diagnostics, RU metrics)"]
        AI_T["App Insights<br/>(requests, dependencies, exceptions)"]
    end

    LAW["Log Analytics<br/>Workspace"]

    AKS_T --> LAW
    CA_T --> LAW
    PG_T --> LAW
    CDB_T --> LAW
    AI_T --> LAW

    subgraph Alerts["Alert Rules"]
        A1["payment-service 5xx > 10%<br/>(Sev 1)"]
        A2["order-api P95 > 2s<br/>(Sev 2)"]
        A3["Node NotReady<br/>(Sev 1)"]
        A4["Node pool count = 0<br/>(Sev 0, Critical)"]
        A5["Pod unschedulable<br/>(Sev 1)"]
        A6["Failure Anomalies<br/>(Smart Detection)"]
    end

    LAW --> Alerts

    AG["Action Group<br/>(ag-contoso-meals-sre)"]

    Alerts --> AG
    AG -->|"notify"| SREA["SRE Agent"]
    SREA -->|"investigate + remediate"| IH["Subagent Chain"]

    subgraph Dashboard["Observability"]
        WB_D["Contoso Meals Workbook<br/>(service health, error rates,<br/>latency, pod status)"]
    end

    LAW --> WB_D
```

---

## 8. Deployment Architecture (IaC)

```mermaid
graph TD
    AZD["azd up / az deployment sub create"] -->|"deploys"| BICEP["infra/main.bicep<br/>(targetScope: subscription)"]

    BICEP --> RG["Resource Group<br/>(rg-contoso-meals)"]

    BICEP -->|"AVM modules"| AVM
    BICEP -->|"Custom modules"| CUSTOM

    subgraph AVM["Azure Verified Modules"]
        M_AKS["avm/res/container-service/managed-cluster"]
        M_CAE["avm/res/app/managed-environment"]
        M_CA["avm/res/app/container-app"]
        M_PG["Custom: modules/postgres.bicep"]
        M_CDB["avm/res/document-db/database-account"]
        M_KV["avm/res/key-vault/vault"]
        M_LAW["avm/res/operational-insights/workspace"]
        M_APPI["avm/res/insights/component"]
        M_ACR["avm/res/container-registry/registry"]
        M_LT["avm/res/load-test-service/load-test"]
        M_MI["avm/res/managed-identity/user-assigned-identity"]
        M_ST["avm/res/storage/storage-account"]
    end

    subgraph CUSTOM["Custom Modules"]
        M_MON["modules/monitoring.bicep<br/>(alert rules + action group)"]
        M_CHAOS["modules/chaos.bicep<br/>(pod-kill experiment)"]
        M_CHAOSN["modules/chaos-node-pool.bicep<br/>(node pool failure)"]
        M_ROLE["modules/sre-agent-role.bicep<br/>(tiered RBAC: High/Low)"]
        M_ROLET["modules/sre-agent-role-target.bicep<br/>(cross-RG monitoring)"]
        M_AGENT["modules/sre-agent.bicep<br/>(SRE Agent resource)"]
        M_WB["modules/workbooks.bicep<br/>(dashboard)"]
        M_ACR_PULL["modules/acr-pull-role.bicep"]
    end

    RG --> AVM & CUSTOM

    style AVM fill:#1a5276,color:#fff
    style CUSTOM fill:#7d3c98,color:#fff
```

### Post-Deployment Scripts

| Script | Purpose |
|--------|---------|
| `scripts/deploy.sh` | Full automated deployment (Bicep + app build + push + K8s apply) |
| `scripts/post-provision.sh` | Post-Bicep setup (AKS credentials, database init) |
| `scripts/post-deploy.sh` | Post-app-deploy (Container App env var injection) |
| `scripts/seed-data.sh` | Seed Cosmos DB with restaurant/menu data |
| `scripts/setup-jira.sh` | Configure Jira SM (project, users, workflows) |
| `scripts/setup-node-alerts.sh` | Create node pool monitoring alerts |
| `scripts/generate-load.sh` | Generate baseline traffic for monitoring |
| `scripts/start-lunch-rush.sh` | Start chaos load test scenario |
| `scripts/start-node-failure.sh` | Trigger node pool failure chaos experiment |
