# Contoso Meals — Jira ITSM Escalation Procedures

## Jira Service Management Integration

### Connection Details
- **Jira Instance:** `jira-sm` Container App in `rg-contoso-meals`
- **MCP Bridge:** `mcp-atlassian` Container App, port 9000, endpoint `/mcp`
- **Project Name:** Contoso Meals Operations
- **Project Key:** CONTOSO
- **Issue Type for Incidents:** Task
- **Available Fields:** Summary (required), Description, Priority, Attachment

### Incident Creation Guidelines
When creating a Jira incident ticket via the SRE Agent:
1. **Summary:** Clear, actionable title describing the issue (e.g., "Payment-service pod failures causing order checkout errors")
2. **Priority:** Set based on business impact analysis using Jira priority values:
   - **Blocker:** Complete system outage — all services down, no customer transactions possible
   - **Highest:** Full outage — customers cannot place orders (order-api down) or payment failures > 30% during peak traffic
   - **High:** Partial degradation — payments intermittently failing, error rate 10-30%
   - **Medium:** Menu browsing degraded — Cosmos DB throttling, menu-api latency
   - **Low:** Non-customer-facing issues — log ingestion delays, metric gaps
   - **Lowest:** Cosmetic or informational items — minor log warnings, non-impacting alerts
   - **Minor:** Improvement suggestions from post-incident reviews, technical debt items
3. **Labels:** Always include `sre-agent`, the affected service name (e.g., `payment-service`), and `production`
4. **Description:** Include investigation findings, error rates, affected pods, timeline, and root cause

### Ticket Assignment
Assign tickets to the service owner based on the affected component:

| Service | Assignee | Jira Username |
|---------|----------|---------------|
| payment-service | Alana Grant | `agrant-sd-demo` |
| order-api | Jennifer Evans | `jevans-sd-demo` |
| menu-api | Mitch Davis | `mdavis-sd-demo` |
| PostgreSQL / database | Ryan Lee | `rlee-sd-demo` |
| AKS node pool / infra | Vincent Wong | `vwong-sd-demo` |

- Use `jira_assign_issue` with the Jira username (e.g., `agrant-sd-demo`) after ticket creation
- If multiple services are affected, assign to the primary impacted service owner
- For cross-cutting issues, assign to Vincent Wong (infra) and mention others in comments

### Investigation Work Notes
While investigating, post findings as Jira comments in real time:
- Each investigation step should be a separate comment
- Include quantitative data (error rates, latency percentiles, connection counts)
- Note blast radius — which services are affected and which are healthy
- Reference the runbook when applicable

### Ticket Lifecycle
1. **Open** → Created with initial investigation findings
2. **In Progress** → Agent is actively investigating (use `jira_transition_issue`)
3. **Resolved** → Issue confirmed fixed, include resolution summary with:
   - Root cause
   - Incident duration
   - Business impact (number of failed transactions)
   - Remediation applied or recommended
4. **Closed** → Post-incident review completed

### SLA Tracking
- Use `jira_get_issue_sla` to check SLA compliance
- **Blocker / Highest** incidents: 15-minute response SLA
- **High** incidents: 30-minute response SLA
- **Medium** incidents: 1-hour response SLA
- **Low / Lowest / Minor** incidents: Best-effort response
- Track cycle time from creation to resolution

### Cross-Incident Pattern Analysis
Periodically search for recurring incidents:
- JQL: `project = CONTOSO AND labels = <service-name> AND created >= -7d ORDER BY created DESC`
- If the same service has 3+ incidents in 7 days, escalate to the service owner's engineering lead
- Recommend permanent fixes (PodDisruptionBudgets, circuit breakers, autoscaling adjustments)
