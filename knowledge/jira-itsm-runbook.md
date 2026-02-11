# Contoso Meals — Jira ITSM Escalation Procedures

## Jira Service Management Integration

### Connection Details
- **Jira Instance:** `jira-sm` Container App in `rg-contoso-meals`
- **MCP Bridge:** `mcp-atlassian` Container App, port 9000, endpoint `/mcp`
- **Project Key:** CONTOSO
- **Issue Type for Incidents:** Incident

### Incident Creation Guidelines
When creating a Jira incident ticket via the SRE Agent:
1. **Summary:** Clear, actionable title describing the issue (e.g., "Payment-service pod failures causing order checkout errors")
2. **Priority:** Set based on business impact analysis:
   - **P1 (Critical):** Full outage — customers cannot place orders (order-api down)
   - **P1 (Critical):** Payment failures > 30% during peak traffic
   - **P2 (High):** Partial degradation — payments intermittently failing, error rate 10-30%
   - **P3 (Medium):** Menu browsing degraded — Cosmos DB throttling, menu-api latency
   - **P4 (Low):** Non-customer-facing issues — log ingestion delays, metric gaps
3. **Labels:** Always include `sre-agent`, the affected service name (e.g., `payment-service`), and `production`
4. **Description:** Include investigation findings, error rates, affected pods, timeline, and root cause

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
- P1 incidents: 15-minute response SLA
- P2 incidents: 30-minute response SLA
- Track cycle time from creation to resolution

### Cross-Incident Pattern Analysis
Periodically search for recurring incidents:
- JQL: `project = CONTOSO AND labels = <service-name> AND created >= -7d ORDER BY created DESC`
- If the same service has 3+ incidents in 7 days, escalate to the service owner's engineering lead
- Recommend permanent fixes (PodDisruptionBudgets, circuit breakers, autoscaling adjustments)
